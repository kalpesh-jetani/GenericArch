#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Gather everything /project-init can establish without asking — mode, toolchain mismatches, rule-conflict evidence, name collisions, routable-path resolvability — so the command reviews findings instead of running scans.
#@usage     ga-init-scan.sh [<target-dir>] [--write] [--check] [--quiet]
#@in        target:dir(default the repo above Scripts/) --write:flag(also place the evidence artifact) --check:flag(CI: exit 1 when the artifact is missing or older than the tree) --quiet:flag(write the artifact, print only the counts)
#@out       stdout:the report; with --write also .claude/notes/.evidence/INIT-SCAN.md and INIT-CONFLICTS.tsv
#@exit      0=scan complete, nothing blocking 1=a generator failed (handoff report written) 2=usage 3=BLOCKING toolchain mismatch — /project-init cannot proceed
#@effects   read-only by default; --write creates only .claude/notes/.evidence/ (gitignored, generated) and never touches an installed file
#@when      before project-init|what conflicts does this repo have|adoption evidence|preflight an install|does the map resolve|which module docs are orphans|which rules clash with this repo
#
# Why this exists: /project-init is 565 lines and about half of them are deterministic scans of
# files on disk — the mode, the toolchain mismatches, the eleven conflict rows in docs/ADOPTION.md
# §A2, the name collisions in §A4, the routable-path validator in S0c, the orphan module docs in
# S2c. Every one of those costs a session to produce output a shell script can hand over.
#
# So this gathers exactly that half, offline, and hands the command a bounded artifact to review.
# The other half — which rule wins, what to migrate, what goes in CLAUDE.md — is asked, because
# CLAUDE.md §0 forbids defaulting it and docs/STRUCTURE.md gates every CLAUDE.md write on its own
# approval. Same split as Scripts/sync-notes.sh, for the same reason.
#
# What it deliberately does NOT do:
#   - record the project-init step. That would mark the asking done when no asking happened, and
#     unblock /gaps against rules nobody accepted (docs/SEQUENCE.md).
#   - classify a conflict. Counts and paths are facts; "hard" versus "soft" is a judgement that
#     belongs to ADOPTION.md §A2 and the user.
#   - write CLAUDE.md, DECISIONS.md, settings.json, or remove anything. It proposes; the command
#     asks; the user decides.
#
# Every count carries its method's blind spot in the same row. docs/SCAN-TRAPS.md is the record of
# why: a grep count presented as a fact was wrong three times running.
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/ga-lifecycle.sh
. "$HERE/ga-lifecycle.sh"
SRC="$(cd "$HERE/.." && pwd)"

TARGET=""; WRITE=0; CHECK=0; QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --write)   WRITE=1; shift ;;
    --check)   CHECK=1; shift ;;
    --quiet)   QUIET=1; shift ;;
    -h|--help) sed -n '6,10p' "$0"; exit "$GA_EX_USAGE" ;;
    -*)        ga_die "unknown flag: $1" "$GA_EX_USAGE" ;;
    *)         [ -z "$TARGET" ] || ga_die "one target only" "$GA_EX_USAGE"; TARGET="$1"; shift ;;
  esac
done

# Same order as install.sh: the platform gate before anything is read, so a Linux run says why
# instead of failing later on a missing xcode-select.
ga_require_macos

TARGET="${TARGET:-$SRC}"
[ -d "$TARGET" ] || ga_die "no such directory: $TARGET" "$GA_EX_USAGE"
TARGET="$(cd "$TARGET" && pwd)"

EVID="$TARGET/.claude/notes/.evidence"
ART="$EVID/INIT-SCAN.md"
TSV="$EVID/INIT-CONFLICTS.tsv"

# ── --check: is the artifact still true? ───────────────────────────────────
# A stale evidence file is worse than none — it reads as current and the command trusts it. So CI
# gets a gate, and the test is the cheapest one that cannot lie: anything in the tree newer than
# the artifact means the scan predates the code it describes.
if [ "$CHECK" -eq 1 ]; then
  if [ ! -f "$ART" ]; then
    ga_warn "no evidence artifact: ${ART#"$TARGET"/}
  Run: ./Scripts/ga-init-scan.sh --write"
    exit "$GA_EX_ERR"
  fi
  NEWER="$(find "$TARGET" \
    \( -name .git -o -name .build -o -name .evidence -o -name Pods -o -name DerivedData \) -prune -o \
    -type f -newer "$ART" -print 2>/dev/null | head -3)"
  if [ -n "$NEWER" ]; then
    ga_warn "the evidence artifact is older than the tree it describes:"
    printf '%s\n' "$NEWER" | sed "s|^$TARGET/|    |"
    exit "$GA_EX_ERR"
  fi
  ga_ok "${ART#"$TARGET"/} is current"
  exit "$GA_EX_OK"
fi

# ── Shared scanning primitives ────────────────────────────────────────────
# One exclusion list for every grep and find below. Vendored trees hold other people's code, and
# counting it as this repo's evidence is how a conflict row reports a migration nobody has to do.
PRUNE='-name .git -o -name .build -o -name .swiftpm -o -name Pods -o -name Carthage
       -o -name DerivedData -o -name node_modules -o -name safetodelete -o -name .evidence'
GX="--exclude-dir=.git --exclude-dir=.build --exclude-dir=.swiftpm --exclude-dir=Pods
    --exclude-dir=Carthage --exclude-dir=DerivedData --exclude-dir=node_modules
    --exclude-dir=safetodelete --exclude-dir=.evidence"

FAILED=0
ROUTE_ISSUES=0
handoff() {  # handoff <cause> — a generator gave up; diagnose it, never emit a half-built table
  FAILED=1
  if [ -x "$SRC/Scripts/ga-handoff.sh" ]; then
    "$SRC/Scripts/ga-handoff.sh" "Scripts/ga-init-scan.sh" 1 --cause "$1" --file "$TARGET" >/dev/null 2>&1 || true
  fi
  ga_warn "$1"
}

S_SITES=0; S_FILES=0; S_EX=""
scan() {  # scan <pattern> [include-glob] → S_SITES (occurrences) S_FILES S_EX (up to 3 paths)
  _pat="$1"; _inc="${2:-*.swift}"
  S_SITES=0; S_FILES=0; S_EX=""
  _t="$(mktemp "${TMPDIR:-/tmp}/ga-scan.XXXXXX")" || { handoff "cannot create a temp file in ${TMPDIR:-/tmp}"; return 1; }
  # -c prints path:count for every file including the zeros, so the filter is ours. -I skips
  # binaries, which a .xcodeproj directory is full of.
  # shellcheck disable=SC2086  # deliberate word splitting of the exclusion list
  grep -RIc $GX --include="$_inc" -e "$_pat" "$TARGET" 2>/dev/null \
    | awk -F: '$NF+0>0' > "$_t"
  S_SITES="$(awk -F: '{n+=$NF} END{print n+0}' "$_t")"
  S_FILES="$(wc -l < "$_t" | tr -d ' ')"
  S_EX="$(sed 's/:[0-9]*$//' "$_t" | head -3 | sed "s|^$TARGET/||" | paste -sd';' -)"
  rm -f "$_t"
  [ "$S_SITES" -gt 0 ]
}

F_COUNT=0; F_EX=""
files_named() {  # files_named <name-pattern>... → F_COUNT F_EX
  F_COUNT=0; F_EX=""
  _t="$(mktemp "${TMPDIR:-/tmp}/ga-find.XXXXXX")" || { handoff "cannot create a temp file in ${TMPDIR:-/tmp}"; return 1; }
  for _n in "$@"; do
    # shellcheck disable=SC2086  # PRUNE is a deliberate expression fragment
    find "$TARGET" \( $PRUNE \) -prune -o -name "$_n" -print 2>/dev/null >> "$_t"
  done
  F_COUNT="$(wc -l < "$_t" | tr -d ' ')"
  F_EX="$(head -3 "$_t" | sed "s|^$TARGET/||" | paste -sd';' -)"
  rm -f "$_t"
  [ "$F_COUNT" -gt 0 ]
}

# ── The report is built once and sent to two sinks ─────────────────────────
# stdout for a person or an agent reading it now, the artifact for /project-init reading it later.
# One generator, so the two can never disagree about what was found.
REPORT="$(mktemp "${TMPDIR:-/tmp}/ga-init-report.XXXXXX")"
CONFLICTS="$(mktemp "${TMPDIR:-/tmp}/ga-init-conflicts.XXXXXX")"
trap 'rm -f "$REPORT" "$CONFLICTS"' EXIT
say() { printf '%s\n' "$*" >> "$REPORT"; }

N_CONFLICTS=0
conflict() {  # conflict <signal> <count-text> <examples> <rule> <blind-spot>
  N_CONFLICTS=$((N_CONFLICTS + 1))
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$CONFLICTS"
  say "| $1 | $2 | \`${3:-—}\` | $4 | $5 |"
}

# ── §mode ─────────────────────────────────────────────────────────────────
ga_check_compatible "$TARGET"
case "$GA_COMPAT_KIND" in
  fresh) MODE="new" ;;
  *)     MODE="existing" ;;
esac
COMMITS="$(git -C "$TARGET" rev-list --count HEAD 2>/dev/null || echo 0)"
# The newest manifest, if this repo has an install. §collisions needs it to tell a file GenericArch
# wrote from one it preserved, and this scan runs after the install, so name alone cannot.
MANIFEST=""
for _m in $(ga_manifest_find "$TARGET" 2>/dev/null); do MANIFEST="$_m"; done

say "# /project-init evidence — $(basename "$TARGET")"
say ""
say "Generated by \`Scripts/ga-init-scan.sh\` on $(ga_now_iso). Read this instead of re-running the"
say "scans; every row is a fact from disk, and no row is a verdict. The asking is still \`/project-init\`'s."
say ""
say "## mode"
say ""
say "\`$MODE\` — derived from the same gate \`install.sh\` uses (\`ga_check_compatible\`), so the two cannot disagree."
say ""
say "| Fact | Value |"
say "|---|---|"
say "| Apple markers found |${GA_COMPAT_FOUND:- none} |"
say "| Non-Swift build files |${GA_COMPAT_FOREIGN:- none} |"
say "| Commits | $COMMITS |"
say "| \`Packages/\` | $([ -d "$TARGET/Packages" ] && echo present || echo absent) |"
say "| \`.genericarch/\` manifest | $([ -n "$MANIFEST" ] && printf '%s' "${MANIFEST#"$TARGET"/}" || echo absent) |"
say ""

# Their CLAUDE.md files, with size — A1 reads these in full, and the line count is what says
# whether the §5 four-way split is worth offering.
say "**CLAUDE.md files** (A1 reads each in full — this is only where they are and how big):"
say ""
# shellcheck disable=SC2086
CMDS="$(find "$TARGET" \( $PRUNE \) -prune -o -name CLAUDE.md -print 2>/dev/null | LC_ALL=C sort)"
if [ -z "$CMDS" ]; then
  say "- none — nothing to reconcile, Path B applies"
else
  printf '%s\n' "$CMDS" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    say "- \`${f#"$TARGET"/}\` — $(wc -l < "$f" | tr -d ' ') lines"
  done
fi
say ""

# Their skills and commands, name plus description. A4 needs the names; the descriptions are how
# a *description* overlap without a name clash gets caught, which is the failure that leaves two
# skills triggering on the same phrases.
say "**Their skills and commands:**"
say ""
FOUND_ANY=0
for d in "$TARGET/.claude/skills" "$TARGET/.claude/commands"; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    [ -e "$f" ] || continue
    FOUND_ANY=1
    _md="$f"; [ -d "$f" ] && _md="$f/SKILL.md"
    _desc=""
    [ -f "$_md" ] && _desc="$(awk -F': *' '/^description:/{sub(/^description: */,""); print; exit}' "$_md" | cut -c1-90)"
    say "- \`${f#"$TARGET"/}\` — ${_desc:-no description}"
  done
done
[ "$FOUND_ANY" -eq 0 ] && say "- none"
say ""

# ── §offered ──────────────────────────────────────────────────────────────
# B1: what this repo already gives them. Confirmed against the filesystem, because the table in
# the command is a description and the filesystem is the fact.
say "## offered"
say ""
_from="$TARGET"; _label="installed here"
[ -d "$TARGET/.claude/commands" ] || { _from="$SRC"; _label="available from the base — not installed yet"; }
say "Source: \`${_from}\` ($_label)."
say ""
for kind in skills commands; do
  _list=""
  [ -d "$_from/.claude/$kind" ] && _list="$(ls "$_from/.claude/$kind" 2>/dev/null | sed 's/\.md$//' | paste -sd' ' -)"
  say "- **$kind:** ${_list:-none}"
done
if [ -f "$_from/.claude/MAP.tsv" ]; then
  _pat="$(awk -F'\t' '$2=="pattern"{n++} END{print n+0}' "$_from/.claude/MAP.tsv")"
  say "- **patterns waiting in \`docs/patterns/\`:** $_pat — each becomes a skill via \`/learn <name>\` once the code it describes exists"
fi
say ""

# ── §toolchain ────────────────────────────────────────────────────────────
# --root, never a cd: detect-toolchain.sh cd's to its own repo root unconditionally, so changing
# directory before the call reports GenericArch's stack instead of the target's.
say "## toolchain"
say ""
BLOCKING=0
MISMATCHES=""
if [ -x "$SRC/Scripts/detect-toolchain.sh" ]; then
  MISMATCHES="$(NO_COLOR=1 "$SRC/Scripts/detect-toolchain.sh" --mismatches --root "$TARGET" 2>/dev/null)"
  if [ -z "$MISMATCHES" ]; then
    say "No mismatches — the project's settings and this machine agree."
  else
    say "\`SEVERITY|id|what|current|available|remediation\` — BLOCKING first."
    say ""
    say '```'
    printf '%s\n' "$MISMATCHES" | grep '^BLOCKING' >> "$REPORT"
    printf '%s\n' "$MISMATCHES" | grep -v '^BLOCKING' >> "$REPORT"
    say '```'
    printf '%s\n' "$MISMATCHES" | grep -q '^BLOCKING' && BLOCKING=1
  fi
else
  handoff "Scripts/detect-toolchain.sh is not executable at $SRC — the toolchain section is empty"
  say "Not resolved — \`detect-toolchain.sh\` was unavailable."
fi
say ""

# ── §conflicts ────────────────────────────────────────────────────────────
# One row per docs/ADOPTION.md §A2 row that has evidence. A signal with no evidence is omitted
# rather than printed as a zero: a table of eleven "none" rows reads as a scan that found nothing
# when it is really a scan of a repo with nothing to find.
say "## conflicts"
say ""
say "Evidence for the \`docs/ADOPTION.md\` §A2 table. **No severity column** — classifying these is"
say "A2's job, and A3 still asks per row with its four options. Absent signals are omitted."
say ""
say "| Signal | Evidence | Where (first 3) | Conflicts with | What this count does NOT establish |"
say "|---|---|---|---|---|"

files_named Podfile Cartfile Podfile.lock \
  && conflict "CocoaPods / Carthage" "$F_COUNT manifest(s)" "$F_EX" "SPM only (§1)" \
       "whether the pods are still used or are a leftover lockfile"

files_named Project.swift Workspace.swift project.yml \
  && conflict "Tuist / XcodeGen" "$F_COUNT manifest(s)" "$F_EX" "SPM-generated (§1, REPO.md)" \
       "nothing — the manifest's presence is the conflict"

files_named '*.storyboard' '*.xib' \
  && conflict "Storyboards / xibs" "$F_COUNT file(s)" "$F_EX" "SwiftUI only (§1)" \
       "how many screens they hold; one storyboard can carry twenty"

scan '^import UIKit' \
  && conflict "UIKit imports" "$S_FILES file(s)" "$S_EX" "SwiftUI only (§1)" \
       "which are legitimate Representable wrappers, which §1 allows"

scan '^import Combine' \
  && conflict "Combine" "$S_FILES file(s)" "$S_EX" "async/await only (§1, §6)" \
       "whether these are @Published in view models or real pipelines"

scan '@escaping.*->' \
  && conflict "Completion handlers" "$S_SITES site(s) in $S_FILES file(s)" "$S_EX" "async/await only (§6)" \
       "which are callbacks a framework demands rather than choices, and which are already async wrappers"

scan 'UIAlertController\|\.alert(\|\.confirmationDialog(' \
  && conflict "Direct alerts / sheets" "$S_SITES call site(s)" "$S_EX" "one MessagePresenting (§2.4)" \
       "the migration cost per site; a bound \`.alert\` is not a one-line change"

scan 'Text("[A-Za-z]' \
  && conflict "Literal strings in Text" "$S_SITES site(s) in $S_FILES file(s)" "$S_EX" "localized keys (§2.3)" \
       "which literals are user-facing — SwiftUI's LocalizedStringKey overload makes some already keyed"

scan 'import Swinject\|import Factory\|import Resolver\|Resolver\.\|Container()' \
  && conflict "Third-party DI" "$S_FILES file(s)" "$S_EX" "own typed registry, DIKit (§2.6)" \
       "how pervasive it is; DI shows up at every construction site, not just the imports"

scan '\.shared\b' \
  && conflict "Singletons" "$S_SITES reference(s)" "$S_EX" "protocol injection (§2.6)" \
       "which are Apple's own (FileManager.default-style) and perfectly fine"

scan 'Interactor\|Presenter\|Router\|Coordinator' \
  && conflict "VIPER / Clean / Coordinator markers" "$S_FILES file(s)" "$S_EX" "MVVM + @Observable, layered (§0, §3)" \
       "the actual pattern — a name is a hint, and Router also means Navigation here"

scan '^import XCTest' \
  && conflict "XCTest" "$S_FILES file(s)" "$S_EX" "Swift Testing for new code (§9)" \
       "nothing — §9 already allows both to coexist, and XCTest stays for UI tests"

scan 'platforms:' 'Package.swift' \
  && conflict "Declared platform floors" "$S_FILES Package.swift" "$S_EX" "whatever Package.swift declares (§1.1)" \
       "whether they agree with each other or with the .xcconfig floors — compare against §toolchain"

files_named '*.xcodeproj' && [ "$F_COUNT" -gt 1 ] \
  && conflict "Multiple Xcode projects" "$F_COUNT" "$F_EX" "single repo + two extracted (§4)" \
       "whether they are one product or several sharing a checkout"

[ -f "$TARGET/.gitmodules" ] \
  && conflict "Git submodules" "$(grep -c '^\[submodule' "$TARGET/.gitmodules" 2>/dev/null || echo '?')" ".gitmodules" \
       "single repo + two extracted (§4)" "whether the submodules are vendor code or the product's own"

[ "$N_CONFLICTS" -eq 0 ] && say "| — | no signals found | — | — | an empty table on a repo with code means the greps missed, not that nothing conflicts |"
say ""

# ── §collisions ───────────────────────────────────────────────────────────
# A4: a skill or command whose name already exists would shadow or duplicate theirs. install.sh
# already refuses to overwrite, so this is not about safety — it is about the four options A4 has
# to offer for each one.
say "## collisions"
say ""
COLL=0
for kind in skills commands; do
  [ -d "$SRC/.claude/$kind" ] || continue
  for f in "$SRC/.claude/$kind"/*; do
    [ -e "$f" ] || continue
    _n="$(basename "$f")"
    [ -e "$TARGET/.claude/$kind/$_n" ] || continue
    [ "$TARGET" = "$SRC" ] && continue
    # install.sh runs this scan AFTER the files have landed, so "exists in both" is true of
    # everything it just wrote. The manifest is what tells the two apart: `created` is ours,
    # `skipped` is theirs — install.sh preserved it rather than overwriting. With no manifest
    # (a standalone pre-install run) nothing here is ours, so every match is a real collision.
    # A skill is a directory and the manifest records files, so the lookup path is its SKILL.md.
    _rel=".claude/$kind/$_n"
    [ -d "$SRC/.claude/$kind/$_n" ] && _rel="$_rel/SKILL.md"
    if [ -n "$MANIFEST" ]; then
      _rec="$(ga_manifest_record_for "$MANIFEST" "$_rel" 2>/dev/null || true)"
      [ -z "$_rec" ] || [ "$(ga_json_field "$_rec" action 2>/dev/null)" = "skipped" ] || continue
    fi
    COLL=$((COLL + 1))
    say "- \`.claude/$kind/$_n\` — theirs, and ours has the same name. A4: keep theirs · install ours as \`ga-${_n%.md}\` · merge · skip ours"
  done
done
if [ "$COLL" -eq 0 ]; then
  say "None — no name in \`.claude/skills\` or \`.claude/commands\` is claimed twice."
  [ -n "$MANIFEST" ] && say ""
  [ -n "$MANIFEST" ] && say "(Files GenericArch installed are excluded by the manifest, not by name — only a file the"
  [ -n "$MANIFEST" ] && say "install *preserved* counts as a collision.)"
fi
say ""

# ── §routes ───────────────────────────────────────────────────────────────
# S0c, moved out of the command verbatim. A map row that cannot resolve is worse than a missing
# row: it reads as "this exists here", and when the file is not there the content gets invented.
say "## routes"
say ""
MAP="$TARGET/.claude/MAP.tsv"
if [ ! -f "$MAP" ]; then
  say "No \`.claude/MAP.tsv\` — nothing is installed here yet. Every lookup path below is missing by"
  say "definition; re-check after \`install.sh --apply\`."
  say ""
  say '```'
  for f in .claude/MAP.tsv .claude/INDEX.md .claude/memory/INDEX.md .claude/skills .claude/commands .claude/notes; do
    [ -e "$TARGET/$f" ] && continue
    printf 'MISSING-LOCAL  %s\n' "$f" >> "$REPORT"
    ROUTE_ISSUES=$((ROUTE_ISSUES + 1))
  done
  say '```'
else
  FETCH_BASE="$(awk -F'\t' '/^# FETCH-BASE:/{print $2; exit}' "$MAP")"
  RT="$(mktemp "${TMPDIR:-/tmp}/ga-routes.XXXXXX")"
  # These cannot be fetched: Claude Code discovers skills and commands from the filesystem, and a
  # map you must fetch first cannot route you to itself.
  for f in .claude/MAP.tsv .claude/INDEX.md .claude/memory/INDEX.md \
           Scripts/check.sh Scripts/find.sh Scripts/scan-api-map.py \
           Scripts/notes-staleness.sh Scripts/scan-colors.py \
           Scripts/scan-unused-assets.py Scripts/scan-fonts.py; do
    [ -e "$TARGET/$f" ] || printf 'MISSING-LOCAL  %s\n' "$f" >> "$RT"
  done
  for d in .claude/skills .claude/commands .claude/notes; do
    [ -d "$TARGET/$d" ] || printf 'MISSING-LOCAL  %s\n' "$d" >> "$RT"
  done

  # Everything under docs/ may be absent when the map carries a fetch base — that is the
  # fetch-on-demand install, not a broken row.
  awk -F'\t' '!/^#/ && NF>1 {print $1}' "$MAP" | while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -e "$TARGET/$p" ] && continue
    # .genericarch/ is runtime state, created on demand — failures/, safetodelete/, the manifest.
    # An absent one means nothing has failed yet, not that a row cannot resolve, and telling the
    # operator to stamp a FETCH-BASE for it would send them after a doc that was never a doc.
    case "$p" in "$GA_STATE_DIR"/*) continue ;; esac
    if [ -n "$FETCH_BASE" ]; then printf 'FETCHABLE      %s\n' "$p"; else printf 'UNRESOLVABLE   %s\n' "$p"; fi
  done | sort | uniq -c | sort -rn >> "$RT"

  # A row that is not exactly 4 tab-separated columns is dropped by every awk/grep recipe that
  # reads this file — silently, with no error anywhere.
  awk -F'\t' 'NF!=4 && $0 !~ /^#/ && NF>0 {print "MALFORMED-ROW  line "NR": "NF" columns"}' "$MAP" >> "$RT"
  awk -F'\t' '$2=="note" {print $1}' "$MAP" | while IFS= read -r n; do
    [ -f "$TARGET/$n" ] || printf 'MISSING-NOTE   %s\n' "$n"
  done >> "$RT"

  # UNRESOLVABLE, MISSING-LOCAL, MALFORMED-ROW and MISSING-NOTE must all be zero. FETCHABLE is the
  # expected shape of a fetch-on-demand install, so it is reported and not counted as a problem.
  ROUTE_ISSUES="$(grep -c 'UNRESOLVABLE\|MISSING-LOCAL\|MALFORMED-ROW\|MISSING-NOTE' "$RT" 2>/dev/null | tr -d ' ')"
  if [ -s "$RT" ]; then
    say '```'
    cat "$RT" >> "$REPORT"
    say '```'
  else
    say "Every row in \`.claude/MAP.tsv\` resolves on disk, and every path Claude Code discovers from"
    say "the filesystem — skills, commands, notes, the map itself — is present."
  fi
  rm -f "$RT"
  say ""
  say "FETCH-BASE: ${FETCH_BASE:-<none — every missing row must resolve locally>}"
  say ""
  say "\`MISSING-LOCAL\` → the install was partial; re-run \`install.sh --apply\`. \`UNRESOLVABLE\` → stamp"
  say "a \`# FETCH-BASE:\` first line from \`genericarch.installation.md\`'s pinned commit. \`FETCHABLE\` →"
  say "correct and expected. **The unresolvable count must be zero before \`/project-init\` reports success.**"
fi
say ""

# ── §orphan-docs ──────────────────────────────────────────────────────────
# S2c: a doc for a package that does not exist reads as current and describes code that is not
# there. The removal is gated (§2.15) — this prints the exact command and runs none of it.
say "## orphan-docs"
say ""
ORPH=0
# The base checkout is the exception: it ships all twelve module docs as the blueprint, and its own
# Packages/ holds only the Core+DIKit floor. Proposing removals there would be proposing to delete
# the material every install copies.
if [ "$TARGET" = "$SRC" ]; then
  say "Skipped — this is the GenericArch base checkout, which ships the full \`docs/modules/\` set as"
  say "the blueprint. The derivation only means something in a target repo."
elif [ -d "$TARGET/docs/modules" ]; then
  for f in "$TARGET/docs/modules"/*.md; do
    [ -e "$f" ] || continue
    _pkg="$(basename "$f" .md)"
    [ -d "$TARGET/Packages/$_pkg" ] && continue
    # Features and Wrappers are directories of packages, not packages — their docs stay.
    case "$_pkg" in Features|Wrappers|README) continue ;; esac
    ORPH=$((ORPH + 1))
    say "- \`docs/modules/$_pkg.md\` — no \`Packages/$_pkg\`"
    say "  \`\`\`bash"
    say "  ./Scripts/ga-remove.sh docs/modules/$_pkg.md --reason \"no $_pkg package in this product\" --apply"
    say "  \`\`\`"
  done
fi
if [ "$TARGET" = "$SRC" ]; then
  :
elif [ ! -d "$TARGET/docs/modules" ]; then
  say "No \`docs/modules/\` here — nothing to be orphaned from."
elif [ "$ORPH" -eq 0 ]; then
  say "None — every installed module doc has a package."
else
  say ""
  say "Nothing above has been removed. \`ga-remove.sh\` writes the tombstone *and* the DECISIONS.md"
  say "*Do not re-propose* row together; \`rm\` writes neither, so the next install re-creates the file."
fi
say ""

# ── §levels ───────────────────────────────────────────────────────────────
# S0: a rule stated at two levels drifts, and the stale copy is the one nobody reads. Presence
# only — deciding which duplicate to drop needs the text of both, and that is the command's read.
say "## levels"
say ""
say "Where a rule could be stated here. S0 removes duplicates working inward; keeping the most specific copy."
say ""
say "| Level | Reach | Present |"
say "|---|---|---|"
ENT="/Library/Application Support/ClaudeCode/managed-settings.json"
say "| Enterprise | every repo, every user | $([ -f "$ENT" ] && echo 'yes — **read-only, never touch it**' || echo no) |"
_user="$(ls "$HOME/.claude/CLAUDE.md" 2>/dev/null | wc -l | tr -d ' ')"
_mem="$(ls "$HOME"/.claude/projects/*/memory/*.md 2>/dev/null | wc -l | tr -d ' ')"
say "| User | this user | CLAUDE.md: $([ "$_user" -gt 0 ] && echo yes || echo no) · project-scoped memories: $_mem |"
say "| Project | everyone who clones | $(printf '%s' "$CMDS" | grep -c . | tr -d ' ') CLAUDE.md file(s) |"
say "| Plugin | every repo that installs it | $([ -d "$TARGET/.claude-plugin" ] && echo yes || echo no) |"
say ""
say "A project-scoped memory directory adds no reach over the repo itself — a rule in both is pure duplication."
say ""

# ── Emit ──────────────────────────────────────────────────────────────────
if [ "$WRITE" -eq 1 ]; then
  mkdir -p "$EVID" || handoff "cannot create $EVID"
  if [ -d "$EVID" ]; then
    # Redirect rather than cp: mktemp makes the scratch file 0600, and an artifact the next
    # developer cannot read is one they will regenerate instead of trusting.
    cat "$REPORT" > "$ART"
    { printf 'signal\tevidence\texamples\tconflicts_with\tblind_spot\n'; cat "$CONFLICTS"; } > "$TSV"
    chmod 644 "$ART" "$TSV" 2>/dev/null || true
  fi
fi

[ "$QUIET" -eq 1 ] || cat "$REPORT"

ga_hdr "── init scan ──────────────────────────────────────────"
printf '  mode          %s%s%s\n' "$GA_BLD" "$MODE" "$GA_OFF"
printf '  conflicts     %s (evidence rows — severity is not ours to set)\n' "$N_CONFLICTS"
printf '  collisions    %s\n' "$COLL"
printf '  orphan docs   %s\n' "$ORPH"
printf '  route issues  %s (unresolvable, missing-local, malformed — must be 0)\n' "$ROUTE_ISSUES"
if [ "$WRITE" -eq 1 ] && [ -f "$ART" ]; then
  ga_ok "evidence: ${ART#"$TARGET"/}"
fi
[ "$FAILED" -eq 1 ] && ga_warn "a generator failed — see the report in .genericarch/failures/"

if [ "$BLOCKING" -eq 1 ]; then
  echo
  ga_warn "a BLOCKING toolchain mismatch stands — the report's \`## toolchain\` section names it.
  That build cannot succeed as configured, so /project-init stops here rather than adopting docs
  onto a repo that does not build. Hand it to /upgrade-stack, which asks twice before changing
  any project setting, then re-run this scan."
  exit "$GA_EX_COMPAT"
fi
[ "$FAILED" -eq 1 ] && exit "$GA_EX_ERR"
exit "$GA_EX_OK"
