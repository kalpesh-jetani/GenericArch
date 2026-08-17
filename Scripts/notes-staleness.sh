#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Report which .claude/notes/ inventories are older than the code they describe.
#@usage     notes-staleness.sh
#@in        none
#@out       stdout:per-note staleness
#@exit      0=fresh 1=stale notes found
#@effects   read-only
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
ROOT="${1:-.}"
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

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
