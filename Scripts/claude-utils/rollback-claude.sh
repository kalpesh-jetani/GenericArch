#!/usr/bin/env bash
#@kind      util
#@platform  macos
#@claude    needs-approval
#@purpose   Undo phase 5 by restoring the pre-edit backup (not git).
#@usage     rollback-claude.sh <project> <task-id> [--yes] [--from-git] [--force]
#@in        02-file.env 05-backup/latest --yes:flag(REQUIRED to write)
#@out       restores the target; writes a pre-rollback backup
#@exit      0=restored|nothing-to-do 1=restore failed 3=no-backup 4=no --yes
#@effects   WRITES THE TARGET. Preview-only without --yes
# Emergency: undo the last applied edit and restore the document.
#
#   ./Scripts/claude-utils/rollback-claude.sh <project> <task-id>          # preview
#   ./Scripts/claude-utils/rollback-claude.sh <project> <task-id> --yes    # do it
#   ./Scripts/claude-utils/rollback-claude.sh <project> <task-id> --from-git --yes
#
# Restores from the phase-5 backup by default. That is deliberately NOT git:
# phase 2 may have found the document already dirty, and `git checkout` would
# discard those unrelated edits along with this task's. The backup contains
# exactly the bytes that were there immediately before phase 5 wrote, so
# restoring it undoes this task and nothing else.
#
# --from-git restores the committed version instead, and refuses when phase 2
# recorded the file as already dirty — unless you add --force, having understood
# that it throws away work this task never touched.
. "$(dirname "$0")/_common.sh"

usage_text() { usage_from "$0"; }

[ $# -ge 2 ] || usage
case "$1" in -h|--help) usage "$EX_OK" ;; esac

PROJECT="$1"; TASK_ID="$2"; shift 2
check_id "$PROJECT" "project name"; check_id "$TASK_ID" "task id"

YES=0; FROM_GIT=0; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y)   YES=1; shift ;;
    --from-git) FROM_GIT=1; shift ;;
    --force)    FORCE=1; shift ;;
    -h|--help)  usage "$EX_OK" ;;
    *)          die "unknown argument: $1" "$EX_USAGE" ;;
  esac
done

DIR="$(task_dir "$PROJECT" "$TASK_ID")"
[ -d "$DIR" ] || die "no such task: $PROJECT/$TASK_ID" "$EX_USAGE"
FILE_ENV="$(need_artifact "$PROJECT" "$TASK_ID" 02-file.env 2)" || exit $?
TARGET="$(kv_get "$FILE_ENV" TARGET)"
GIT_TOP="$(kv_get "$FILE_ENV" GIT_TOPLEVEL)"
WAS_DIRTY="$(kv_get "$FILE_ENV" GIT_DIRTY)"

hdr "rollback — $PROJECT/$TASK_ID"
info "target  $TARGET"

# ── Choose a source ────────────────────────────────────────────────────────
if [ "$FROM_GIT" -eq 1 ]; then
  [ -n "$GIT_TOP" ] || die "not a git repository — cannot restore from git" "$EX_PRECOND"
  if [ "$WAS_DIRTY" = 1 ] && [ "$FORCE" -eq 0 ]; then
    die "phase 2 recorded this file as ALREADY having uncommitted changes.
    Restoring from git would discard those too — work this task never touched.
    Use the phase-5 backup instead (drop --from-git), or add --force if you are
    certain you want the committed version." "$EX_PRECOND"
  fi
  SOURCE_DESC="git HEAD"
  PREVIEW_CMD="git -C $GIT_TOP diff -- $TARGET"
else
  BACKUP="$(cat "$DIR/05-backup/latest" 2>/dev/null || true)"
  if [ -z "$BACKUP" ] || [ ! -f "$BACKUP" ]; then
    die "no phase-5 backup for this task — nothing was applied, or the backup is gone.
    Available backups:
$(ls -1 "$DIR/05-backup" 2>/dev/null | sed 's/^/      /' || printf '      (none)')
    To restore the committed version instead: --from-git" "$EX_PRECOND"
  fi
  SOURCE_DESC="$BACKUP"
fi
info "restore from  $SOURCE_DESC"

# ── Preview ────────────────────────────────────────────────────────────────
printf '\n'
if [ "$FROM_GIT" -eq 1 ]; then
  CHANGES=$(git -C "$GIT_TOP" diff --numstat -- "$TARGET" 2>/dev/null)
  if [ -z "$CHANGES" ]; then
    ok "already identical to HEAD — nothing to roll back"
    exit "$EX_OK"
  fi
  printf '  %swould discard:%s +%s / -%s lines\n' "$DIM" "$OFF" \
    "$(printf '%s' "$CHANGES" | awk '{print $1}')" "$(printf '%s' "$CHANGES" | awk '{print $2}')"
else
  if cmp -s "$BACKUP" "$TARGET"; then
    ok "target already matches the backup — nothing to roll back"
    exit "$EX_OK"
  fi
  ADD=$(diff -u "$BACKUP" "$TARGET" 2>/dev/null | grep -c '^+[^+]' || true)
  DEL=$(diff -u "$BACKUP" "$TARGET" 2>/dev/null | grep -c '^-[^-]' || true)
  printf '  %swould revert:%s %s line(s) added, %s removed since the backup\n' \
    "$DIM" "$OFF" "$ADD" "$DEL"
  printf '\n'
  diff -u "$BACKUP" "$TARGET" 2>/dev/null | sed -n '3,23p' | sed 's/^/    /'
  [ "$((ADD + DEL))" -gt 20 ] && dim "    … truncated; full diff: diff -u \"$BACKUP\" \"$TARGET\""
fi

if [ "$YES" -eq 0 ]; then
  printf '\n'
  warn "preview only — nothing was changed. Add --yes to restore."
  exit "$EX_APPROVAL"
fi

# ── Restore ────────────────────────────────────────────────────────────────
# Keep a copy of the state being discarded. A rollback of a rollback is a real
# request, and losing the "after" makes it impossible.
UNDO_DIR="$DIR/05-backup"
mkdir -p "$UNDO_DIR"
UNDO="$UNDO_DIR/$(basename "$TARGET").pre-rollback.$(date +%Y%m%d-%H%M%S).bak"
cp -p "$TARGET" "$UNDO" 2>/dev/null || warn "could not save the pre-rollback state"

if [ "$FROM_GIT" -eq 1 ]; then
  git -C "$GIT_TOP" checkout -- "$TARGET" || die "git checkout failed"
else
  cp -p "$BACKUP" "$TARGET" || die "restore failed — $TARGET may be partially written.
    The backup is intact at $BACKUP; copy it by hand."
fi

state_set "$PROJECT" "$TASK_ID" 5 rolled-back "restored from $SOURCE_DESC"

printf '\n'
ok "restored $(basename "$TARGET") from $SOURCE_DESC"
dim "the discarded state was saved to $UNDO"
dim "phase 5 is marked rolled-back; re-run phase 4 to build a corrected plan"
