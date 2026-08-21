#!/usr/bin/env bash
# Fetch GenericArch from GitHub, then hand over to its install.sh.
#
#   Recommended — read it before you run it:
#     curl -fsSLO https://raw.githubusercontent.com/kalpesh-jetani/GenericArch/HEAD/bootstrap.sh
#     less bootstrap.sh && bash bootstrap.sh --apply
#
#   One-liner, if you already trust the source:
#     curl -fsSL https://raw.githubusercontent.com/kalpesh-jetani/GenericArch/HEAD/bootstrap.sh | bash -s -- --apply
#
# Dry run unless --apply is given.
#
# Overrides:
#   GA_REPO=<git url|path>   where to fetch from   (default: the kalpesh-jetani/GenericArch remote)
#   GA_REF=<tag|branch>      which version to pin  (default: the newest semver tag on the remote)
#   --ref <tag>              same, as a flag — usable through `curl ... | bash -s -- --ref <tag>`
#   --yes                    passed through to install.sh, skipping its confirmation prompt
#   --root-ok · --force · --with-architecture · --project-setup · --no-project-setup ·
#   --no-preflight            install.sh's own flags, forwarded verbatim
#
# This is the ONLY script in the lifecycle that touches the network, and all it does is fetch.
# Every decision about what lands in your repo — the compatibility gate, the plan, the manifest,
# the rollback — belongs to install.sh, which runs offline against the clone this leaves behind.
set -o pipefail

RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; DIM=$'\033[2m'; BLD=$'\033[1m'; OFF=$'\033[0m'

GA_REPO="${GA_REPO:-https://github.com/kalpesh-jetani/GenericArch.git}"
GA_REF="${GA_REF:-}"
RESOLVED_LATEST=0
APPLY=0
PASS_THROUGH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --yes|-y) PASS_THROUGH="$PASS_THROUGH --yes"; shift ;;
    --ref)   GA_REF="$2"; shift 2 || { echo "--ref needs a tag" >&2; exit 2; } ;;
    --help|-h) sed -n '2,24p' "$0" 2>/dev/null || echo "see the header of bootstrap.sh"; exit 0 ;;
    # install.sh's own flags, forwarded verbatim. Rejecting them made its advice unreachable: its
    # multi-root refusal says "re-run with --root-ok", and through here that was an unknown argument.
    --root-ok|--with-architecture|--project-setup|--no-project-setup|--no-preflight|--force|-f)
             PASS_THROUGH="$PASS_THROUGH $1"; shift ;;
    # A trailing `# comment` pasted from the README arrives as arguments in zsh, whose
    # interactive_comments is off by default. Say that, rather than reporting `#` as a typo.
    '#') echo "${YEL}⚠${OFF} a '#' comment reached this script as an argument — your shell did not" >&2
         echo "  strip it (zsh does not, by default). Paste the command without its trailing" >&2
         echo "  comment, or run:  setopt interactive_comments" >&2
         exit 2 ;;
    *) echo "unknown argument: $1" >&2
       echo "  bootstrap flags: --apply --yes --ref <tag> --help" >&2
       echo "  forwarded to install.sh: --root-ok --with-architecture --project-setup" >&2
       echo "                           --no-project-setup --no-preflight --force" >&2
       exit 2 ;;
  esac
done

# Refuse before the fetch, not after. bootstrap.sh cannot source Scripts/ga-lifecycle.sh — it is
# what clones the repo that holds it — so the platform gate is repeated inline here, with the same
# code (78) and the same reasoning: everything downstream assumes shasum, xcrun and BSD sed/awk.
# Checking here means a Linux or WSL machine never clones a tree it cannot use. --help is handled
# above, so reading the header still works anywhere.
GA_OS="$(uname -s 2>/dev/null || echo unknown)"
if [ "$GA_OS" != Darwin ]; then
  printf '%s✗ GenericArch is macOS-only (found: %s).%s\n' "$RED" "$GA_OS" "$OFF" >&2
  printf '  It installs Apple-platform rules and scripts that assume shasum, xcrun and BSD\n' >&2
  printf '  sed/awk. Nothing was fetched and nothing was written.\n' >&2
  exit 78
fi

# A piped script cannot see the URL it was fetched from, so a hardcoded default silently
# installs the wrong version. Resolve the newest semver tag from the remote instead, and let
# --ref override. Tag names are matched with an optional leading `v` because this repo has both.
semver_tags() {
  git ls-remote --tags --refs "$GA_REPO" 2>/dev/null \
    | awk -F'refs/tags/' 'NF>1 {print $2}' \
    | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' \
    | awk '{o=$0; v=$0; sub(/^v/,"",v); print v"\t"o}' \
    | sort -t. -k1,1n -k2,2n -k3,3n
}

# `0.2.0` and `v0.2.0` are the SAME version under two names, and nothing stops them pointing at
# different commits — in this repo they do. A collision is reported and the choice named rather
# than left to whichever way `sort` happened to break the tie.
resolve_latest_ref() {
  local tags newest dupes
  tags="$(semver_tags)"
  [ -n "$tags" ] || return 0
  newest="$(printf '%s\n' "$tags" | tail -1 | cut -f1)"
  dupes="$(printf '%s\n' "$tags" | awk -F'\t' -v n="$newest" '$1==n {print $2}')"
  if [ "$(printf '%s\n' "$dupes" | grep -c .)" -gt 1 ]; then
    echo "${YEL}two tags both claim version $newest and may point at different commits:${OFF}" >&2
    printf '%s\n' "$dupes" | sed "s|^|    |" >&2
    echo "  ${DIM}picking the last by name; pass --ref <tag> to choose, or delete the duplicate tag${OFF}" >&2
  fi
  printf '%s\n' "$dupes" | tail -1
}

if [ -z "$GA_REF" ]; then
  GA_REF="$(resolve_latest_ref)"
  if [ -n "$GA_REF" ]; then
    RESOLVED_LATEST=1
  else
    echo "${YEL}could not list tags on $GA_REPO — falling back to the default branch${OFF}" >&2
    echo "  ${DIM}pass --ref <tag> to pin a version you can reproduce${OFF}" >&2
    GA_REF="HEAD"
  fi
fi

TARGET="$(pwd)"

command -v git >/dev/null 2>&1 || { echo "${RED}git is required${OFF}"; exit 1; }

# Refuse to install into the base itself — the usual copy/paste accident.
if [ -f "$TARGET/CLAUDE.md" ] && grep -q "Generic Apple Platform App Architecture" "$TARGET/CLAUDE.md" 2>/dev/null; then
  echo "${RED}this looks like the GenericArch base itself — nothing to install${OFF}"; exit 1
fi

echo
echo "${BLD}GenericArch bootstrap${OFF}"
echo "  into    $TARGET"
echo "  from    $GA_REPO"
if [ "$RESOLVED_LATEST" -eq 1 ]; then
  echo "  version ${BLD}$GA_REF${OFF} ${DIM}(newest tag on the remote; pass --ref to pin another)${OFF}"
else
  echo "  version ${BLD}$GA_REF${OFF} ${DIM}(pinned)${OFF}"
fi
[ "$APPLY" -eq 1 ] && echo "  mode    ${GRN}APPLY${OFF}" || echo "  mode    ${YEL}dry run${OFF} (add --apply to write)"
echo

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "${DIM}fetching $GA_REF...${OFF}"
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

[ -f "$TMP/base/install.sh" ] || { echo "${RED}the fetched base has no install.sh${OFF}"; exit 1; }
chmod +x "$TMP/base/install.sh" 2>/dev/null || true

# --depth 1 --branch <tag> leaves a shallow clone whose only tag is the one asked for, so
# install.sh's own `git describe --exact-match` resolves the release name without another fetch.
# Where it cannot (a branch clone), pass the ref through so the manifest is still named after a
# version rather than a commit.
case "$GA_REF" in
  v[0-9]*|[0-9]*) export GA_VERSION="$GA_REF" ;;
esac

# Everything from here is offline and belongs to install.sh: the gate, the plan, the confirmation,
# the manifest, the rollback. Duplicating any of it here is how the two would disagree.
# install.sh's remediation advice names a command to run. Reached from here, `./install.sh` is not
# one the caller has — the clone this used is a temp dir that is about to go away — so tell it which
# entry point to name.
export GA_VIA_BOOTSTRAP=1
# PASS_THROUGH goes to BOTH branches. Dropping it on the dry run meant `bootstrap.sh --root-ok`
# without --apply was refused for the very reason --root-ok exists to allow, and the plan the
# operator was trying to read never printed.
# shellcheck disable=SC2086
if [ "$APPLY" -eq 1 ]; then
  "$TMP/base/install.sh" "$TARGET" $PASS_THROUGH
else
  "$TMP/base/install.sh" "$TARGET" --dry-run $PASS_THROUGH
fi
rc=$?

if [ "$APPLY" -eq 0 ] && [ "$rc" -eq 0 ]; then
  echo
  echo "Dry run only. Re-run with ${BLD}--apply${OFF} to write."
fi
exit "$rc"
