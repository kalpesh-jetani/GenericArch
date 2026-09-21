#!/usr/bin/env bash
#@kind      tool
#@platform  any
#@claude    call
#@purpose   Run the active stack profile's checks (lint/build/rules), plus the profile-agnostic OpenSpec-projection staleness gate. No profile → only the agnostic checks run.
#@usage     check.sh
#@in        none
#@out       stdout:pass/fail report
#@exit      0=clean 1=violations
#@effects   read-only, plus whatever the profile's check command does (which may compile — CLAUDE.md §2.8: validating is fine, running/testing needs consent)
# The stack-specific rules — how a feature is structured, the language's lint, the build floor — are
# the active profile's, run through the command it declares (check_cmd). This is the neutral runner:
# it runs the one check that holds on any repo (that the OpenSpec projection is current), then
# dispatches to the profile. With no profile declared there is nothing stack-specific to check.
set -o pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
# shellcheck source=Scripts/ga-lifecycle.sh
. "$HERE/ga-lifecycle.sh"
RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; DIM=$'\033[2m'; OFF=$'\033[0m'; [ -t 1 ] || { RED=''; YEL=''; GRN=''; DIM=''; OFF=''; }
fails=0; warns=0

# ── OpenSpec projection (profile-agnostic) ──────────────────────────────────
# Built from CLAUDE.md and docs/DECISIONS.md, so it can drift in any repo whatever its stack. A
# warning, never a failure: a stale projection is a one-command fix with no business blocking an
# unrelated change. Exit 7 means this repo has no OpenSpec config, which is not a finding.
if [ -x Scripts/openspec-sync.sh ]; then
  Scripts/openspec-sync.sh --check --tsv >/dev/null 2>&1
  case $? in
    0|7) : ;;
    *)   printf '%s⚠ the OpenSpec projection is stale%s\n' "$YEL" "$OFF"
         printf '  %srun /openspec-install (or ./Scripts/openspec-sync.sh --check to see the drift)%s\n' "$DIM" "$OFF"
         warns=$((warns + 1)) ;;
  esac
fi

# ── The active profile's checks ─────────────────────────────────────────────
# A profile declares its own validation as `check_cmd` (a lint/build line — validation, never a test
# run: CLAUDE.md §2.8). The stack rules a linter cannot express live in that command too, because
# they are the profile's, not the layer's.
PROFILE="$(ga_profile_active .)"
CHECK_CMD="$(ga_profile_get . check_cmd 2>/dev/null || true)"
echo "── Stack checks ───────────────────────────────────────────"
if [ -z "$PROFILE" ]; then
  printf '  %sno stack profile declared — no stack-specific checks to run%s\n' "$DIM" "$OFF"
elif [ -z "$CHECK_CMD" ]; then
  printf '  %sprofile %s declares no check command (check_cmd) yet%s\n' "$DIM" "$PROFILE" "$OFF"
else
  printf '  %srunning profile check: %s%s\n' "$DIM" "$CHECK_CMD" "$OFF"
  sh -c "$CHECK_CMD" || fails=$((fails + 1))
fi

echo "───────────────────────────────────────────────────────────"
if [ "$fails" -gt 0 ]; then
  printf '%s%d check(s) failed%s, %d warning(s)\n' "$RED" "$fails" "$OFF" "$warns"; exit 1
fi
printf '%sall checks pass%s, %d warning(s)\n' "$GRN" "$OFF" "$warns"
exit 0
