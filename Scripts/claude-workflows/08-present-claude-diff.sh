#!/usr/bin/env bash
# PHASE 8 · PRESENT — produce the diff, summarise it per section, and stage it
# for review.
#
#   ./Scripts/claude-workflows/08-present-claude-diff.sh <project> <task-id>
#   ./Scripts/claude-workflows/08-present-claude-diff.sh <project> <task-id> --full
#   ./Scripts/claude-workflows/08-present-claude-diff.sh <project> <task-id> --stage
#
# Writes 08-diff.patch · 08-summary.md · 08-present.env.
#
# The per-section summary is the point of this phase. A 200-line diff of a
# CLAUDE.md tells a reviewer nothing about which RULES moved; "§6 Concurrency:
# +12/-4" tells them exactly where to look. Sections are re-derived from the file
# as it stands now, not from phase 3's pre-edit inventory, so a heading the edit
# added maps correctly.
#
# --stage runs `git add`. Without it, the command is printed. Staging is
# reversible and local, so it is offered — committing is not, and phase 9 never
# runs anything at all.
. "$(dirname "$0")/../claude-utils/_common.sh"

usage_text() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; }

[ $# -ge 2 ] || usage
case "$1" in -h|--help) usage "$EX_OK" ;; esac

PROJECT="$1"; TASK_ID="$2"; shift 2
check_id "$PROJECT" "project name"; check_id "$TASK_ID" "task id"

FULL=0; STAGE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --full)    FULL=1; shift ;;
    --stage)   STAGE=1; shift ;;
    -h|--help) usage "$EX_OK" ;;
    *)         die "unknown argument: $1" "$EX_USAGE" ;;
  esac
done

FILE_ENV="$(need_artifact "$PROJECT" "$TASK_ID" 02-file.env 2)"
DIR="$(task_dir "$PROJECT" "$TASK_ID")"
TARGET="$(kv_get "$FILE_ENV" TARGET)"
GIT_TOP="$(kv_get "$FILE_ENV" GIT_TOPLEVEL)"
GIT_TRACKED="$(kv_get "$FILE_ENV" GIT_TRACKED)"
[ -r "$TARGET" ] || die "cannot read target: $TARGET" "$EX_PRECOND"

PATCH="$DIR/08-diff.patch"
SUMMARY="$DIR/08-summary.md"
BACKUP="$(cat "$DIR/05-backup/latest" 2>/dev/null || true)"

# ── Produce the diff ───────────────────────────────────────────────────────
# Prefer git (it knows the committed baseline). Fall back to the phase-5 backup,
# which is the only baseline available for an untracked file.
SOURCE=''
if [ -n "$GIT_TOP" ] && [ "$GIT_TRACKED" = 1 ] && command -v git >/dev/null 2>&1; then
  git -C "$GIT_TOP" diff -- "$TARGET" > "$PATCH" 2>/dev/null
  SOURCE="git diff (working tree vs HEAD)"
  if [ ! -s "$PATCH" ]; then
    # Nothing unstaged — the change may already be staged.
    git -C "$GIT_TOP" diff --cached -- "$TARGET" > "$PATCH" 2>/dev/null
    [ -s "$PATCH" ] && SOURCE="git diff --cached (staged vs HEAD)"
  fi
fi

if [ ! -s "$PATCH" ] && [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
  diff -u "$BACKUP" "$TARGET" > "$PATCH" 2>/dev/null || true
  [ -s "$PATCH" ] && SOURCE="diff against the phase-5 backup"
fi

if [ ! -s "$PATCH" ]; then
  state_set "$PROJECT" "$TASK_ID" 8 empty "no changes"
  hdr "Phase 8 · present"
  warn "no changes to show for $(basename "$TARGET").
    Either phase 5 has not run, or it applied edits that changed nothing."
  : > "$SUMMARY"
  printf '# %s/%s — no changes\n' "$PROJECT" "$TASK_ID" > "$SUMMARY"
  ENV="$DIR/08-present.env"
  : > "$ENV"
  kv_set "$ENV" CHANGED 0
  exit "$EX_OK"
fi

ADDED=$(count_match '^+[^+]' "$PATCH")
REMOVED=$(count_match '^-[^-]' "$PATCH")

# ── Attribute hunks to sections ────────────────────────────────────────────
md_sections "$TARGET" > "$DIR/.sections-now.$$"

awk -F'\t' '
  # pass 1: the current section map
  FNR == NR { n++; S[n] = $2; E[n] = $3; T[n] = $5; next }

  function section_of(ln) {
    for (i = 1; i <= n; i++) if (S[i] <= ln && ln <= E[i]) return T[i]
    return "(preamble)"
  }

  # pass 2: the patch
  /^@@/ {
    # @@ -old,len +new,len @@
    if (match($0, /\+[0-9]+/)) {
      newstart = substr($0, RSTART + 1, RLENGTH - 1) + 0
      cur = section_of(newstart)
      if (!(cur in seen)) { order[++k] = cur; seen[cur] = 1 }
    }
    next
  }
  /^\+\+\+|^---/ { next }
  /^\+/ { if (cur != "") add[cur]++ }
  /^-/  { if (cur != "") del[cur]++ }

  END {
    for (i = 1; i <= k; i++) {
      s = order[i]
      printf "%s\t%d\t%d\n", s, add[s] + 0, del[s] + 0
    }
  }
' "$DIR/.sections-now.$$" "$PATCH" > "$DIR/.bysection.$$"

# ── Summary ────────────────────────────────────────────────────────────────
TASK_ENV="$DIR/01-task.env"
{
  printf '# %s / %s\n\n' "$PROJECT" "$TASK_ID"
  printf -- '- **Document:** `%s`\n' "$TARGET"
  [ -f "$TASK_ENV" ] && printf -- '- **Task type:** %s\n' "$(kv_get "$TASK_ENV" TASK_TYPE)"
  [ -f "$TASK_ENV" ] && printf -- '- **Scope:** %s\n' "$(kv_get "$TASK_ENV" TASK_SCOPE)"
  printf -- '- **Diff:** +%s / -%s lines · %s\n' "$ADDED" "$REMOVED" "$SOURCE"
  printf '\n## Changed sections\n\n'
  printf '| Section | + | - |\n|---|---:|---:|\n'
  awk -F'\t' '{printf "| %s | %d | %d |\n", $1, $2, $3}' "$DIR/.bysection.$$"

  if [ -f "$DIR/05-applied.tsv" ]; then
    printf '\n## Edits applied\n\n'
    printf '| # | Action | Section | Note |\n|---|---|---|---|\n'
    awk -F'\t' '!/^#/ {printf "| %s | %s | %s | %s |\n", $1, $3, $2, $6}' "$DIR/05-applied.tsv"
  fi

  if [ -f "$DIR/06-verify.env" ]; then
    printf '\n## Verification\n\n'
    printf -- '- Errors: %s\n' "$(kv_get "$DIR/06-verify.env" ERRORS)"
    printf -- '- Warnings: %s\n' "$(kv_get "$DIR/06-verify.env" WARNINGS)"
  fi

  if [ -f "$DIR/07-test.env" ]; then
    printf '\n## Snippets and symbols\n\n'
    printf -- '- Code blocks: %s (%s checkable)\n' \
      "$(kv_get "$DIR/07-test.env" CODE_BLOCKS)" "$(kv_get "$DIR/07-test.env" CHECKABLE)"
    printf -- '- Symbols not found by grep: %s\n' "$(kv_get "$DIR/07-test.env" NOT_FOUND)"
    printf -- '- **Not run** (CLAUDE.md §2.12): `bash %s`\n' "$(kv_get "$DIR/07-test.env" COMMANDS)"
  fi
} > "$SUMMARY"

ENV="$DIR/08-present.env"
: > "$ENV"
kv_set "$ENV" CHANGED  1
kv_set "$ENV" ADDED    "$ADDED"
kv_set "$ENV" REMOVED  "$REMOVED"
kv_set "$ENV" PATCH    "$PATCH"
kv_set "$ENV" SUMMARY  "$SUMMARY"
kv_set "$ENV" SOURCE   "$SOURCE"
kv_set "$ENV" STAGED   "$STAGE"

# ── Output ─────────────────────────────────────────────────────────────────
hdr "Phase 8 · present — +$ADDED / -$REMOVED"
dim "$SOURCE"
printf '\n'
# Straight from the attribution data, not by re-parsing the markdown table out of
# the summary — a sed range over rendered output breaks the moment the layout does.
awk -F'\t' -v g="$GRN" -v r="$RED" -v o="$OFF" \
  '{printf "  %-40s %s+%-5s%s %s-%s%s\n", $1, g, $2, o, r, $3, o}' "$DIR/.bysection.$$"
rm -f "$DIR/.sections-now.$$" "$DIR/.bysection.$$"

if [ "$FULL" -eq 1 ]; then
  hdr "diff"
  cat "$PATCH"
else
  printf '\n'
  dim "patch    $PATCH"
  dim "summary  $SUMMARY"
  dim "(--full prints the whole diff here)"
fi

# ── Stage ──────────────────────────────────────────────────────────────────
printf '\n'
if [ -z "$GIT_TOP" ]; then
  dim "not a git repo — nothing to stage"
elif [ "$STAGE" -eq 1 ]; then
  git -C "$GIT_TOP" add -- "$TARGET" || die "git add failed"
  ok "staged $(basename "$TARGET")"
else
  hdr "to stage for review"
  printf '  git -C %s add -- %s\n' "$GIT_TOP" "$TARGET"
  dim "or re-run this phase with --stage"
fi

state_set "$PROJECT" "$TASK_ID" 8 done "+$ADDED/-$REMOVED"
dim "next: run-task.sh $PROJECT $TASK_ID 9   (emits a commit command; never runs it)"
