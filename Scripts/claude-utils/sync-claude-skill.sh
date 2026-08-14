#!/usr/bin/env bash
# Post-task: find the skills and commands that quote what this task just changed,
# so a rule edited in one place does not survive uncorrected in three others.
#
#   ./Scripts/claude-utils/sync-claude-skill.sh <project> <task-id>
#   ./Scripts/claude-utils/sync-claude-skill.sh <project> <task-id> --write
#
# Writes sync-report.md in the task directory.
#
# Reports by default and changes nothing. A skill body is a procedure someone
# wrote; rewriting it from a diff would be guessing at intent. What this can do
# honestly is point at every file that references a changed section or a removed
# phrase, and leave the editing to a reader.
#
# --write appends a dated, clearly-marked note to each affected file listing what
# moved. It backs each one up first. It never edits prose in place.
. "$(dirname "$0")/_common.sh"

usage_text() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; }

[ $# -ge 2 ] || usage
case "$1" in -h|--help) usage "$EX_OK" ;; esac

PROJECT="$1"; TASK_ID="$2"; shift 2
check_id "$PROJECT" "project name"; check_id "$TASK_ID" "task id"

WRITE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --write)   WRITE=1; shift ;;
    -h|--help) usage "$EX_OK" ;;
    *)         die "unknown argument: $1" "$EX_USAGE" ;;
  esac
done

DIR="$(task_dir "$PROJECT" "$TASK_ID")"
FILE_ENV="$(need_artifact "$PROJECT" "$TASK_ID" 02-file.env 2)"
APPLIED="$(need_artifact "$PROJECT" "$TASK_ID" 05-applied.tsv 5)"
TARGET="$(kv_get "$FILE_ENV" TARGET)"
ROOT="$(project_field "$PROJECT" 2)"
REPORT="$DIR/sync-report.md"

hdr "sync — skills referencing what $TASK_ID changed"

# Where a project keeps reusable procedures. Anything markdown under these, plus
# the docs tree, can quote a rule that just moved.
SEARCH_DIRS=''
for d in "$ROOT/.claude/skills" "$ROOT/.claude/commands" "$ROOT/docs"; do
  [ -d "$d" ] && SEARCH_DIRS="$SEARCH_DIRS $d"
done

if [ -z "$SEARCH_DIRS" ]; then
  dim "no .claude/skills, .claude/commands or docs/ under $ROOT — nothing to sync"
  printf '# sync — nothing to check\n\nNo skill, command or docs directory under `%s`.\n' "$ROOT" > "$REPORT"
  exit "$EX_OK"
fi

SECTIONS=$(awk -F'\t' '!/^#/ {print $2}' "$APPLIED" | sort -u)
[ -n "$SECTIONS" ] || die "phase 5 recorded no sections — nothing to trace" "$EX_PRECOND"

# Phrases that phase 5 REMOVED are the strongest signal: text deleted from the
# source of truth but still quoted elsewhere is, by definition, now wrong.
: > "$DIR/.removed.$$"
for f in "$DIR"/04-payload-*.old; do
  [ -f "$f" ] || continue
  # Lines long enough to be a real quotation rather than a coincidence.
  awk 'length($0) > 30 {gsub(/^[ \t]+|[ \t]+$/, ""); if ($0 !~ /^[-*#|>]/) print}' "$f" >> "$DIR/.removed.$$"
done
sort -u "$DIR/.removed.$$" -o "$DIR/.removed.$$" 2>/dev/null || true

{
  printf '# Sync report — %s/%s\n\n' "$PROJECT" "$TASK_ID"
  printf -- '- **Changed document:** `%s`\n' "$TARGET"
  printf -- '- **Generated:** %s\n\n' "$(now)"
  printf 'Files below quote a section this task edited, or text it removed. Each needs\n'
  printf 'reading — a match is a candidate, not a defect.\n\n'
} > "$REPORT"

HITS=0

# ── 1. Files naming a changed section ──────────────────────────────────────
printf '## Sections\n\n' >> "$REPORT"
printf '%s\n' "$SECTIONS" | while IFS= read -r sec; do
  [ -n "$sec" ] || continue
  FOUND=$(grep -rl --include='*.md' -F "$sec" $SEARCH_DIRS 2>/dev/null | grep -v "^$TARGET$" || true)
  if [ -n "$FOUND" ]; then
    printf '### `%s`\n\n' "$sec" >> "$REPORT"
    printf '%s\n' "$FOUND" | while IFS= read -r f; do
      LN=$(grep -nF "$sec" "$f" 2>/dev/null | head -3 | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')
      printf -- '- `%s` (line %s)\n' "${f#$ROOT/}" "$LN" >> "$REPORT"
    done
    printf '\n' >> "$REPORT"
    printf '%s\n' "$FOUND" >> "$DIR/.hits.$$"
  fi
done

# ── 2. Files quoting removed text ──────────────────────────────────────────
printf '## Removed text still quoted elsewhere\n\n' >> "$REPORT"
STALE=0
if [ -s "$DIR/.removed.$$" ]; then
  while IFS= read -r phrase; do
    [ -n "$phrase" ] || continue
    FOUND=$(grep -rl --include='*.md' -F "$phrase" $SEARCH_DIRS 2>/dev/null | grep -v "^$TARGET$" || true)
    if [ -n "$FOUND" ]; then
      printf -- '- **"%s…"**\n' "$(printf '%s' "$phrase" | cut -c1-60)" >> "$REPORT"
      printf '%s\n' "$FOUND" | sed "s|^$ROOT/||;s|^|    - \`|;s|$|\`|" >> "$REPORT"
      printf '%s\n' "$FOUND" >> "$DIR/.hits.$$"
      STALE=$((STALE + 1))
    fi
  done < "$DIR/.removed.$$"
fi
[ "$STALE" -eq 0 ] && printf 'None — no removed phrase is quoted in another file.\n\n' >> "$REPORT"
rm -f "$DIR/.removed.$$"

FILES=$(sort -u "$DIR/.hits.$$" 2>/dev/null || true)
rm -f "$DIR/.hits.$$"
HITS=$(printf '%s\n' "$FILES" | count_stdin)

if [ "$HITS" -eq 0 ]; then
  ok "no skill, command or doc references the changed sections"
  dim "report: $REPORT"
  exit "$EX_OK"
fi

info "$HITS file(s) reference what changed"
printf '\n'
printf '%s\n' "$FILES" | sed "s|^$ROOT/||;s|^|  |"
printf '\n'

# ── 3. --write: leave a marker, never rewrite prose ────────────────────────
if [ "$WRITE" -eq 1 ]; then
  SECS_ONE_LINE=$(printf '%s' "$SECTIONS" | tr '\n' ';' | sed 's/;$//;s/;/; /g')
  printf '%s\n' "$FILES" | while IFS= read -r f; do
    [ -f "$f" ] && [ -w "$f" ] || { warn "skipping unwritable $f"; continue; }
    cp -p "$f" "$f.presync.bak" || { warn "no backup for $f — skipped"; continue; }
    {
      printf '\n<!-- sync: %s — %s/%s edited `%s`\n' "$(today)" "$PROJECT" "$TASK_ID" "$(basename "$TARGET")"
      printf '     Sections changed: %s\n' "$SECS_ONE_LINE"
      printf '     This file quotes one of them. Re-read it against the source and delete\n'
      printf '     this marker once reconciled. Report: %s -->\n' "${REPORT#$ROOT/}"
    } >> "$f"
    ok "marked ${f#$ROOT/}"
    dim "  backup: ${f#$ROOT/}.presync.bak"
  done
  printf '\n'
  warn "markers appended. They are comments, so they do not change rendering — but they
    are also not the fix. Reconcile each file and delete its marker."
else
  dim "report: $REPORT"
  dim "--write appends a dated marker to each file above (backing it up first)"
fi
