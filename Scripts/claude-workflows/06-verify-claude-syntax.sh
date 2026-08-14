#!/usr/bin/env bash
# PHASE 6 · VERIFY — validate the edited document: YAML front matter, markdown
# structure, tables, internal links, formatting lint.
#
#   ./Scripts/claude-workflows/06-verify-claude-syntax.sh <project> <task-id>
#   ./Scripts/claude-workflows/06-verify-claude-syntax.sh <project> <task-id> --fix
#
# Writes 06-verify.txt (the full report) and 06-verify.env (the counts).
#
# Composes validate-claude-links.sh and claude-lint.sh rather than reimplementing
# them, so a rule fixed in one place is fixed for every caller. What this phase
# adds on top is the two structural checks those two do not cover: front-matter
# parseability, and table column consistency — the two failures that render as a
# visibly broken document rather than as a lint nit.
#
# Runs standalone: verifying a document nobody has edited yet is a legitimate way
# to find out what is already wrong with it.
. "$(dirname "$0")/../claude-utils/_common.sh"

usage_text() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }

[ $# -ge 2 ] || usage
case "$1" in -h|--help) usage "$EX_OK" ;; esac

PROJECT="$1"; TASK_ID="$2"; shift 2
check_id "$PROJECT" "project name"; check_id "$TASK_ID" "task id"

FIX=0; MAXLINE=100
while [ $# -gt 0 ]; do
  case "$1" in
    --fix)      FIX=1; shift ;;
    --max-line) [ $# -ge 2 ] || die "--max-line needs a number" "$EX_USAGE"
                MAXLINE="$2"; shift 2 ;;
    -h|--help)  usage "$EX_OK" ;;
    *)          die "unknown argument: $1" "$EX_USAGE" ;;
  esac
done

FILE_ENV="$(need_artifact "$PROJECT" "$TASK_ID" 02-file.env 2)"
DIR="$(task_dir "$PROJECT" "$TASK_ID")"
TARGET="$(kv_get "$FILE_ENV" TARGET)"
[ -r "$TARGET" ] || die "cannot read target: $TARGET" "$EX_PRECOND"

UTILS="$(dirname "$0")/../claude-utils"
REPORT="$DIR/06-verify.txt"
: > "$REPORT"

ERRORS=0; WARNS=0

section() { printf '\n=== %s ===\n' "$1" >> "$REPORT"; }

hdr "Phase 6 · verify — $(basename "$TARGET")"

# ── 1. YAML front matter ───────────────────────────────────────────────────
# Only when the document opens with a --- fence. A skill file has one; a
# CLAUDE.md normally does not, and its absence is not a finding.
section "front matter"
if [ "$(head -1 "$TARGET")" = '---' ]; then
  CLOSE=$(awk 'NR > 1 && /^---[ \t]*$/ {print NR; exit}' "$TARGET")
  if [ -z "$CLOSE" ]; then
    printf 'ERROR: front matter opens with --- but never closes\n' >> "$REPORT"
    ERRORS=$((ERRORS + 1))
    printf '  %s✗%s front matter  unterminated --- block\n' "$RED" "$OFF"
  else
    sed -n "2,$((CLOSE - 1))p" "$TARGET" > "$DIR/.frontmatter.$$"
    if command -v python3 >/dev/null 2>&1; then
      YAML_OUT=$(python3 - "$DIR/.frontmatter.$$" <<'PY' 2>&1
import sys
p = sys.argv[1]
text = open(p, encoding='utf-8').read()
try:
    import yaml
except ImportError:
    # No PyYAML: fall back to a shallow check. Every non-continuation,
    # non-comment, non-list line must carry a "key:". That catches the real
    # failure mode — a value with an unquoted colon splitting the mapping —
    # without pretending to be a parser.
    bad = []
    for i, line in enumerate(text.split('\n'), 1):
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        if line[0] in ' \t-':
            continue
        if ':' not in line:
            bad.append((i, line))
    if bad:
        for i, line in bad:
            print("ERROR: line %d is not a key: value pair: %s" % (i, line[:60]))
    else:
        print("OK (shallow — PyYAML not installed)")
    sys.exit(0)
try:
    yaml.safe_load(text)
    print("OK")
except Exception as e:
    print("ERROR: %s" % str(e).replace('\n', ' ')[:200])
PY
)
      printf '%s\n' "$YAML_OUT" >> "$REPORT"
      if printf '%s' "$YAML_OUT" | grep -q '^ERROR'; then
        ERRORS=$((ERRORS + 1))
        printf '  %s✗%s front matter  %s\n' "$RED" "$OFF" "$(printf '%s' "$YAML_OUT" | head -1)"
      else
        printf '  %s✓%s front matter  %s\n' "$GRN" "$OFF" "$(printf '%s' "$YAML_OUT" | head -1)"
      fi
    fi
    rm -f "$DIR/.frontmatter.$$"
  fi
else
  printf 'none (document does not open with ---)\n' >> "$REPORT"
  printf '  %s·%s front matter  none\n' "$DIM" "$OFF"
fi

# ── 2. Tables ──────────────────────────────────────────────────────────────
# A pipe table whose rows disagree on column count renders with cells dropped or
# merged — silently, and only in the renderer. CLAUDE.md is table-heavy enough
# that this is worth its own check.
section "tables"
awk '
  /^[ \t]*(```|~~~)/ { fence = !fence; next }
  fence { next }

  function cols(s) {
    sub(/^[ \t]*\|/, "", s); sub(/\|[ \t]*$/, "", s)
    n = split(s, parts, "|")
    return n
  }

  /^[ \t]*\|/ {
    if (!in_table) { in_table = 1; start = FNR; expect = cols($0); row = 1; delim = 0; next }
    row++
    if (row == 2 && $0 ~ /^[ \t]*\|[ \t:|-]+\|?[ \t]*$/) { delim = 1 }
    c = cols($0)
    if (c != expect) printf "ERROR: line %d: table starting line %d has %d columns, this row has %d\n", FNR, start, expect, c
    next
  }

  in_table {
    if (!delim && row >= 2) printf "WARN: line %d: table starting line %d has no |---| delimiter row\n", start, start
    in_table = 0; row = 0
  }

  END {
    if (in_table && !delim && row >= 2) printf "WARN: line %d: table starting line %d has no |---| delimiter row\n", start, start
  }
' "$TARGET" >> "$REPORT"

T_ERR=$(count_match '^ERROR: line .*table' "$REPORT")
T_WARN=$(count_match '^WARN: line .*table' "$REPORT")
ERRORS=$((ERRORS + T_ERR)); WARNS=$((WARNS + T_WARN))
if [ "$T_ERR" -gt 0 ]; then
  printf '  %s✗%s tables        %s row(s) with a mismatched column count\n' "$RED" "$OFF" "$T_ERR"
  grep '^ERROR: line .*table' "$REPORT" | sed 's/^ERROR: /      /' | head -5
elif [ "$T_WARN" -gt 0 ]; then
  printf '  %s⚠%s tables        %s missing a delimiter row\n' "$YEL" "$OFF" "$T_WARN"
else
  printf '  %s✓%s tables        consistent\n' "$GRN" "$OFF"
fi

# ── 3. Links ───────────────────────────────────────────────────────────────
section "links"
if bash "$UTILS/validate-claude-links.sh" "$TARGET" --quiet >> "$REPORT" 2>&1; then
  printf '  %s✓%s links         all internal links resolve\n' "$GRN" "$OFF"
else
  ERRORS=$((ERRORS + 1))
  printf '  %s✗%s links         broken — see the report\n' "$RED" "$OFF"
  bash "$UTILS/validate-claude-links.sh" "$TARGET" 2>&1 | grep '^  line' | head -6
fi

# ── 4. Lint ────────────────────────────────────────────────────────────────
section "lint"
LINT_ARGS="--quiet --max-line $MAXLINE"
[ "$FIX" -eq 1 ] && LINT_ARGS="--fix $LINT_ARGS"
if bash "$UTILS/claude-lint.sh" "$TARGET" $LINT_ARGS >> "$REPORT" 2>&1; then
  printf '  %s✓%s lint          clean\n' "$GRN" "$OFF"
else
  # Lint findings are formatting, not correctness: they warn, they do not fail
  # the phase. A long line has never broken a document.
  LINT_SUMMARY=$(bash "$UTILS/claude-lint.sh" "$TARGET" --max-line "$MAXLINE" 2>&1 | \
                 awk '/^ +[0-9]+ +[a-z-]+$/ {printf "%s×%s ", $2, $1}')
  WARNS=$((WARNS + 1))
  printf '  %s⚠%s lint          %s\n' "$YEL" "$OFF" "${LINT_SUMMARY:-see report}"
  [ "$FIX" -eq 1 ] && dim "--fix applied the mechanical subset"
fi

ENV="$DIR/06-verify.env"
: > "$ENV"
kv_set "$ENV" VERIFIED "$(now)"
kv_set "$ENV" TARGET   "$TARGET"
kv_set "$ENV" ERRORS   "$ERRORS"
kv_set "$ENV" WARNINGS "$WARNS"
kv_set "$ENV" REPORT   "$REPORT"

printf '\n'
if [ "$ERRORS" -gt 0 ]; then
  state_set "$PROJECT" "$TASK_ID" 6 failed "$ERRORS errors"
  info "report  $REPORT"
  die "$ERRORS error(s), $WARNS warning(s) — fix before phase 8.
    Undo everything: ./Scripts/claude-utils/rollback-claude.sh $PROJECT $TASK_ID" "$EX_ERR"
fi

state_set "$PROJECT" "$TASK_ID" 6 done "$WARNS warnings"
ok "structure valid$([ "$WARNS" -gt 0 ] && printf ' — %s warning(s)' "$WARNS")"
info "report  $REPORT"
dim "next: run-task.sh $PROJECT $TASK_ID 7"
