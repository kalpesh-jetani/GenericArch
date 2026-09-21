#!/usr/bin/env bash
#@kind      tool
#@platform  any
#@claude    call
#@purpose   Regenerate the inventories the active stack profile declares, offline; a no-op when no profile is declared, so /sync-app-notes reviews rows instead of running scans.
#@usage     sync-notes.sh [--check|--apply|--evidence] [--init-markers] [--only NOTE] [--src DIR]
#@in        --check:flag(compare, write nothing, exit 1 on drift) --apply:flag(rewrite managed rows) --evidence:flag(candidates for judgement notes) --init-markers:flag(place managed-row markers) --only:string(one note) --src:dir(source root)
#@out       stdout:status per mode; with no active profile, every mode reports and writes nothing
#@exit      0=in sync, applied, or no profile 1=drift (--check) or a generator failed 2=usage 3=no markers yet
#@effects   none until a stack profile declares a note set; then --apply writes only between the managed-row markers
#@when      regenerate the notes|notes are stale|sync notes offline|ci check the notes|without claude|candidate rows for review
#
# The inventories in .claude/notes/ are generated from the project's own code. WHICH notes exist and
# HOW each is scanned belongs to the active stack profile (profiles/<name>/): the file taxonomy of
# one stack means nothing to another. This is the neutral engine — it dispatches to a profile's
# declared generators and owns the managed-row markers, the offline/CI contract, and the
# mechanical/partial/judgement tiering. No profile ships by default, and the profile note-generator
# contract is still to be defined (docs/DECISIONS.md → Open), so with no profile it reports and
# writes nothing — never a half-built or guessed table.
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=Scripts/ga-lifecycle.sh
. "$HERE/ga-lifecycle.sh"
NOTES="$ROOT/.claude/notes"

MODE="report"
while [ $# -gt 0 ]; do
  case "$1" in
    --check)        MODE="check"; shift ;;
    --apply)        MODE="apply"; shift ;;
    --evidence)     MODE="evidence"; shift ;;
    --init-markers) shift ;;
    --only)         shift 2 || true ;;
    --src)          shift 2 || true ;;
    -h|--help)      sed -n '5,8p' "$0"; exit 2 ;;
    *)              printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[ -d "$NOTES" ] || { printf 'no .claude/notes/ here — nothing to sync\n' >&2; exit 2; }

PROFILE="$(ga_profile_active "$ROOT")"
BLD=$'\033[1m'; DIM=$'\033[2m'; OFF=$'\033[0m'; [ -t 1 ] || { BLD=''; DIM=''; OFF=''; }
printf '%s── Notes ──────────────────────────────────────────────%s\n\n' "$BLD" "$OFF"
if [ -z "$PROFILE" ]; then
  printf '  %sno stack profile declared%s — no note set to generate (mode: %s).\n' "$DIM" "$OFF" "$MODE"
else
  printf '  %sprofile %s declared, but its note generators are not wired yet%s (mode: %s).\n' "$DIM" "$PROFILE" "$OFF" "$MODE"
fi
printf '  A stack profile (profiles/<name>/) declares which inventories a project keeps and how each\n'
printf '  is scanned. See profiles/CLAUDE.md and docs/DECISIONS.md (Open). Nothing was written.\n'
exit 0
