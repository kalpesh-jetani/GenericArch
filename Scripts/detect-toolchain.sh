#!/usr/bin/env bash
#@kind      tool
#@platform  any
#@claude    call
#@purpose   Report the stack the active profile declares, and (once a profile wires it) reconcile it against the machine. Never quote stack values from memory.
#@usage     detect-toolchain.sh [--markdown|--options|--mismatches] [--root DIR]
#@in        --markdown:flag(emit PROJECT.md rows from the profile) --options:flag(choice lists for /project-init) --mismatches:flag(SEVERITY|id|what|current|available|remediation rows) --root:dir(repo whose profile answers; default this checkout)
#@out       stdout:the declared stack, or a no-profile notice
#@exit      0=ok — always; callers gate on BLOCKING rows, never on status
#@effects   read-only
#@when      what is the stack|which toolchain|min version|resolved stack|declared stack
# The stack is DECLARED by the active stack profile (profiles/<name>/), not detected from a fixed
# toolchain. This reads what the profile declares. Machine reconciliation — SDK/version mismatches —
# is per-stack and belongs to the profile's own probe, which no shipped profile defines yet
# (docs/DECISIONS.md → Open). So with no profile, or a profile that wires no probe, it reports what
# it can and emits no mismatches. It never invents a value the profile did not state.
set -o pipefail

BLD=$'\033[1m'; DIM=$'\033[2m'; GRN=$'\033[32m'; OFF=$'\033[0m'; [ -t 1 ] || { BLD=''; DIM=''; GRN=''; OFF=''; }
MODE=report; ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --markdown)   MODE=markdown; shift ;;
    --options)    MODE=options; shift ;;
    --mismatches) MODE=mismatches; shift ;;
    --root)       ROOT="${2:-}"; shift 2 || true ;;
    *)            shift ;;
  esac
done
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -n "$ROOT" ]; then
  [ -d "$ROOT" ] || { echo "no such directory: $ROOT" >&2; exit 2; }
else
  ROOT="$(cd "$HERE/.." && pwd)"
fi
# shellcheck source=Scripts/ga-lifecycle.sh
. "$HERE/ga-lifecycle.sh"
PROFILE="$(ga_profile_active "$ROOT")"
KEYS="platform languages build_system ui concurrency testing"
pget() { ga_profile_get "$ROOT" "$1" 2>/dev/null; }

case "$MODE" in
  options)
    if [ -z "$PROFILE" ]; then
      echo "# No stack profile declared — /declare-profile records one. Nothing to offer."
    else
      echo "# Declared by profile '$PROFILE'. A profile may also offer machine-derived choices; none is wired yet."
      for k in $KEYS; do v="$(pget "$k")"; [ -n "$v" ] && printf '%s: %s\n' "$k" "$v"; done
    fi
    exit 0 ;;

  mismatches)
    # Machine reconciliation is the profile's own probe, and none is wired yet. No rows means nothing
    # is blocking — callers grep for BLOCKING and correctly find none.
    exit 0 ;;

  markdown)
    echo "| Item | Value | Source |"
    echo "|---|---|---|"
    if [ -z "$PROFILE" ]; then
      echo "| Stack profile | **none declared** | run /declare-profile |"
    else
      echo "| Stack profile | **$PROFILE** | profiles/$PROFILE |"
      for k in $KEYS; do v="$(pget "$k")"; [ -n "$v" ] && printf '| %s | **%s** | profile |\n' "$k" "$v"; done
    fi
    exit 0 ;;

  *)
    echo
    echo "${BLD}Stack — declared by the active profile${OFF}"
    echo
    if [ -z "$PROFILE" ]; then
      echo "  ${DIM}no stack profile declared${OFF} — /declare-profile records the stack, and"
      echo "  profiles/<name>/ optionally adds templates. Nothing to detect until then."
    else
      printf '  %-16s %s\n' "profile" "$PROFILE"
      for k in $KEYS; do v="$(pget "$k")"; [ -n "$v" ] && printf '  %-16s %s\n' "$k" "$v"; done
      echo
      echo "  ${DIM}Machine reconciliation is the profile's own probe; none is wired yet.${OFF}"
    fi
    echo
    exit 0 ;;
esac
