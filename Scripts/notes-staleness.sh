#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Report which .claude/notes/ inventories are older than the code they describe.
#@usage     notes-staleness.sh [source-root] | notes-staleness.sh --stamp [source-root]
#@in        source-root:dir(default .) --stamp:flag(write each note's content hash into it)
#@out       stdout:per-note staleness, verified by content hash where the note carries one
#@exit      0=fresh 1=stale notes found
#@effects   read-only, except --stamp which rewrites the header line of each note
#@when      are the notes stale|do the notes lie|which inventory is out of date|notes current
# Which notes are stale, and why. Read-only.
#   ./Scripts/notes-staleness.sh [source-root]
#
# Compares each note's `Last synced:` date against what has actually changed since,
# so /sync-app-notes can rescan the two notes that moved instead of all nine.
#
# Uses GIT timestamps, not filesystem mtime: a clone or a branch switch rewrites every
# mtime to checkout time, which would report the whole tree as stale on a fresh machine.
# Uncommitted work is picked up separately from `git status`.
set -u
# The install root is not always the git root: an Xcode project often sits in a subdirectory of
# its checkout, and `.claude/notes/` then lives there rather than at the top. Resolving to the git
# root made every lookup read an empty or absent notes directory and answer "No row" for terms the
# populated notes documented. So walk up from the caller instead, and only fall back to the git
# root when no ancestor holds the notes.
_resolve_notes_root() {
  d="$PWD"
  while [ "$d" != "/" ]; do
    [ -d "$d/.claude/notes" ] && { printf '%s\n' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  git rev-parse --show-toplevel 2>/dev/null || printf '.\n'
}
STAMP=0
[ "${1:-}" = "--stamp" ] && { STAMP=1; shift; }
ROOT="${1:-.}"
cd "$(_resolve_notes_root)"

# path pattern -> the note that indexes it
note_for() {
  case "$1" in
    *.colorset/*)                                 echo ASSETS-COLORS ;;
    *.imageset/*)                                 echo ASSETS-IMAGES ;;
    *.ttf|*.otf)                                  echo FONTS ;;
    *.xcconfig|*.xcscheme)                        echo SCHEMES ;;
    *project.pbxproj|*.entitlements|*Podfile|*Package.swift) echo PROJECT ;;
    *Info.plist)                                  echo "PROJECT FONTS SCHEMES" ;;
    *Route*.swift|*Navigation*.swift|*Deeplink*.swift|*.storyboard) echo NAVIGATION ;;
    *Routing.swift|*APIRouter.swift|*API*.swift)  echo API-MAP ;;
    *Fonts.swift|*Tokens*.swift|*DesignSystem/*)  echo STYLE-GUIDE ;;
    *ViewController.swift|*ViewModel.swift|*View.swift|*Screen.swift) echo FEATURES ;;
    *) echo "" ;;
  esac
}

# ── Content hash per note ──────────────────────────────────────────────────
# A date answers "might this be stale?"; a hash answers "is it?". Dates are wrong exactly when it
# matters — a rebase, a clone, or a note re-verified by hand all move the date without moving the
# content, and re-verifying nine notes to find out is the most expensive routine operation here.
# With a stamped hash, "still valid" is one comparison and Claude can trust the note as-is.
GA_EMPTY_HASH="e3b0c44298fc1c14"   # sha256 of nothing: no source file maps to this note

note_hash() {   # note_hash <NOTE-NAME>
  _want="$1"
  {
    git ls-files -s -- "$ROOT" 2>/dev/null | while read -r _mode _blob _stage _path; do
      for t in $(note_for "$_path"); do
        [ "$t" = "$_want" ] && printf '%s\t%s\n' "$_path" "$_blob"
      done
    done
    # Uncommitted work counts: a note stamped against a dirty tree must not read as verified once
    # the edit lands.
    git status --porcelain=v1 -- "$ROOT" 2>/dev/null | awk '{print $NF}' | while read -r _path; do
      [ -f "$_path" ] || continue
      for t in $(note_for "$_path"); do
        [ "$t" = "$_want" ] && printf '%s\tdirty:%s\n' "$_path" "$(shasum -a 256 "$_path" | awk '{print $1}')"
      done
    done
  } | LC_ALL=C sort -u | shasum -a 256 | awk '{print substr($1,1,16)}'
}

stamped_hash() {   # stamped_hash <note-file>
  grep -m1 -- '- \*\*Tree hash:\*\*' "$1" 2>/dev/null | sed 's/.*Tree hash:\*\* *`*//; s/`.*//' | tr -d '\r '
}

# ── --stamp ────────────────────────────────────────────────────────────────
if [ "$STAMP" -eq 1 ]; then
  n=0
  for f in .claude/notes/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .md)
    [ "$name" = "README" ] && continue
    h="$(note_hash "$name")"
    if [ "$h" = "$GA_EMPTY_HASH" ]; then
      printf '  %-16s no source files map to this note — not stamped\n' "$name"
      continue
    fi
    tmp="$f.tmp"
    if grep -q -- '- \*\*Tree hash:\*\*' "$f"; then
      sed "s|^- \*\*Tree hash:\*\*.*|- **Tree hash:** \`$h\`|" "$f" > "$tmp"
    elif grep -q -- '- \*\*Last synced:\*\*' "$f"; then
      awk -v h="$h" '{print} /- \*\*Last synced:\*\*/ && !done {print "- **Tree hash:** `" h "`"; done=1}' "$f" > "$tmp"
    else
      awk -v h="$h" 'NR==1 {print; print ""; print "- **Tree hash:** `" h "`"; next} {print}' "$f" > "$tmp"
    fi
    mv "$tmp" "$f"
    printf '  stamped %-16s %s\n' "$name" "$h"
    n=$((n + 1))
  done
  echo
  echo "$n note(s) stamped. A later run reports 'verified' while the hash still matches, so nothing"
  echo "re-reads a note to find out whether it is current."
  exit 0
fi

changed_since() {   # changed_since <iso-date>
  git log --since="$1" --name-only --pretty=format: -- "$ROOT" 2>/dev/null | grep -v '^$'
  git status --porcelain=v1 -- "$ROOT" 2>/dev/null | awk '{print $NF}'
}

printf '%-16s %-12s %-8s %s\n' NOTE "LAST SYNCED" STATUS "EVIDENCE"
printf '%-16s %-12s %-8s %s\n' ---- ----------- ------ --------
any_stale=0
for f in .claude/notes/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .md)
  [ "$name" = "README" ] && continue
  synced=$(grep -m1 -- '- \*\*Last synced:\*\*' "$f" | sed 's/.*Last synced:\*\* *//' | tr -d '\r')
  # A stamped hash outranks the date in both directions: matching means verified without reading
  # the note, differing means stale even if today's date sits in the header.
  stamp="$(stamped_hash "$f")"
  if [ -n "$stamp" ] && [ "$stamp" != "$GA_EMPTY_HASH" ]; then
    live="$(note_hash "$name")"
    if [ "$stamp" = "$live" ]; then
      printf '%-16s %-12s %-8s %s\n' "$name" "${synced:-—}" "verified" "hash $stamp — trust it as written"
      continue
    fi
    printf '%-16s %-12s %-8s %s\n' "$name" "${synced:-—}" "STALE" "hash moved: $stamp → $live"
    any_stale=1; continue
  fi
  case "$synced" in
    ""|never|Never)
      printf '%-16s %-12s %-8s %s\n' "$name" "${synced:-none}" "NEVER" "no baseline - full scan"
      any_stale=1; continue ;;
  esac
  n=$(changed_since "$synced" | sort -u | while read -r p; do
        for target in $(note_for "$p"); do [ "$target" = "$name" ] && echo "$p"; done
      done | sort -u)
  count=$(printf '%s\n' "$n" | grep -c . )
  if [ "$count" -eq 0 ]; then
    printf '%-16s %-12s %-8s %s\n' "$name" "$synced" "current" "-"
  else
    sample=$(printf '%s\n' "$n" | head -2 | xargs -I{} basename {} | tr '\n' ' ')
    printf '%-16s %-12s %-8s %s\n' "$name" "$synced" "STALE" "$count file(s): $sample"
    any_stale=1
  fi
done
echo
if [ "$any_stale" -eq 1 ]; then
  echo "Scan the STALE and NEVER rows only. A 'current' note has had no source change since its"
  echo "last sync, so rescanning it rewrites identical content."
else
  echo "Every note is current - nothing to rescan."
fi

# The #@exit header declares 0=fresh 1=stale. This was an unconditional `exit 0`, so any gate
# branching on $? reported fresh while notes were stale.
exit "$any_stale"
