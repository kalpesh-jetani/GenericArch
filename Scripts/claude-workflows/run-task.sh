#!/usr/bin/env bash
# Entry point for the CLAUDE.md task pipeline.
#
#   ./Scripts/claude-workflows/run-task.sh <project> <task-id> <action> [args…]
#   ./Scripts/claude-workflows/run-task.sh talentsure task-6-apis 5 --approve
#   ./Scripts/claude-workflows/run-task.sh list
#
# Actions
#   1…9          run one phase
#   parse find audit plan apply verify test present commit    the same, by name
#   all          phases 1→4, then 5 only with --approve, then 6→9
#   next         the first phase that has not completed
#   status       what has run, and what is next
#   rollback     undo phase 5 (claude-utils/rollback-claude.sh)
#   lint links   run those utils against the target
#   sync         trace the change into skills and docs
#   clean        delete this task's artifacts
#
# Phases
#   1 intake    2 locate   3 audit    4 plan     5 edit
#   6 verify    7 test     8 present  9 commit
#
# Arguments after the action are forwarded to the phase that accepts them, so
# `all --text "…" --edit "…" --approve` reaches phases 1, 4 and 5 respectively.
# In `all`, --type goes to phase 1 (intake) — pass it to 9 directly if you want to
# override the commit type.
#
# Phases 5 and 9 are the gated ones: 5 refuses to write without --approve, and 9
# never runs git at all. Both are deliberate (CLAUDE.md §2.11, docs/STRUCTURE.md).
. "$(dirname "$0")/../claude-utils/_common.sh"

usage_text() { sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; }

HERE="$(cd "$(dirname "$0")" && pwd)"
UTILS="$HERE/../claude-utils"

phase_title() {
  case "$1" in
    1) printf 'intake' ;;  2) printf 'locate' ;;  3) printf 'audit' ;;
    4) printf 'plan' ;;    5) printf 'edit' ;;    6) printf 'verify' ;;
    7) printf 'test' ;;    8) printf 'present' ;; 9) printf 'commit' ;;
  esac
}

phase_script() {
  case "$1" in
    1) printf '%s/01-parse-claude-task.sh' "$HERE" ;;
    2) printf '%s/02-find-claude-file.sh' "$HERE" ;;
    3) printf '%s/03-audit-claude-sections.sh' "$HERE" ;;
    4) printf '%s/04-plan-claude-edits.sh' "$HERE" ;;
    5) printf '%s/05-apply-claude-edits.sh' "$HERE" ;;
    6) printf '%s/06-verify-claude-syntax.sh' "$HERE" ;;
    7) printf '%s/07-test-claude-artifacts.sh' "$HERE" ;;
    8) printf '%s/08-present-claude-diff.sh' "$HERE" ;;
    9) printf '%s/09-commit-claude-changes.sh' "$HERE" ;;
  esac
}

# Action names → phase numbers, so the pipeline reads as words when you want it to.
normalize_action() {
  case "$1" in
    1|2|3|4|5|6|7|8|9) printf '%s' "$1" ;;
    parse|intake)      printf '1' ;;
    find|locate)       printf '2' ;;
    audit)             printf '3' ;;
    plan)              printf '4' ;;
    apply|edit)        printf '5' ;;
    verify)            printf '6' ;;
    test)              printf '7' ;;
    present|diff)      printf '8' ;;
    commit)            printf '9' ;;
    *)                 printf '%s' "$1" ;;
  esac
}

# ── Argument forwarding ────────────────────────────────────────────────────
takes_value() {
  case "$1" in
    --text|--file|--type|--target|--sections|--path|--edit|--from|--max-line|--scope) return 0 ;;
  esac
  return 1
}

accepts() {
  case "$1:$2" in
    1:--text|1:--file|1:--type|1:--target|1:--sections|1:-)  return 0 ;;
    2:--path|2:--allow-missing)                              return 0 ;;
    3:--verbose|3:-v)                                        return 0 ;;
    4:--edit|4:--from|4:--template)                          return 0 ;;
    5:--approve|5:--force)                                   return 0 ;;
    6:--fix|6:--max-line)                                    return 0 ;;
    7:--verbose|7:-v)                                        return 0 ;;
    8:--full|8:--stage)                                      return 0 ;;
    9:--scope|9:--no-coauthor)                               return 0 ;;
  esac
  return 1
}

# filter_args <phase> <args…> — the subset this phase understands, %q-quoted.
filter_args() {
  _ph="$1"; shift
  _out=''
  while [ $# -gt 0 ]; do
    if takes_value "$1"; then
      if accepts "$_ph" "$1"; then
        _out="$_out $(printf '%q' "$1") $(printf '%q' "${2:-}")"
      fi
      shift 2 2>/dev/null || shift
    else
      accepts "$_ph" "$1" && _out="$_out $(printf '%q' "$1")"
      shift
    fi
  done
  printf '%s' "$_out"
}

has_flag() {
  _want="$1"; shift
  for a in "$@"; do [ "$a" = "$_want" ] && return 0; done
  return 1
}

run_phase() {
  _ph="$1"; shift
  _script="$(phase_script "$_ph")"
  [ -x "$_script" ] || [ -r "$_script" ] || die "missing phase script: $_script" "$EX_PRECOND"
  _args="$(filter_args "$_ph" "$@")"
  eval bash "$(printf '%q' "$_script")" "$(printf '%q' "$PROJECT")" "$(printf '%q' "$TASK_ID")" "$_args"
}

# ── list: no project needed ────────────────────────────────────────────────
case "${1:-}" in
  list|--list)
    bash "$UTILS/init-claude-env.sh" --list
    exit $? ;;
  -h|--help|'') usage "$EX_OK" ;;
esac

[ $# -ge 3 ] || usage

PROJECT="$1"; TASK_ID="$2"; ACTION="$(normalize_action "$3")"; shift 3
check_id "$PROJECT" "project name"; check_id "$TASK_ID" "task id"

DIR="$(task_dir "$PROJECT" "$TASK_ID")"

# ── status ─────────────────────────────────────────────────────────────────
if [ "$ACTION" = status ]; then
  hdr "$PROJECT / $TASK_ID"
  SF="$(state_file "$PROJECT" "$TASK_ID")"
  if [ ! -f "$SF" ]; then
    dim "nothing has run yet"
    printf '\n  start with:\n    %s %s %s 1 --text "<the request>"\n' \
      "./Scripts/claude-workflows/run-task.sh" "$PROJECT" "$TASK_ID"
    exit "$EX_OK"
  fi
  printf '\n'
  n=1
  while [ "$n" -le 9 ]; do
    st="$(state_get "$PROJECT" "$TASK_ID" "$n")"
    note=$(awk -F'\t' -v p="$n" '$1==p {print $4}' "$SF" | tail -1)
    case "$st" in
      done|emitted) mark="${GRN}✓${OFF}" ;;
      failed|blocked) mark="${RED}✗${OFF}" ;;
      rolled-back|template) mark="${YEL}↺${OFF}" ;;
      '') mark="${DIM}·${OFF}"; st="—" ;;
      *) mark="${YEL}?${OFF}" ;;
    esac
    printf '  %b %d %-9s %-12s %s%s%s\n' "$mark" "$n" "$(phase_title "$n")" "$st" "$DIM" "$note" "$OFF"
    n=$((n + 1))
  done
  printf '\n'
  NEXT=''
  n=1
  while [ "$n" -le 9 ]; do
    case "$(state_get "$PROJECT" "$TASK_ID" "$n")" in
      done|emitted) ;;
      *) NEXT="$n"; break ;;
    esac
    n=$((n + 1))
  done
  if [ -n "$NEXT" ]; then
    dim "next: run-task.sh $PROJECT $TASK_ID $NEXT   ($(phase_title "$NEXT"))"
  else
    ok "all nine phases have run"
    dim "artifacts: $DIR"
  fi
  exit "$EX_OK"
fi

# ── utils ──────────────────────────────────────────────────────────────────
case "$ACTION" in
  rollback) exec bash "$UTILS/rollback-claude.sh" "$PROJECT" "$TASK_ID" "$@" ;;
  sync)     exec bash "$UTILS/sync-claude-skill.sh" "$PROJECT" "$TASK_ID" "$@" ;;
  lint|links)
    FE="$DIR/02-file.env"
    [ -f "$FE" ] || die "run phase 2 first — the target is not resolved yet" "$EX_PRECOND"
    T="$(kv_get "$FE" TARGET)"
    if [ "$ACTION" = lint ]; then
      exec bash "$UTILS/claude-lint.sh" "$T" "$@"
    else
      exec bash "$UTILS/validate-claude-links.sh" "$T" "$@"
    fi ;;
  clean)
    [ -d "$DIR" ] || die "no such task: $PROJECT/$TASK_ID" "$EX_USAGE"
    if ! has_flag --yes "$@"; then
      hdr "would delete"
      info "$DIR"
      du -sh "$DIR" 2>/dev/null | awk '{print "  " $1}'
      # A backup is the only thing here that cannot be regenerated.
      if [ -d "$DIR/05-backup" ]; then
        printf '\n'
        warn "this task has phase-5 backups — deleting them removes the only non-git
    record of the document before the edit:"
        ls -1 "$DIR/05-backup" 2>/dev/null | sed 's/^/      /'
      fi
      printf '\n'
      dim "add --yes to delete"
      exit "$EX_APPROVAL"
    fi
    rm -rf "$DIR" || die "could not delete $DIR"
    ok "deleted $DIR"
    exit "$EX_OK" ;;
esac

# ── next ───────────────────────────────────────────────────────────────────
if [ "$ACTION" = next ]; then
  n=1
  while [ "$n" -le 9 ]; do
    case "$(state_get "$PROJECT" "$TASK_ID" "$n")" in
      done|emitted) ;;
      *) ACTION="$n"; break ;;
    esac
    n=$((n + 1))
  done
  if [ "$ACTION" = next ]; then
    ok "all nine phases have already run — nothing to do"
    exit "$EX_OK"
  fi
  dim "next unfinished phase is $ACTION ($(phase_title "$ACTION"))"
fi

# ── all ────────────────────────────────────────────────────────────────────
if [ "$ACTION" = all ]; then
  APPROVED=0
  has_flag --approve "$@" && APPROVED=1

  for n in 1 2 3 4; do
    run_phase "$n" "$@" || die "phase $n ($(phase_title "$n")) failed — stopping.
    Fix it, then continue with: run-task.sh $PROJECT $TASK_ID $n" "$?"
  done

  if [ "$APPROVED" -eq 0 ]; then
    printf '\n'
    hdr "stopping before phase 5"
    info "Phases 1-4 are complete. Phase 5 writes to the document, so it needs approval."
    printf '\n'
    [ -f "$DIR/04-outline.md" ] && dim "read the outline: $DIR/04-outline.md"
    dim "then:  run-task.sh $PROJECT $TASK_ID all --approve"
    dim "or:    run-task.sh $PROJECT $TASK_ID 5 --approve"
    exit "$EX_APPROVAL"
  fi

  for n in 5 6 7 8 9; do
    # Verify findings are worth stopping for; a lint warning is not, and phase 6
    # already separates the two by exit code.
    if ! run_phase "$n" "$@"; then
      rc=$?
      die "phase $n ($(phase_title "$n")) failed — stopping.
    Continue with: run-task.sh $PROJECT $TASK_ID $n
    Undo phase 5:  run-task.sh $PROJECT $TASK_ID rollback" "$rc"
    fi
  done

  printf '\n'
  ok "all nine phases complete"
  dim "nothing was committed and nothing was compiled — see phases 9 and 7."
  exit "$EX_OK"
fi

# ── a single phase ─────────────────────────────────────────────────────────
case "$ACTION" in
  1|2|3|4|5|6|7|8|9) ;;
  *) die "unknown action: $ACTION
    Try: 1…9, all, next, status, rollback, lint, links, sync, clean, list" "$EX_USAGE" ;;
esac

run_phase "$ACTION" "$@"
