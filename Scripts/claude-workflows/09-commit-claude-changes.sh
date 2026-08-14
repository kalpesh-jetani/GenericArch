#!/usr/bin/env bash
#@kind      workflow
#@platform  macos
#@claude    emit-only
#@purpose   PHASE 9 commit: compose a tagged commit message and EMIT the command.
#@usage     09-commit-claude-changes.sh <project> <task-id> [--type T] [--scope S] [--no-coauthor]
#@in        05-applied.tsv 01-task.env 06-verify.env 07-test.env
#@out       09-message.txt:text 09-commit.sh:sh(NOT RUN) 09-commit.env:kv
#@exit      0=composed 2=usage 3=nothing-applied|not-a-git-repo
#@effects   writes files only. NEVER commits or pushes (CLAUDE.md 2.11)
# PHASE 9 · COMMIT — compose a tagged commit message from the task record and
# emit the command that would apply it.
#
#   ./Scripts/claude-workflows/09-commit-claude-changes.sh <project> <task-id>
#   ./Scripts/claude-workflows/09-commit-claude-changes.sh <project> <task-id> --type docs
#   ./Scripts/claude-workflows/09-commit-claude-changes.sh <project> <task-id> --no-coauthor
#
# Writes 09-message.txt · 09-commit.sh · 09-commit.env.
#
# ** THIS PHASE NEVER RUNS GIT. ** No commit, no push, no tag, no add. It writes
# a message and a script, prints them, and stops.
#
# CLAUDE.md §2.11: the working tree is left alone and the user commits when they
# decide the work is done. A pipeline that committed its own output would make
# that decision for them — and "the phase is called commit" is not a reason to
# take it. The task id goes in the message so the artifacts under
# .claude/claude-tasks/ can be found again from git log.
. "$(dirname "$0")/../claude-utils/_common.sh"

usage_text() { usage_from "$0"; }

[ $# -ge 2 ] || usage
case "$1" in -h|--help) usage "$EX_OK" ;; esac

PROJECT="$1"; TASK_ID="$2"; shift 2
check_id "$PROJECT" "project name"; check_id "$TASK_ID" "task id"

TYPE=''; SCOPE_OVERRIDE=''; COAUTHOR=1
while [ $# -gt 0 ]; do
  case "$1" in
    --type)        [ $# -ge 2 ] || die "--type needs a value" "$EX_USAGE"
                   TYPE="$2"; shift 2 ;;
    --scope)       [ $# -ge 2 ] || die "--scope needs a value" "$EX_USAGE"
                   SCOPE_OVERRIDE="$2"; shift 2 ;;
    --no-coauthor) COAUTHOR=0; shift ;;
    -h|--help)     usage "$EX_OK" ;;
    *)             die "unknown argument: $1" "$EX_USAGE" ;;
  esac
done

FILE_ENV="$(need_artifact "$PROJECT" "$TASK_ID" 02-file.env 2)" || exit $?
DIR="$(task_dir "$PROJECT" "$TASK_ID")"
TARGET="$(kv_get "$FILE_ENV" TARGET)"
GIT_TOP="$(kv_get "$FILE_ENV" GIT_TOPLEVEL)"

[ -n "$GIT_TOP" ] || die "$TARGET is not in a git repository — nothing to compose a commit for" "$EX_PRECOND"

APPLIED="$DIR/05-applied.tsv"
[ -f "$APPLIED" ] || die "phase 5 has not applied anything — there is nothing to commit.
    Run phases 4 and 5 first." "$EX_PRECOND"

TASK_ENV="$DIR/01-task.env"
TASK_TYPE="$(kv_get "$TASK_ENV" TASK_TYPE)"
TASK_SCOPE="$(kv_get "$TASK_ENV" TASK_SCOPE)"

# Conventional-commit type. Everything this pipeline edits is a markdown
# document, so `docs` is right unless the caller says otherwise.
[ -n "$TYPE" ] || TYPE=docs

# Subject scope: the document, not the task type — a reader scanning git log
# wants to know which file's rules moved.
if [ -n "$SCOPE_OVERRIDE" ]; then
  SCOPE="$SCOPE_OVERRIDE"
else
  SCOPE=$(basename "$TARGET" .md | tr '[:upper:]' '[:lower:]')
fi

SECTIONS=$(awk -F'\t' '!/^#/ {print $2}' "$APPLIED" | sort -u | tr '\n' ',' | sed 's/,$//;s/,/, /g')
N_EDITS=$(count_rows "$APPLIED")

# Subject line. Prefer the task's own words over a generated phrase — the person
# who wrote the request described the change better than a keyword map can.
SUBJECT_BODY="$TASK_SCOPE"
[ -n "$SUBJECT_BODY" ] || SUBJECT_BODY="$TASK_TYPE across $N_EDITS section(s)"
# Trim to keep the whole subject under the 72-column convention, at a word
# boundary — a subject cut mid-word ("drop the Dispatc") reads as corruption.
MAXBODY=$((68 - ${#TYPE} - ${#SCOPE} - ${#TASK_ID}))
[ "$MAXBODY" -lt 20 ] && MAXBODY=20
if [ "${#SUBJECT_BODY}" -gt "$MAXBODY" ]; then
  SUBJECT_BODY=$(printf '%s' "$SUBJECT_BODY" | cut -c1-"$MAXBODY" | sed 's/[^ ]*$//')
fi
SUBJECT_BODY=$(printf '%s' "$SUBJECT_BODY" | sed 's/[ .,;:]*$//')

MSG="$DIR/09-message.txt"
{
  printf '%s(%s): %s [%s]\n\n' "$TYPE" "$SCOPE" "$SUBJECT_BODY" "$TASK_ID"

  if [ -f "$DIR/01-request.txt" ]; then
    # The request, wrapped. A commit that records what was asked for is the one
    # you can still understand a year later.
    fold -s -w 76 "$DIR/01-request.txt" | sed 's/[ \t]*$//'
    printf '\n'
  fi

  printf 'Sections: %s\n' "${SECTIONS:-—}"
  printf 'Edits: %s\n' "$N_EDITS"

  if [ -f "$DIR/06-verify.env" ]; then
    printf 'Verified: %s error(s), %s warning(s)\n' \
      "$(kv_get "$DIR/06-verify.env" ERRORS)" "$(kv_get "$DIR/06-verify.env" WARNINGS)"
  fi
  if [ -f "$DIR/07-test.env" ]; then
    printf 'Snippets: %s block(s) extracted, NOT executed\n' "$(kv_get "$DIR/07-test.env" CODE_BLOCKS)"
    NF_SYM="$(kv_get "$DIR/07-test.env" NOT_FOUND)"
    [ "${NF_SYM:-0}" != 0 ] && printf 'Unverified symbols: %s (grep heuristic)\n' "$NF_SYM"
  fi
  printf 'Task: %s/%s\n' "$PROJECT" "$TASK_ID"

  if [ "$COAUTHOR" -eq 1 ]; then
    printf '\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n'
  fi
} > "$MSG"

# ── The emitted script ─────────────────────────────────────────────────────
CMD="$DIR/09-commit.sh"
{
  printf '#!/usr/bin/env bash\n'
  printf '# GENERATED by 09-commit-claude-changes.sh — %s\n' "$(now)"
  printf '# Task: %s/%s\n#\n' "$PROJECT" "$TASK_ID"
  printf '# The pipeline did NOT run this (CLAUDE.md §2.11). Review, then:\n'
  printf '#   bash %s\n#\n' "$CMD"
  printf '# There is no push here on purpose. Push when you have looked at the commit.\n\n'
  printf 'set -eu\n\n'
  printf 'cd %s\n\n' "$(printf '%q' "$GIT_TOP")"
  printf 'git add -- %s\n' "$(printf '%q' "$TARGET")"
  printf 'git commit -F %s\n\n' "$(printf '%q' "$MSG")"
  printf 'printf "\\ncommitted. Review it:\\n  git show --stat HEAD\\n"\n'
  printf 'printf "Then push when you are ready:\\n  git push\\n"\n'
} > "$CMD"
chmod +x "$CMD"

BRANCH=$(git -C "$GIT_TOP" rev-parse --abbrev-ref HEAD 2>/dev/null)
DEFAULT_BRANCH=$(git -C "$GIT_TOP" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
[ -n "$DEFAULT_BRANCH" ] || DEFAULT_BRANCH=main

ENV="$DIR/09-commit.env"
: > "$ENV"
kv_set "$ENV" COMPOSED_AT "$(now)"
kv_set "$ENV" MESSAGE     "$MSG"
kv_set "$ENV" SCRIPT      "$CMD"
kv_set "$ENV" BRANCH      "$BRANCH"
kv_set "$ENV" EXECUTED    "0"

state_set "$PROJECT" "$TASK_ID" 9 emitted "not committed"

hdr "Phase 9 · commit — composed, NOT run"
printf '\n'
sed 's/^/  /' "$MSG"
printf '\n'

if [ "$BRANCH" = "$DEFAULT_BRANCH" ]; then
  warn "you are on $BRANCH. Branch first if this should not land directly there:
      git -C $GIT_TOP checkout -b docs/$TASK_ID"
fi

hdr "to commit — run this yourself"
printf '  bash %s\n' "$CMD"
printf '\n'
dim "or by hand:"
printf '  %sgit -C %s add -- %s%s\n' "$DIM" "$GIT_TOP" "$(basename "$TARGET")" "$OFF"
printf '  %sgit -C %s commit -F %s%s\n' "$DIM" "$GIT_TOP" "$MSG" "$OFF"
printf '\n'
dim "CLAUDE.md §2.11 — this tooling never commits or pushes. The working tree is"
dim "left as it is; the decision that the work is done is yours."
ok "wrote 09-message.txt · 09-commit.sh"
