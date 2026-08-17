#!/usr/bin/env bash
#@kind      util
#@platform  macos
#@claude    call
#@purpose   Audit an existing feature package against the CLAUDE.md rules and print ranked recommendations.
#@usage     audit-feature.sh <feature-path-or-name> [--tsv] [--strict]
#@in        feature:path|name(resolved under Packages/Features/) --tsv:flag(machine output) --strict:flag(warnings fail too)
#@out       stdout:findings grouped by severity, each with a recommendation + xed hint; --tsv emits severity,rule,file,line,finding,fix
#@exit      0=clean 1=findings 2=usage 3=not a feature package
#@effects   read-only. Never compiles (CLAUDE.md 2.12) and never edits the feature
# Audit an existing feature package and say what to change.
#
#   ./Scripts/claude-utils/audit-feature.sh FeatureSettings
#   ./Scripts/claude-utils/audit-feature.sh Packages/Features/FeatureSettings --strict
#   ./Scripts/claude-utils/audit-feature.sh FeatureSettings --tsv > findings.tsv
#
# `new-feature` scaffolds from nothing and `/verify` walks a diff. Neither answers
# "this feature already exists — what is wrong with it?". That is this.
#
# REPORTS ONLY. It never edits the feature. Adding a missing content state or a
# mock is a judgement call about behaviour, and a script that guessed at one would
# produce code that compiles and lies. The findings name the file and line; the
# fixing is yours or Claude's, with `docs/patterns/change.md` as the procedure.
#
# Every check is static text analysis — no compiler, no build (CLAUDE.md §2.12).
# Two of them are HEURISTIC and marked as such in the output: force-unwrap and
# raw-string detection both over-report, because telling `label!` from `a != b`,
# or a user-facing string from an accessibility identifier, needs a parser. Read
# those rows before acting; the rest are exact.
. "$(dirname "$0")/_common.sh"

usage_text() { usage_from "$0"; }

[ $# -ge 1 ] || usage
case "$1" in -h|--help) usage "$EX_OK" ;; esac

ARG="$1"; shift
TSV=0; STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tsv)     TSV=1; shift ;;
    --strict)  STRICT=1; shift ;;
    -h|--help) usage "$EX_OK" ;;
    *)         die "unknown argument: $1" "$EX_USAGE" ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Accept a path or a bare name, so both `FeatureSettings` and the path you just
# tab-completed work.
if [ -d "$ARG" ]; then
  PKG="$(cd "$ARG" && pwd)"
elif [ -d "$ROOT/$ARG" ]; then
  PKG="$(cd "$ROOT/$ARG" && pwd)"
elif [ -d "$ROOT/Packages/Features/$ARG" ]; then
  PKG="$(cd "$ROOT/Packages/Features/$ARG" && pwd)"
else
  die "no such feature: $ARG
    Looked in: $ARG · $ROOT/$ARG · $ROOT/Packages/Features/$ARG
    Available:
$(ls -1 "$ROOT/Packages/Features" 2>/dev/null | sed 's/^/      /' || printf '      (none — Packages/Features does not exist)')" "$EX_USAGE"
fi

NAME="$(basename "$PKG")"
[ -f "$PKG/Package.swift" ] || die "$NAME has no Package.swift — not a package" "$EX_PRECOND"

SRC="$PKG/Sources/$NAME"
[ -d "$SRC" ] || SRC="$(find "$PKG/Sources" -maxdepth 1 -type d ! -path "$PKG/Sources" 2>/dev/null | head -1)"
[ -n "$SRC" ] && [ -d "$SRC" ] || die "$NAME has no Sources/ directory" "$EX_PRECOND"

TMP="${TMPDIR:-/tmp}/ga-audit.$$"
trap 'rm -f "$TMP"' EXIT INT TERM
: > "$TMP"

# finding <severity> <rule> <file> <line> <finding> <fix>
# One row per problem. The `fix` column is the recommendation — a finding without
# one is a complaint, and this script exists to be actionable.
finding() {
  _fp="${3#$PKG/}"; _fp="${_fp#$ROOT/}"     # package-relative, then repo-relative
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$1" "$2" "$_fp" "$4" "$5" "$6" >> "$TMP"
}

# swift_files — sources only, never the test target: a force-unwrap in a test is
# allowed (§2.7) and flagging it would train you to ignore the rule.
swift_files() { find "$SRC" -name '*.swift' -type f 2>/dev/null | sort; }

# -H is load-bearing: `grep -n` omits the filename when handed exactly ONE file,
# so a single-file feature returned `line:content` and every caller's
# `IFS=: read -r f ln rest` shifted by a field — producing a report full of source
# text in the line column. -H forces the prefix whatever the file count.
hits() { grep -nHE "$1" $(swift_files) 2>/dev/null; }

# ── Structure (the new-feature layout) ─────────────────────────────────────
for d in Models Services ViewModels Views Localization DI; do
  [ -d "$SRC/$d" ] || finding warn structure "$SRC/$d" 0 \
    "no $d/ directory" \
    "Add Sources/$NAME/$d/ — the layout in the new-feature skill §4"
done

[ -f "$PKG/$NAME.md" ] || finding warn package-doc "$PKG/$NAME.md" 0 \
  "the feature has no $NAME.md" \
  "Write it — package, used-by, when-to-read, screens, routes, decisions (new-feature §8)"

find "$PKG/Tests" -name '*.swift' -type f >/dev/null 2>&1 || finding error tests "$PKG/Tests" 0 \
  "no test target" \
  "Add Tests/${NAME}Tests/ — standalone package tests are what enforce the boundaries (§9)"

ls "$SRC/DI/"*Assembly.swift >/dev/null 2>&1 || finding error di-assembly "$SRC/DI" 0 \
  "no <Name>Assembly.swift" \
  "Add DI/${NAME#Feature}Assembly.swift — the only file that may see DIContainer (§2.6)"

ls "$SRC/Localization/"*.xcstrings >/dev/null 2>&1 || finding warn localization "$SRC/Localization" 0 \
  "no .xcstrings catalog" \
  "Add Localization/${NAME#Feature}.xcstrings — every user-facing string needs a key (§2.3)"

# ── §2.1 no sibling feature import ─────────────────────────────────────────
grep -nE '\.package\(path:[^)]*Features/' "$PKG/Package.swift" 2>/dev/null | while IFS=: read -r ln rest; do
  case "$rest" in *"$NAME"*) continue ;; esac
  finding error sibling-import "$PKG/Package.swift" "$ln" \
    "manifest depends on another feature package" \
    "Remove it. Features talk through Core protocols and navigate by Route value (§2.1)"
done
hits '^[[:space:]]*import[[:space:]]+Feature[A-Z]' | while IFS=: read -r f ln rest; do
  case "$rest" in *"$NAME"*) continue ;; esac
  finding error sibling-import "$f" "$ln" \
    "imports a sibling feature:$(printf '%s' "$rest" | sed 's/^[[:space:]]*//')" \
    "Route through Core, or navigate by Route value (§2.1)"
done

# ── §2.2 third-party types must not cross a module boundary ────────────────
KNOWN='Foundation|SwiftUI|Observation|OSLog|Core|DesignSystem|Navigation|DIKit|StorageKit|LocalizationKit|LoggingKit|NotificationKit|Messaging|Testing|XCTest|UIKit|AppKit|Combine'
hits '^[[:space:]]*import[[:space:]]+[A-Za-z_]' | while IFS=: read -r f ln rest; do
  mod=$(printf '%s' "$rest" | sed 's/^[[:space:]]*import[[:space:]]*//;s/[[:space:]].*//')
  case "$mod" in
    Feature*) continue ;;                       # handled above
    Combine)
      finding warn legacy-concurrency "$f" "$ln" \
        "imports Combine" \
        "No Combine in new code — async/await and AsyncSequence instead (§1)" ;;
    *)
      printf '%s' "$mod" | grep -qE "^($KNOWN)$" || finding error vendor-import "$f" "$ln" \
        "imports '$mod', which is not a first-party module" \
        "Wrap it: protocol in Core, one implementation in ${mod}Wrapper, our types at the boundary (§7)" ;;
  esac
done

# ── §2.4 no system message surface ─────────────────────────────────────────
hits '\.alert\(|\.confirmationDialog\(|UIAlertController|NSAlert\(' | while IFS=: read -r f ln rest; do
  finding error message-surface "$f" "$ln" \
    "system alert or dialog used directly" \
    "Route it through MessagePresenting — one presenter for the whole app (§2.4)"
done

# ── §2.5 every content state ───────────────────────────────────────────────
if grep -rqE 'ContentState' $(swift_files) 2>/dev/null; then
  for c in idle loading loaded empty offline failed; do
    grep -rqE "case[[:space:]]+\.?$c" $(swift_files) 2>/dev/null || \
      finding error content-state "$SRC" 0 \
        "ContentState is used but '.$c' is never handled" \
        "Render it — a missing case is the blank-screen bug (§2.5, Core.md)"
  done
else
  grep -rqE 'isLoading|var loading|@State.*[Ll]oading' $(swift_files) 2>/dev/null && \
    finding error content-state "$SRC" 0 \
      "ad-hoc loading flag instead of ContentState<T>" \
      "Expose ContentState<T> from Core and render via ContentStateView (§2.5)"
fi

# ── §2.6 injection by protocol ─────────────────────────────────────────────
hits '\.shared\b' | while IFS=: read -r f ln rest; do
  finding error singleton "$f" "$ln" \
    "reaches a .shared singleton" \
    "Inject it by protocol through the Assembly instead (§2.6)"
done
hits '\bresolve\(' | while IFS=: read -r f ln rest; do
  case "$f" in *"/DI/"*) continue ;; esac         # the Assembly is the sanctioned seam
  finding error di-leak "$f" "$ln" \
    "calls resolve() outside DI/" \
    "Only the Assembly, previews and tests may resolve — inject into the initialiser (§2.6)"
done

# ── §2.7 error handling ────────────────────────────────────────────────────
hits 'try\?' | while IFS=: read -r f ln rest; do
  finding error swallowed-error "$f" "$ln" \
    "try? discards the error" \
    "Map it to AppError with isRetryable set deliberately (§2.7)"
done
hits 'fatalError\(' | while IFS=: read -r f ln rest; do
  finding error fatal-error "$f" "$ln" \
    "fatalError in a shipping path" \
    "Return a typed AppError, or make the state unrepresentable (§2.7)"
done

# ── §2.8 unchecked Sendable needs its justification ────────────────────────
hits '@unchecked Sendable' | while IFS=: read -r f ln rest; do
  prev=$(sed -n "$((ln > 1 ? ln - 1 : 1))p" "$f" 2>/dev/null)
  case "$prev" in *//*) continue ;; esac
  finding error unchecked-sendable "$f" "$ln" \
    "@unchecked Sendable with no justifying comment above it" \
    "Say which lock or queue makes it safe, on the line above (§2.8)"
done

# ── §2.10 no build-flag branching in a feature ─────────────────────────────
hits '#if[[:space:]]+(DEBUG|RELEASE|BETA|TEST)' | while IFS=: read -r f ln rest; do
  finding error build-flag "$f" "$ln" \
    "build-flag branch inside a feature" \
    "Read configuration once at the composition root, inject as AppEnvironment (§2.10)"
done

# ── §6 concurrency placement ───────────────────────────────────────────────
for f in $(swift_files); do
  case "$f" in
    */ViewModels/*)
      grep -qE '@MainActor' "$f" || finding error mainactor "$f" 1 \
        "view model is not @MainActor" \
        "Mark the type @MainActor, not each method (§6)" ;;
    */Services/*)
      grep -qE '@MainActor' "$f" && finding error mainactor-service "$f" \
        "$(grep -nE '@MainActor' "$f" | head -1 | cut -d: -f1)" \
        "service is @MainActor" \
        "Never @MainActor a service — make it an actor or a Sendable struct (§6)" ;;
  esac
done

# ── Protocol/mock pairs ────────────────────────────────────────────────────
grep -hoE '^[[:space:]]*(public[[:space:]]+)?protocol[[:space:]]+[A-Z][A-Za-z0-9_]*' $(swift_files) 2>/dev/null \
  | sed 's/.*protocol[[:space:]]*//' | sort -u | while read -r p; do
  [ -n "$p" ] || continue
  grep -rqE "(Mock|Stub|Spy|NoOp)$p|$p(Mock|Stub|Spy|NoOp)|struct[[:space:]]+Mock.*:[[:space:]]*$p" \
    $(swift_files) 2>/dev/null || \
    finding warn missing-mock "$SRC" 0 \
      "protocol $p has no mock in the package" \
      "Ship a Mock$p beside it — tests and previews both need it (new-feature §5)"
done

# ── Heuristics, flagged as such ────────────────────────────────────────────
hits 'Text\("[^"]{2,}"|Label\("[^"]{2,}"|\.navigationTitle\("' | while IFS=: read -r f ln rest; do
  finding warn raw-string-heuristic "$f" "$ln" \
    "literal string in a view [heuristic]" \
    "Use a localized key — <feature>_<screen>_<element>_<role> (§2.3)"
done
hits '[a-zA-Z0-9_\)\]]![^=]' | while IFS=: read -r f ln rest; do
  finding warn force-unwrap-heuristic "$f" "$ln" \
    "possible force-unwrap [heuristic]" \
    "Bind it, or make the optional impossible (§2.7)"
done

# ── Output ─────────────────────────────────────────────────────────────────
E=$(count_match '^error' "$TMP")
W=$(count_match '^warn'  "$TMP")

if [ "$TSV" -eq 1 ]; then
  printf '# severity\trule\tfile\tline\tfinding\tfix\n'
  sort -t'	' -k1,1 -k2,2 "$TMP"
  [ "$E" -gt 0 ] && exit "$EX_ERR"
  [ "$STRICT" -eq 1 ] && [ "$W" -gt 0 ] && exit "$EX_ERR"
  exit "$EX_OK"
fi

hdr "audit — $NAME"
info "package  ${PKG#$ROOT/}"
info "sources  $(swift_files | wc -l | tr -d ' ') swift file(s)"
info "findings $E error(s) · $W warning(s)"

# Errors first: a §2 rule break is not the same kind of thing as a missing mock,
# and interleaving them buries the ones that must be fixed.
for sev in error warn; do
  n=$(count_match "^$sev" "$TMP")
  [ "$n" -gt 0 ] || continue
  hdr "$(printf '%s' "$sev" | tr '[:lower:]' '[:upper:]') · $n"
  awk -F'\t' -v s="$sev" -v d="$DIM" -v o="$OFF" '$1==s {
    printf "  %-22s %s\n", $2, $5
    printf "  %-22s %s%s%s\n", "", d, ($4 == 0 ? $3 : $3 ":" $4), o
    printf "  %-22s → %s\n\n", "", $6
  }' "$TMP"
done

if [ "$((E + W))" -eq 0 ]; then
  ok "no findings — the feature satisfies every check this script can make statically"
  dim "what it cannot check: behaviour, accessibility, and anything needing a build — DONE.md"
  exit "$EX_OK"
fi

hdr "recommended order"
# Ranked by what unblocks the most: structure before rules, because a missing
# Assembly or test target is why several rule findings exist at all.
awk -F'\t' '
  $1 == "error" && ($2 ~ /structure|tests|di-assembly/) { a[++i] = "1. " $2 " — " $6 }
  $1 == "error" && ($2 !~ /structure|tests|di-assembly/) { b[++j] = "2. " $2 " — " $6 }
  $1 == "warn"                                           { c[++k] = "3. " $2 " — " $6 }
  END {
    for (x = 1; x <= i; x++) if (!seen[a[x]]++) print "  " a[x]
    for (x = 1; x <= j; x++) if (!seen[b[x]]++) print "  " b[x]
    for (x = 1; x <= k; x++) if (!seen[c[x]]++) print "  " c[x]
  }
' "$TMP" | head -12

printf '\n'
dim "procedure for changing an existing feature: docs/patterns/change.md"
FIRST=$(awk -F'\t' '$1=="error" && $4 > 0 {print $3 "\t" $4; exit}' "$TMP")
if [ -n "$FIRST" ]; then
  dim "$(xed_hint "$PKG/$(printf '%s' "$FIRST" | cut -f1)" "$(printf '%s' "$FIRST" | cut -f2)")"
fi
dim "heuristic rows over-report — read them before acting"

[ "$E" -gt 0 ] && exit "$EX_ERR"
[ "$STRICT" -eq 1 ] && [ "$W" -gt 0 ] && exit "$EX_ERR"
exit "$EX_OK"
