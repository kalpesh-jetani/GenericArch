#!/usr/bin/env bash
# Install GenericArch into the repo you are standing in.
#
#   Recommended — read it before you run it:
#     curl -fsSLO https://raw.githubusercontent.com/kalpesh-jetani/GenericArch/v0.1.0/install.sh
#     less install.sh && bash install.sh --apply
#
#   One-liner, if you already trust the source:
#     curl -fsSL https://raw.githubusercontent.com/kalpesh-jetani/GenericArch/v0.1.0/install.sh | bash -s -- --apply
#
# Dry run unless --apply is given. Nothing is ever overwritten.
#
# Overrides:
#   GA_REPO=<git url|path>   where to fetch from   (default: the kalpesh-jetani/GenericArch remote)
#   GA_REF=<tag|branch>      which version to pin  (default: v0.1.0 — pin, don't track main)
#
# This script only FETCHES and DELEGATES. The list of what travels and what must not lives in
# Scripts/adopt.sh, in one place — duplicating it here is how the two would disagree.
set -o pipefail

GA_REPO="${GA_REPO:-https://github.com/kalpesh-jetani/GenericArch.git}"
GA_REF="${GA_REF:-v0.1.0}"
APPLY=0
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;;
    --help|-h) sed -n '2,20p' "$0" 2>/dev/null || echo "see the header of install.sh"; exit 0 ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done

RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; DIM=$'\033[2m'; BLD=$'\033[1m'; OFF=$'\033[0m'
TARGET="$(pwd)"

command -v git >/dev/null 2>&1 || { echo "${RED}git is required${OFF}"; exit 1; }

# Refuse to install into the base itself — the usual copy/paste accident.
if [ -f "$TARGET/CLAUDE.md" ] && grep -q "Generic Apple Platform App Architecture" "$TARGET/CLAUDE.md" 2>/dev/null; then
  echo "${RED}this looks like the GenericArch base itself — nothing to install${OFF}"; exit 1
fi

echo
echo "${BLD}GenericArch installer${OFF}"
echo "  into    $TARGET"
echo "  from    $GA_REPO"
echo "  version ${BLD}$GA_REF${OFF}"
[ "$APPLY" -eq 1 ] && echo "  mode    ${GRN}APPLY${OFF}" || echo "  mode    ${YEL}dry run${OFF} (add --apply to write)"
echo

[ -d "$TARGET/.git" ] || echo "${YEL}⚠ not a git repository — you won't be able to review or revert this${OFF}"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "${DIM}fetching $GA_REF…${OFF}"
if ! git clone --quiet --depth 1 --branch "$GA_REF" "$GA_REPO" "$TMP/base" 2>/dev/null; then
  # A branch/tag that doesn't exist, or a local path clone — retry without --branch.
  if ! git clone --quiet --depth 1 "$GA_REPO" "$TMP/base" 2>/dev/null; then
    echo "${RED}could not fetch $GA_REPO${OFF}"
    echo "  ${DIM}set GA_REPO to a reachable URL or a local checkout path${OFF}"
    exit 1
  fi
  echo "${YEL}⚠ ref '$GA_REF' not found — installed from the default branch instead${OFF}"
  echo "  ${DIM}Pin a tag for anything you intend to reproduce.${OFF}"
fi
VER=$(git -C "$TMP/base" describe --tags --always 2>/dev/null || echo unknown)
echo "${DIM}fetched $VER${OFF}"
echo

[ -x "$TMP/base/Scripts/adopt.sh" ] || chmod +x "$TMP/base/Scripts/adopt.sh" 2>/dev/null
[ -f "$TMP/base/Scripts/adopt.sh" ] || { echo "${RED}the fetched base has no Scripts/adopt.sh${OFF}"; exit 1; }

# Fresh vs existing changes only the advice at the end — adopt.sh is non-destructive either way.
MODE="existing"
if [ -z "$(find "$TARGET" -name '*.swift' -not -path '*/.git/*' -print -quit 2>/dev/null)" ] \
   && [ ! -f "$TARGET/CLAUDE.md" ]; then
  MODE="fresh"
fi
echo "${DIM}target looks like a ${MODE} project${OFF}"

if [ "$APPLY" -eq 1 ]; then
  "$TMP/base/Scripts/adopt.sh" "$TARGET" --apply --quiet-next
else
  "$TMP/base/Scripts/adopt.sh" "$TARGET"
fi
rc=$?
[ "$rc" -ne 0 ] && exit "$rc"
[ "$APPLY" -eq 0 ] && exit 0

# Record what was installed, so an upgrade knows where it started.
cat > "$TARGET/.genericarch-version" <<META
$VER
repo=$GA_REPO
ref=$GA_REF
META

echo
echo "${BLD}Installed $VER${OFF} ${DIM}(recorded in .genericarch-version)${OFF}"
echo
if [ "$MODE" = fresh ]; then
  cat <<NEXT
${BLD}Next — fresh project${OFF}
  1. ${BLD}/project-init <ProductName>${OFF}
       Asks for bundle ID, Team ID, v1 languages, permissions per group, and which of the
       rules you want as hard vs base. Writes CLAUDE.md only with your approval.
  2. ${BLD}./Scripts/detect-toolchain.sh${OFF}
       Your machine defines the baseline — no project file exists yet.
NEXT
else
  cat <<NEXT
${BLD}Next — existing project${OFF}
  1. ${BLD}/project-init${OFF}
       Reads your CLAUDE.md in full, builds the rule-conflict table, and asks per conflict.
       Your rules win by default; nothing is overwritten without an explicit yes.
  2. ${BLD}/gaps${OFF}
       Derives each gap's status from your code instead of asking.
  3. ${BLD}./Scripts/detect-toolchain.sh && ./Scripts/check.sh${OFF}
       Expect check.sh failures — that is the point. Triage them in /project-init as
       "keep theirs", "new code only", or "migrate".
NEXT
fi
echo
echo "${DIM}No CLAUDE.md was written. Your rules stay yours until you decide otherwise.${OFF}"
