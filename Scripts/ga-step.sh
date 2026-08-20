#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Gate and record the lifecycle steps so commands run in order: install → project-init → gaps → sync-app-notes → ready.
#@usage     ga-step.sh show|next|require <step>|after <step>|record <step> [note]|reset
#@in        step:enum(install project-init gaps sync-app-notes ready) --target:dir(default: the repo above Scripts/) --force:flag(operator override, never Claude)
#@out       stdout:for show, the ledger and what is next; for require, ok or the unmet prerequisites
#@exit      0=clear to proceed 2=usage 5=out of order, nothing written
#@effects   record appends one row to .genericarch/STEPS.tsv; show/next/require are read-only
#@when      can I run this command yet|what runs next|which step am I on|command order|out of order|step ledger
#
# Why this exists: every command in .claude/commands assumes a repo state an earlier command was
# supposed to leave behind. /gaps before /project-init triages items nobody has decided.
# /sync-app-notes before either writes nine inventories off a tree nobody surveyed. The order was
# documented and unenforced, so it was not followed — and the recovery cost more than the work.
#
# The gate is advisory to the OPERATOR and binding on CLAUDE: --force exists for a human who knows
# why they are skipping a step, and a command file must never pass it.
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/ga-lifecycle.sh
. "$HERE/ga-lifecycle.sh"

TARGET="$(cd "$HERE/.." && pwd)"
FORCE=0
ACTION="${1:-show}"
[ $# -gt 0 ] && shift

STEP=""
NOTE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$(cd "$2" 2>/dev/null && pwd)" || ga_die "no such directory: $2" "$GA_EX_USAGE"; shift 2 ;;
    --force)  FORCE=1; shift ;;
    *)        if [ -z "$STEP" ]; then STEP="$1"; else NOTE="${NOTE:+$NOTE }$1"; fi; shift ;;
  esac
done

usage() {
  cat >&2 <<USAGE
usage: ga-step.sh show
       ga-step.sh next
       ga-step.sh require <step> [--force]   # every step BEFORE <step> has run
       ga-step.sh after   <step> [--force]   # <step> itself has run
       ga-step.sh record  <step> [note]
       ga-step.sh reset            # clears the ledger; the install step is re-derived

steps, in order: $GA_STEPS
USAGE
  exit "$GA_EX_USAGE"
}

# The install step is not recorded by a command — the manifest IS the record. Deriving it here
# keeps a repo installed before this script existed from looking like it never ran install.
derive_install() {
  # The source repo is never "installed" into itself — .claude-plugin is excluded from every adopt,
  # so its presence is the one reliable marker. Without this, every command is blocked in the repo
  # that authors them.
  if [ -d "$TARGET/.claude-plugin" ] && [ -f "$TARGET/Scripts/adopt.sh" ]; then
    ga_step_record "$TARGET" install "GenericArch source repo — nothing to install"
    return 0
  fi
  for _m in $(ga_manifest_find "$TARGET"); do
    [ -n "$_m" ] && { ga_step_record "$TARGET" install "derived from ${_m#"$TARGET"/}"; return 0; }
  done
  return 1
}

case "$ACTION" in
  show)
    derive_install || true
    LEDGER="$(ga_step_path "$TARGET")"
    ga_hdr "── GenericArch steps ──────────────────────────────────"
    for s in $GA_STEPS; do
      if ga_step_done "$TARGET" "$s"; then
        printf '  %s✓%s %-16s %s\n' "$GA_GRN" "$GA_OFF" "$s" \
          "$(awk -F'\t' -v k="$s" '$1==k {print $2 "  " $3; exit}' "$LEDGER" 2>/dev/null)"
      else
        printf '  %s·%s %-16s %spending%s\n' "$GA_DIM" "$GA_OFF" "$s" "$GA_DIM" "$GA_OFF"
      fi
    done
    echo
    printf '  next: %s%s%s\n' "$GA_BLD" "$(ga_step_next "$TARGET")" "$GA_OFF"
    TF="$(ga_tombstone_path "$TARGET")"
    if [ -f "$TF" ]; then
      n=$(awk -F'\t' '$1!~/^#/' "$TF" | grep -c . || true)
      [ "$n" -gt 0 ] && printf '  declined: %s path(s) — %s\n' "$n" "${TF#"$TARGET"/}"
    fi
    ;;

  next)
    derive_install || true
    ga_step_next "$TARGET"; echo
    ;;

  after)
    # "this step must have run", as opposed to require's "everything before this step has run".
    # Work commands need one specific predecessor, not the whole chain.
    [ -n "$STEP" ] || usage
    ga_step_pos "$STEP" >/dev/null || ga_die "unknown step: $STEP (want one of: $GA_STEPS)" "$GA_EX_USAGE"
    derive_install || true
    if ga_step_done "$TARGET" "$STEP"; then
      ga_ok "$STEP has run"
      exit "$GA_EX_OK"
    fi
    if [ "$FORCE" -eq 1 ]; then
      ga_warn "$STEP has not run — --force was given"
      exit "$GA_EX_OK"
    fi
    printf '%s✗%s this needs %s%s%s to have run first, and it has not.%s\n' \
      "$GA_RED" "$GA_OFF" "$GA_BLD" "$STEP" "$GA_OFF" '' >&2
    printf '  next in the sequence: %s   (./Scripts/ga-step.sh show)\n' "$(ga_step_next "$TARGET")" >&2
    exit "$GA_EX_SEQ"
    ;;

  require)
    [ -n "$STEP" ] || usage
    ga_step_pos "$STEP" >/dev/null || ga_die "unknown step: $STEP (want one of: $GA_STEPS)" "$GA_EX_USAGE"
    derive_install || true
    MISSING="$(ga_step_missing "$TARGET" "$STEP")"
    if [ -z "$MISSING" ]; then
      ga_ok "$STEP: prerequisites met"
      exit "$GA_EX_OK"
    fi
    if [ "$FORCE" -eq 1 ]; then
      ga_warn "$STEP: running with unmet prerequisites ($MISSING) — --force was given"
      exit "$GA_EX_OK"
    fi
    printf '%s✗%s %s cannot run yet — these have not run:%s %s%s\n' \
      "$GA_RED" "$GA_OFF" "$STEP" "$GA_BLD" "$MISSING" "$GA_OFF" >&2
    printf '  run them in this order, then retry: %s\n' "$MISSING" >&2
    printf '  %sIf the step genuinely does not apply here, the operator records it as skipped:%s\n' "$GA_DIM" "$GA_OFF" >&2
    printf '    ./Scripts/ga-step.sh record %s "not applicable: <why>"\n' "${MISSING%% *}" >&2
    exit "$GA_EX_SEQ"
    ;;

  record)
    [ -n "$STEP" ] || usage
    ga_step_pos "$STEP" >/dev/null || ga_die "unknown step: $STEP (want one of: $GA_STEPS)" "$GA_EX_USAGE"
    derive_install || true
    MISSING="$(ga_step_missing "$TARGET" "$STEP")"
    if [ -n "$MISSING" ] && [ "$FORCE" -eq 0 ]; then
      ga_die "cannot record $STEP — $MISSING have not run. Record those first, or pass --force." "$GA_EX_SEQ"
    fi
    ga_step_record "$TARGET" "$STEP" "$NOTE"
    ga_ok "recorded: $STEP${NOTE:+ — $NOTE}"
    printf '  next: %s\n' "$(ga_step_next "$TARGET")"
    ;;

  reset)
    LEDGER="$(ga_step_path "$TARGET")"
    [ -f "$LEDGER" ] || { ga_info "no ledger to reset"; exit "$GA_EX_OK"; }
    ga_confirm "Clear the step ledger at ${LEDGER#"$TARGET"/}?" || exit "$GA_EX_ABORT"
    rm -f "$LEDGER"
    derive_install || true
    ga_ok "ledger cleared; next: $(ga_step_next "$TARGET")"
    ;;

  *) usage ;;
esac
