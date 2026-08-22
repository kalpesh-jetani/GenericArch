#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Report what a sync would involve: the installed version and ref, any second install root, per-file drift against a base when one is given, and which docs/patterns/ the code now justifies promoting to skills. Recommends; applies nothing.
#@usage     ga-sync-scan.sh [target-dir] [--base DIR] [--patterns] [--base-only] [--tsv]
#@in        target:dir(default .) --base:dir(a GenericArch checkout; without it the drift half is skipped and said so) --patterns:flag(pattern signals only) --base-only:flag(drift only) --tsv:flag(machine-readable)
#@out       stdout:install facts, then TAKE/HOLD/REFUSE rows per drifted file, then PROMOTE/NOT-YET rows per pattern
#@exit      0=scan completed 1=not a GenericArch install, or two install roots found 2=usage
#@effects   read-only; never opens the network — a base must already be on disk
#@when      is my install stale|what would a sync change|should I promote this pattern|which skill can fire now|two install roots|before sync-with-genericarch|am I behind upstream
#
# The deterministic half of /sync-with-genericarch. Three of its four jobs need no judgement at all:
# reading the installed version, spotting a second install root, and deciding whether a pattern's
# code exists. The fourth — which drifted files to take — needs a per-file recommendation, which is
# what this prints; the choosing stays with the operator, and adopt-review.sh --take stays the only
# thing that writes.
#
# OFFLINE BY CONSTRUCTION. It never fetches. The drift half needs a base checkout on disk, and if
# there is not one it says so and does the rest, rather than reaching for the network or guessing.
# That way the pattern and install-fact halves work on a plane.
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/ga-lifecycle.sh
. "$HERE/ga-lifecycle.sh"

TARGET="."; BASE=""; ONLY=""; TSV=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base)      BASE="${2:-}"; shift 2 || ga_die "--base needs a directory" "$GA_EX_USAGE" ;;
    --patterns)  ONLY=patterns; shift ;;
    --base-only) ONLY=base; shift ;;
    --tsv)       TSV=1; shift ;;
    -h|--help)   sed -n '2,12p' "$0"; exit "$GA_EX_OK" ;;
    -*)          ga_die "unknown option: $1" "$GA_EX_USAGE" ;;
    *)           TARGET="$1"; shift ;;
  esac
done
[ -d "$TARGET" ] || ga_die "no such directory: $TARGET" "$GA_EX_USAGE"
TARGET="$(cd "$TARGET" && pwd)"
if [ -n "$BASE" ]; then
  [ -d "$BASE" ] || ga_die "no such base directory: $BASE" "$GA_EX_USAGE"
  BASE="$(cd "$BASE" && pwd)"
  [ "$BASE" = "$TARGET" ] && ga_die "--base is the target itself; nothing could ever differ" "$GA_EX_USAGE"
fi
cd "$TARGET" || exit "$GA_EX_ERR"
[ -d "$GA_STATE_DIR" ] || ga_die "not a GenericArch install: no $GA_STATE_DIR/ in $TARGET" "$GA_EX_ERR"

want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }
say()  { [ "$TSV" -eq 1 ] || printf '%s\n' "$1"; }
hdr()  { [ "$TSV" -eq 1 ] || ga_hdr "$1"; }
verdict() {  # verdict <TAKE|HOLD|REFUSE|PROMOTE|NOT-YET> <path> <evidence> <reason>
  case "$1" in
    TAKE|PROMOTE) c="$GA_GRN" ;;
    HOLD|NOT-YET) c="$GA_YEL" ;;
    *)            c="$GA_DIM" ;;
  esac
  if [ "$TSV" -eq 1 ]; then printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
  else printf '  %s%-8s%s %-42s %s%s%s\n            %s%s%s\n' \
       "$c" "$1" "$GA_OFF" "$2" "$GA_DIM" "$3" "$GA_OFF" "$GA_DIM" "$4" "$GA_OFF"; fi
}
count() { c="$("$@" 2>/dev/null | tr -d ' ' | head -1)"; case "$c" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' "$c" ;; esac; }

MANIFEST=""; for m in $(ga_manifest_find "$TARGET"); do MANIFEST="$m"; done
VERSION="$([ -n "$MANIFEST" ] && ga_manifest_version "$MANIFEST" || echo unknown)"
SRC_REF="$([ -n "$MANIFEST" ] && awk -F'"' '/"source_ref"/{print $4; exit}' "$MANIFEST" 2>/dev/null || true)"

# ── 1. install facts, and the one thing that must stop a sync ──────────────
if [ "$TSV" -eq 0 ]; then
  ga_hdr "── ga-sync-scan ───────────────────────────────────────"
  printf '  target    %s\n' "$TARGET"
  printf '  version   %s\n' "$VERSION"
  printf '  source    %s\n' "${SRC_REF:-unrecorded}"
  printf '  fetch     %s\n' "$(awk -F'\t' '/^# FETCH-BASE:/{print $2; exit}' .claude/MAP.tsv 2>/dev/null || echo '(none)')"
  ga_dim "  Offline. Nothing here is fetched, and nothing is written."
  echo
fi

# A sync will faithfully update whichever root it is pointed at, so two roots means it can silently
# update the wrong one. install.sh refuses to CREATE the second; an older installer did not, so a
# repo can still be carrying one. This is a stop, not a warning.
GITROOT="$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$GITROOT" ]; then
  ROOTS="$(find "$GITROOT" -maxdepth 3 -name "$GA_STATE_DIR" -not -path '*/.git/*' -type d 2>/dev/null | sort)"
  n_roots="$(printf '%s\n' "$ROOTS" | grep -c . || true)"
  if [ "${n_roots:-0}" -gt 1 ]; then
    [ "$TSV" -eq 1 ] && printf 'STOP\ttwo-install-roots\t%s\t%s\n' "$n_roots" "consolidate before syncing"
    ga_warn "two GenericArch install roots in this checkout — a sync would update only one:"
    printf '%s\n' "$ROOTS" | sed 's|/'"$GA_STATE_DIR"'$||;s/^/      /'
    ga_dim "  Both copies are live, every command and skill resolves ambiguously, and only the one
  with a manifest can be uninstalled. Consolidating is its own decision — not part of a sync."
    exit "$GA_EX_ERR"
  fi
fi

# ── 2. drift against a base, with a recommendation per file ────────────────
if want base; then
  hdr "── drift against the base ─────────────────────────────"
  if [ -z "$BASE" ]; then
    say "  ${GA_YEL}no --base given, so drift was not assessed.${GA_OFF}"
    say "  This script is offline by design. To assess drift, put a base on disk first:"
    say "      git clone -q --depth 1 --branch <tag> <repo-url> /tmp/ga-base"
    say "      ./Scripts/ga-sync-scan.sh . --base /tmp/ga-base"
    say "  Pin a tag, never main — the fetched docs would drift out from under the install."
  else
    # Compare only what the base actually ships and this install actually has. A file absent here is
    # install.sh's business, not a sync's.
    ( cd "$BASE" && find .claude Scripts docs -type f \( -name '*.sh' -o -name '*.md' -o -name '*.tsv' -o -name '*.py' \) 2>/dev/null ) \
    | sed 's|^\./||' | LC_ALL=C sort | while IFS= read -r rel; do
      [ -f "$TARGET/$rel" ] || continue
      [ -f "$BASE/$rel" ]   || continue
      cmp -s "$TARGET/$rel" "$BASE/$rel" && continue
      kind="$(ga_staged_kind "$BASE/$rel")"
      rec=""; [ -n "$MANIFEST" ] && rec="$(ga_manifest_record_for "$MANIFEST" "$rel" 2>/dev/null || true)"
      tsha="$(ga_sha256 "$TARGET/$rel" 2>/dev/null || echo x)"
      act=""; [ -n "$rec" ] && act="$(ga_json_field "$rec" action 2>/dev/null || true)"
      rsha=""; [ -n "$rec" ] && rsha="$(ga_json_field "$rec" sha256 2>/dev/null || true)"
      # The manifest's ACTION is what establishes ownership, not the hash. install.sh records a
      # `skipped` file with the file's OWN hash — that is how it says "this is theirs, we never wrote
      # it" — so testing the hash alone marks every populated note and every locally-patched script
      # as "ours, unedited" and recommends overwriting it. That is the whole of someone's work.
      if ga_tombstoned "$TARGET" "$rel"; then
        verdict REFUSE "$rel" "tombstoned" "declined by this product — restoring it reverses a recorded decision"
      elif [ "$act" = "skipped" ]; then
        if [ "$kind" = "lib" ]; then
          verdict HOLD "$rel" "yours, and a shared library" "install never wrote this; but its callers source it, so a stale copy breaks them — diff, do not overwrite"
        else
          verdict HOLD "$rel" "yours — install never wrote it" "taking it REPLACES your file; the installer deliberately skipped this path"
        fi
      elif [ -z "$act" ]; then
        verdict HOLD "$rel" "no manifest record" "provenance unknown — diff before assuming it is ours"
      elif [ "$kind" = "lib" ]; then
        verdict TAKE "$rel" "shared library (#@kind lib)" "its callers source it; an old copy fails with 'command not found' while exiting 0"
      elif [ "$rsha" = "$tsha" ]; then
        verdict TAKE "$rel" "ours, unedited since install" "provably ours and untouched — nothing local to lose"
      else
        verdict HOLD "$rel" "ours, but edited since install" "taking it reverts your edit — diff it before deciding"
      fi
    done
    say ""
    say "  Nothing above was applied. ${GA_BLD}adopt-review.sh --take is the only thing that writes${GA_OFF},"
    say "  it is numbered separately, and Claude must never pass it:"
    say "      ./Scripts/adopt-review.sh . --base $BASE"
  fi
fi

# ── 3. which patterns the code now justifies ───────────────────────────────
# Evidence, never intent. A pattern with no signal is not a candidate, and "not yet" is a result
# worth printing — it stops the same question being reopened next month.
if want patterns; then
  hdr "── patterns the code now justifies ────────────────────"
  # A lean install carries NO pattern rows — adopt.sh drops them along with the module rows when the
  # architecture layer was not taken. Enumerating from MAP.tsv alone therefore finds nothing and
  # prints nothing, on exactly the installs where this question is live. So fall back to the known
  # set: the patterns exist upstream and are fetchable whether or not a row routes to them here.
  KNOWN="change dark-light-mode feature-complete release-bump rtl-support style-guide wrapper"
  PATS="$(awk -F'\t' '$2=="pattern"{print $1}' .claude/MAP.tsv 2>/dev/null | while IFS= read -r x; do basename "$x" .md; done)"
  if [ -z "$PATS" ]; then
    PATS="$KNOWN"
    say "  ${GA_DIM}no pattern rows in MAP.tsv (lean install) — using the known upstream set${GA_OFF}"
    say ""
  fi
  if true; then
    found=0
    for name in $PATS; do
      found=1
      if [ -d ".claude/skills/$name" ]; then
        verdict REFUSE "$name" "already a skill" "out of scope here — whether it can still FIRE is ga-cleanup-scan.sh --skills"
        continue
      fi
      case "$name" in
        wrapper)
          verdict REFUSE "$name" "reference for CLAUDE.md §7" "not promotable; the module docs cite it as a pattern" ;;
        dark-light-mode)
          d=$(count sh -c "grep -rl '\"dark\"' --include='Contents.json' . | wc -l")
          [ "$d" -gt 0 ] && verdict PROMOTE "$name" "$d dark asset variant(s)" "dark mode is real here — /learn $name" \
                         || verdict NOT-YET "$name" "no dark asset variants" "add a dark variant first, or it fires on nothing" ;;
        rtl-support)
          r=$(find . -name '*.lproj' 2>/dev/null | grep -cE '/(ar|he|fa|ur)\.lproj' | tr -d ' ' | head -1); r=${r:-0}
          [ "$r" -gt 0 ] && verdict PROMOTE "$name" "$r RTL locale(s)" "an RTL language ships — /learn $name" \
                         || verdict NOT-YET "$name" "no ar/he/fa/ur locale" "no RTL language ships here" ;;
        style-guide)
          t=$(count grep -c '^| `' .claude/notes/STYLE-GUIDE.md)
          [ "$t" -gt 0 ] && verdict PROMOTE "$name" "$t registered token(s)" "there are tokens to prefer over literals — /learn $name" \
                         || verdict NOT-YET "$name" "0 token rows in STYLE-GUIDE.md" "register tokens first" ;;
        feature-complete)
          # `grep -c '^| '` counts the note's own template rows, so an empty scaffold scored 6 and
          # got recommended in a repo with no Swift at all. A real entry names something — bold or
          # backticked in the first cell — and there has to be code for a feature to have shipped.
          f=$(count grep -cE '^\| (\*\*|`)' .claude/notes/FEATURES.md)
          sw=$(count sh -c "grep -rl . --include='*.swift' . | wc -l")
          if [ "$sw" -eq 0 ]; then
            verdict NOT-YET "$name" "no Swift files" "nothing has shipped yet, so there is no close-out to repeat"
          elif [ "$f" -gt 2 ]; then
            verdict PROMOTE "$name" "$f named feature row(s)" "features ship often enough to need a close-out — /learn $name"
          else
            verdict NOT-YET "$name" "$f named feature row(s)" "too few shipped features to have a repeatable close-out"
          fi ;;
        change)
          sw=$(count sh -c "grep -rl . --include='*.swift' . | wc -l")
          [ "$sw" -gt 0 ] && verdict PROMOTE "$name" "$sw Swift file(s)" "there is code to change — /learn $name" \
                          || verdict NOT-YET "$name" "no Swift files" "nothing to change yet" ;;
        release-bump)
          tg=$(count sh -c "git tag | wc -l")
          if [ -f Package.swift ] && [ "$tg" -gt 0 ]; then
            verdict PROMOTE "$name" "Package.swift + $tg tag(s)" "this repo publishes a versioned package — /learn $name"
          else
            verdict NOT-YET "$name" "no Package.swift at the root" "a release-workflow tool, not code generation — for an app it fires on nothing"
          fi ;;
        *) verdict NOT-YET "$name" "no signal defined" "add one here before recommending it either way" ;;
      esac
    done
    [ "$found" -eq 1 ] || say "  nothing to enumerate"
    say ""
    say "  ${GA_BLD}/learn <name>${GA_OFF} promotes one. It owns the earned-it test and its own approval"
    say "  gate; a signal here is the first of its three conditions, not all of them."
  fi
fi

exit "$GA_EX_OK"
