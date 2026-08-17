#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   One-call lookup across the .claude/notes/ inventories.
#@usage     find.sh <term> [more terms...]
#@in        term:str
#@out       stdout:matching note rows; miss prints the MAP.tsv route and a code-search fallback
#@exit      0=hits 1=no row found 2=usage
#@effects   read-only
#@when      where is this screen|find a route|which endpoint|locate an asset|find a colour token|which target|look it up
# One-call lookup across the .claude/notes/ index.
#   ./Scripts/find.sh <term> [more terms…]
#
# Prints matching rows and nothing else. The notes are a grep index, never a
# document — this script exists so a lookup costs one tool call instead of
# three, and so nothing has to open a note to answer "where is X?".
set -u
[ $# -ge 1 ] || { echo "usage: ./Scripts/find.sh <term>"; exit 2; }
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
term="$*"

hits=0
for f in .claude/notes/*.md; do
  [ -f "$f" ] || continue
  # rows only — never header prose, never the Gaps table
  out=$(grep -h "^| .*$term" "$f" 2>/dev/null | grep -v '^| *---')
  [ -n "$out" ] || continue
  root=$(grep -m1 '^- \*\*Root:\*\*' "$f" | sed 's/.*`\(.*\)`.*/\1/')
  printf '\n── %s%s\n' "$(basename "$f" .md)" "${root:+  (root: $root)}"
  printf '%s\n' "$out"
  hits=$((hits + $(printf '%s\n' "$out" | grep -c .)))
done

if [ "$hits" -gt 0 ]; then
  printf '\n%d row(s). No note was opened.\n' "$hits"
  exit 0
fi

# Miss. Point at the doc that owns the topic before falling back to a code grep.
printf 'No row in .claude/notes/ for "%s".\n\n' "$term"
map=$(grep -i "$term" .claude/MAP.tsv 2>/dev/null | awk -F'\t' '{printf "  %-42s %s\n", $1, $4}')
if [ -n "$map" ]; then
  printf 'The map routes this topic to:\n%s\n\n' "$map"
fi
cat <<'EOF'
Fall back to a code search, then RECORD THE ROW in the same change — that is what
keeps the next lookup cheap (CLAUDE.md §5, docs/PATTERN-SEARCH.md):

  grep -rn "<term>" --include="*.swift" . | grep -v Pods
EOF
exit 1
