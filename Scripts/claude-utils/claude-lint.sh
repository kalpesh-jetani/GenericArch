#!/usr/bin/env bash
# Cross-phase: enforce markdown formatting standards on a CLAUDE.md-style doc.
#
#   ./Scripts/claude-utils/claude-lint.sh <file>
#   ./Scripts/claude-utils/claude-lint.sh <file> --fix
#   ./Scripts/claude-utils/claude-lint.sh <file> --max-line 100 --quiet
#
# Checks            fixable by --fix
#   trailing whitespace                    yes
#   missing final newline                  yes
#   3+ consecutive blank lines             yes
#   hard tab outside a code fence          yes (→ two spaces)
#   heading with no blank line before it   no
#   heading level jump (h2 → h4)           no
#   setext heading (=== underline)         no
#   line over --max-line characters        no
#   unbalanced code fence                  no
#
# --fix only touches the four that cannot change meaning. Rewrapping a long line
# or re-levelling a heading is an editorial decision, and a linter that made them
# silently would be rewriting the document's intent, not its formatting.
#
# Tabs are flagged OUTSIDE fenced blocks only — a Makefile or TSV example inside
# a fence needs its tabs, and stripping them would break the sample.
#
# Exit 0 clean · 1 problems found (or fixed) · 2 usage.
. "$(dirname "$0")/_common.sh"

usage_text() { sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; }

FIX=0; QUIET=0; MAXLINE=100; FILE=''
while [ $# -gt 0 ]; do
  case "$1" in
    --fix)       FIX=1; shift ;;
    --quiet|-q)  QUIET=1; shift ;;
    --max-line)  [ $# -ge 2 ] || die "--max-line needs a number" "$EX_USAGE"
                 MAXLINE="$2"; shift 2 ;;
    -h|--help)   usage "$EX_OK" ;;
    -*)          die "unknown argument: $1" "$EX_USAGE" ;;
    *)           [ -z "$FILE" ] || die "one file at a time" "$EX_USAGE"
                 FILE="$1"; shift ;;
  esac
done

[ -n "$FILE" ] || usage
[ -r "$FILE" ] || die "cannot read $FILE" "$EX_USAGE"
case "$MAXLINE" in ''|*[!0-9]*) die "--max-line must be a number" "$EX_USAGE" ;; esac
[ "$FIX" -eq 1 ] && [ ! -w "$FILE" ] && die "--fix needs a writable file: $FILE" "$EX_USAGE"

TMP="${TMPDIR:-/tmp}/ga-lint.$$"
trap 'rm -f "$TMP" "$TMP.f"' EXIT INT TERM

# ── Report ─────────────────────────────────────────────────────────────────
awk -v maxline="$MAXLINE" '
  function flag(line, rule, detail) { printf "%d\t%s\t%s\n", line, rule, detail }

  /^[ \t]*(```|~~~)/ { fence = !fence; fences++; prev_blank = 0; next }

  {
    if ($0 ~ /[ \t]+$/)                  flag(FNR, "trailing-space", "line ends in whitespace")
    if (!fence && $0 ~ /\t/)             flag(FNR, "hard-tab", "tab outside a code fence")
    if (length($0) > maxline && !fence) {
      # A long line that is one unbreakable token (a URL, a path) cannot be
      # wrapped, so reporting it is noise.
      if ($0 ~ / /) flag(FNR, "long-line", length($0) " chars (max " maxline ")")
    }

    if ($0 ~ /^[ \t]*$/) { blanks++; prev_blank = 1 }
    else {
      if (blanks >= 3) flag(FNR - 1, "blank-run", blanks " consecutive blank lines")
      blanks = 0
    }

    if (!fence && $0 ~ /^#{1,6}[ \t]/) {
      match($0, /^#+/); lvl = RLENGTH
      if (FNR > 1 && !prev_blank) flag(FNR, "heading-no-gap", "no blank line before heading")
      if (prev_lvl && lvl > prev_lvl + 1) flag(FNR, "heading-jump", "h" prev_lvl " → h" lvl)
      prev_lvl = lvl
    }

    if (!fence && $0 ~ /^=+[ \t]*$/ && prev_text) flag(FNR, "setext-heading", "use # instead of === underline")

    prev_text = ($0 !~ /^[ \t]*$/)
    if ($0 !~ /^[ \t]*$/) prev_blank = 0
  }

  END {
    if (blanks >= 3) flag(FNR, "blank-run", blanks " trailing blank lines")
    if (fences % 2) flag(FNR, "unbalanced-fence", fences " fence markers (odd)")
  }
' "$FILE" > "$TMP"

# Final newline: awk cannot see its absence, so check the last byte directly.
if [ -s "$FILE" ] && [ "$(tail -c1 "$FILE" | wc -l | tr -d ' ')" -eq 0 ]; then
  printf '%s\tno-final-newline\tfile does not end in a newline\n' \
    "$(wc -l < "$FILE" | tr -d ' ')" >> "$TMP"
fi

N=$(wc -l < "$TMP" | tr -d ' ')

if [ "$QUIET" -eq 0 ]; then
  hdr "lint — $(basename "$FILE")"
fi

if [ "$N" -eq 0 ]; then
  [ "$QUIET" -eq 0 ] && ok "clean"
  exit "$EX_OK"
fi

if [ "$QUIET" -eq 0 ]; then
  sort -t'	' -k1,1n "$TMP" | \
    awk -F'\t' -v y="$YEL" -v o="$OFF" \
      '{printf "  %sline %-5s%s %-18s %s\n", y, $1, o, $2, $3}'
  printf '\n'
  # A per-rule tally makes "42 problems" actionable — one rule 40 times is a
  # different job from ten rules four times each.
  cut -f2 "$TMP" | sort | uniq -c | sort -rn | \
    awk '{printf "  %3d  %s\n", $1, $2}'
  printf '\n'
fi

# ── Fix ────────────────────────────────────────────────────────────────────
if [ "$FIX" -eq 1 ]; then
  # Fence-aware tab handling needs awk; the rest is stream work. Order matters:
  # strip trailing space first so a "blank" line of spaces counts as blank when
  # runs are collapsed.
  awk '
    /^[ \t]*(```|~~~)/ { fence = !fence; print; next }
    { if (!fence) gsub(/\t/, "  "); sub(/[ \t]+$/, ""); print }
  ' "$FILE" > "$TMP.f"

  # Collapse 3+ blank lines to exactly 2, and drop trailing blanks.
  python3 - "$TMP.f" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
s = re.sub(r'\n{4,}', '\n\n\n', s)      # 3+ blank lines → 2
s = s.rstrip('\n') + '\n'               # exactly one final newline
open(p, 'w', encoding='utf-8').write(s)
PY

  if cmp -s "$FILE" "$TMP.f"; then
    [ "$QUIET" -eq 0 ] && dim "nothing --fix can change — the remaining items are editorial"
  else
    cp "$TMP.f" "$FILE" || die "cannot write $FILE"
    FIXED=$(grep -cE '	(trailing-space|hard-tab|blank-run|no-final-newline)	' "$TMP" || true)
    ok "fixed $FIXED mechanical problem(s) in $(basename "$FILE")"
    REMAIN=$((N - FIXED))
    [ "$REMAIN" -gt 0 ] && dim "$REMAIN editorial item(s) left — --fix does not touch those"
  fi
fi

exit "$EX_ERR"
