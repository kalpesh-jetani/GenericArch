#!/usr/bin/env bash
# PHASE 2 · LOCATE — resolve the target document, verify it is readable and
# writable, and record its git state before anything edits it.
#
#   ./Scripts/claude-workflows/02-find-claude-file.sh <project> <task-id>
#   ./Scripts/claude-workflows/02-find-claude-file.sh <project> <task-id> --path <file>
#   ./Scripts/claude-workflows/02-find-claude-file.sh <project> <task-id> --allow-missing
#
# Writes 02-file.env. The git state matters more than it looks: phase 5 backs
# the file up before editing, but if the file was ALREADY dirty then a rollback
# to git would also discard work that had nothing to do with this task. Recording
# dirtiness here is what lets phase 5 back up to its own file instead, and
# rollback-claude.sh prefer that backup.
. "$(dirname "$0")/../claude-utils/_common.sh"

usage_text() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; }

[ $# -ge 2 ] || usage
case "$1" in -h|--help) usage "$EX_OK" ;; esac

PROJECT="$1"; TASK_ID="$2"; shift 2
check_id "$PROJECT" "project name"; check_id "$TASK_ID" "task id"

PATH_OVERRIDE=''; ALLOW_MISSING=0
while [ $# -gt 0 ]; do
  case "$1" in
    --path)          [ $# -ge 2 ] || die "--path needs a value" "$EX_USAGE"
                     PATH_OVERRIDE="$2"; shift 2 ;;
    --allow-missing) ALLOW_MISSING=1; shift ;;
    -h|--help)       usage "$EX_OK" ;;
    *)               die "unknown argument: $1" "$EX_USAGE" ;;
  esac
done

TASK_ENV="$(need_artifact "$PROJECT" "$TASK_ID" 01-task.env 1)"
DIR="$(task_dir "$PROJECT" "$TASK_ID")"

TARGET="$(kv_get "$TASK_ENV" TARGET)"
[ -n "$PATH_OVERRIDE" ] && TARGET="$PATH_OVERRIDE"
[ -n "$TARGET" ] || die "phase 1 recorded no target — re-run phase 1 with --target" "$EX_PRECOND"

EXISTS=0; READABLE=0; WRITABLE=0; BYTES=0; LINES=0; DIGEST=''
if [ -e "$TARGET" ]; then
  [ -f "$TARGET" ] || die "target is not a regular file: $TARGET"
  EXISTS=1
  [ -r "$TARGET" ] && READABLE=1
  [ -w "$TARGET" ] && WRITABLE=1
  if [ "$READABLE" -eq 1 ]; then
    BYTES=$(wc -c < "$TARGET" | tr -d ' ')
    LINES=$(wc -l < "$TARGET" | tr -d ' ')
    # Digest lets phase 5 refuse to apply a plan built against a file that has
    # since changed underneath it — the classic way a str_replace lands in the
    # wrong place.
    if command -v shasum >/dev/null 2>&1; then
      DIGEST=$(shasum -a 256 "$TARGET" | awk '{print $1}')
    elif command -v sha256sum >/dev/null 2>&1; then
      DIGEST=$(sha256sum "$TARGET" | awk '{print $1}')
    fi
  fi
fi

if [ "$EXISTS" -eq 0 ]; then
  if [ "$ALLOW_MISSING" -eq 1 ]; then
    warn "target does not exist: $TARGET — continuing (--allow-missing)"
  else
    die "target does not exist: $TARGET
    Pass --allow-missing to plan a new file, or --path to point somewhere else." "$EX_PRECOND"
  fi
elif [ "$READABLE" -eq 0 ]; then
  die "target exists but is not readable: $TARGET" "$EX_PRECOND"
fi

# ── git state ──────────────────────────────────────────────────────────────
GIT_REPO=0; GIT_TRACKED=0; GIT_DIRTY=0; GIT_BRANCH=''; GIT_HEAD=''; GIT_TOPLEVEL=''
if command -v git >/dev/null 2>&1 && [ "$EXISTS" -eq 1 ]; then
  if GIT_TOPLEVEL=$(git -C "$(dirname "$TARGET")" rev-parse --show-toplevel 2>/dev/null); then
    GIT_REPO=1
    GIT_BRANCH=$(git -C "$GIT_TOPLEVEL" rev-parse --abbrev-ref HEAD 2>/dev/null)
    GIT_HEAD=$(git -C "$GIT_TOPLEVEL" rev-parse --short HEAD 2>/dev/null)
    git -C "$GIT_TOPLEVEL" ls-files --error-unmatch -- "$TARGET" >/dev/null 2>&1 && GIT_TRACKED=1
    if [ "$GIT_TRACKED" -eq 1 ]; then
      git -C "$GIT_TOPLEVEL" diff --quiet -- "$TARGET" 2>/dev/null || GIT_DIRTY=1
      git -C "$GIT_TOPLEVEL" diff --cached --quiet -- "$TARGET" 2>/dev/null || GIT_DIRTY=1
    fi
  fi
fi

ENV="$DIR/02-file.env"
: > "$ENV"
kv_set "$ENV" TARGET       "$TARGET"
kv_set "$ENV" EXISTS       "$EXISTS"
kv_set "$ENV" READABLE     "$READABLE"
kv_set "$ENV" WRITABLE     "$WRITABLE"
kv_set "$ENV" BYTES        "$BYTES"
kv_set "$ENV" LINES        "$LINES"
kv_set "$ENV" DIGEST       "$DIGEST"
kv_set "$ENV" GIT_REPO     "$GIT_REPO"
kv_set "$ENV" GIT_TOPLEVEL "$GIT_TOPLEVEL"
kv_set "$ENV" GIT_TRACKED  "$GIT_TRACKED"
kv_set "$ENV" GIT_DIRTY    "$GIT_DIRTY"
kv_set "$ENV" GIT_BRANCH   "$GIT_BRANCH"
kv_set "$ENV" GIT_HEAD     "$GIT_HEAD"

state_set "$PROJECT" "$TASK_ID" 2 done "$([ "$EXISTS" -eq 1 ] && echo "$LINES lines" || echo missing)"

hdr "Phase 2 · locate — $PROJECT/$TASK_ID"
info "target    $TARGET"
if [ "$EXISTS" -eq 1 ]; then
  info "size      $LINES lines, $BYTES bytes"
  info "writable  $([ "$WRITABLE" -eq 1 ] && echo yes || echo "NO — phase 5 will fail")"
else
  info "state     does not exist (planning a new file)"
fi

if [ "$GIT_REPO" -eq 1 ]; then
  info "git       $GIT_BRANCH @ $GIT_HEAD · $([ "$GIT_TRACKED" -eq 1 ] && echo tracked || echo untracked)"
  if [ "$GIT_DIRTY" -eq 1 ]; then
    warn "target already has uncommitted changes.
    Phase 5 will still back up to its own file, and rollback-claude.sh prefers that
    backup — so your existing edits survive a rollback. Do NOT 'git checkout' this
    file to undo phase 5."
  fi
else
  dim "not in a git repo — phases 8 and 9 will have no diff to show"
fi

[ "$WRITABLE" -eq 0 ] && [ "$EXISTS" -eq 1 ] && warn "read-only target — phase 5 cannot apply edits"

ok "wrote $(basename "$ENV")"
dim "next: run-task.sh $PROJECT $TASK_ID 3"
