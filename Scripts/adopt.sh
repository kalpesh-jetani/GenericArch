#!/usr/bin/env bash
# Copy the REUSABLE BASE of GenericArch into another repo — and nothing else.
#
#   ./Scripts/adopt.sh /path/to/TargetRepo            # dry run (default)
#   ./Scripts/adopt.sh /path/to/TargetRepo --apply
#
# Why a script instead of `cp -R`: this repo holds two different things. The base travels; this
# product's state must not. Copying wholesale gives the target GenericArch's decisions, its route
# table, and its gap statuses as if they were its own — the single most common adoption mistake.
#
# Nothing is ever overwritten. Existing files are reported and skipped, so the target's own
# CLAUDE.md, skills, and commands survive untouched.
set -o pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"

RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; DIM=$'\033[2m'; BLD=$'\033[1m'; OFF=$'\033[0m'

TARGET="${1:-}"
APPLY=0
QUIET_NEXT=0
for a in "$@"; do
  [ "$a" = "--apply" ] && APPLY=1
  # install.sh prints advice matched to fresh-vs-existing; ours would contradict it.
  [ "$a" = "--quiet-next" ] && QUIET_NEXT=1
done
[ "${1:-}" = "--apply" ] && { echo "${RED}pass the target path first${OFF}"; exit 2; }

if [ -z "$TARGET" ]; then
  cat <<USAGE
usage: ./Scripts/adopt.sh <target-repo> [--apply]

Copies the reusable base into <target-repo>. Dry run unless --apply is given.
USAGE
  exit 2
fi
[ -d "$TARGET" ] || { echo "${RED}no such directory: $TARGET${OFF}"; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"
[ "$TARGET" = "$SRC" ] && { echo "${RED}target is GenericArch itself${OFF}"; exit 1; }

# ── What travels ───────────────────────────────────────────────────────────
# Rules, design docs, agent tooling, enforcement. Product-independent.
BASE="
.claude/skills
.claude/commands
docs/modules
docs/STRUCTURE.md
docs/CONVENTIONS.md
docs/DONE.md
docs/REPO.md
docs/DELIVERY.md
docs/PERFORMANCE.md
.swiftlint.yml
.swiftformat
Scripts/check.sh
Scripts/check-skill-triggers.py
Scripts/detect-toolchain.sh
"

# ── What must NOT travel, and why ──────────────────────────────────────────
# Each is this product's state. Carrying it into another repo makes the target's docs lie.
EXCLUDED="
CLAUDE.md|the target's rules are its own — /project-init reconciles instead of overwriting
.claude/notes|inventories of THIS app's screens/routes/assets — /project-init creates the target's own
docs/DECISIONS.md|THIS product's answers; the target records its own
docs/GAPS.md|gap statuses are per-product
Packages|this product's code
App|this product's app shells
README.md|the target has its own
.gitignore|the target has its own; merge by hand if needed
"

echo
echo "${BLD}GenericArch → adopt${OFF}"
echo "  from  $SRC"
echo "  into  $TARGET"
[ "$APPLY" -eq 1 ] && echo "  mode  ${GRN}APPLY${OFF}" || echo "  mode  ${YEL}dry run${OFF} (add --apply to write)"
echo

if [ ! -d "$TARGET/.git" ]; then
  echo "${YEL}⚠ target is not a git repository — you won't be able to review or revert this${OFF}"
fi

copied=0; skipped=0; collided=0

# Expand a directory into its immediate entries, so one pre-existing command doesn't block the
# other four. Collisions must be per-item — a whole-directory skip is what made the first version
# of this script useless against a repo that already had a `build` command.
expand() {
  if [ -d "$SRC/$1" ]; then
    for e in "$SRC/$1"/*; do
      [ -e "$e" ] && echo "$1/$(basename "$e")"
    done
  else
    echo "$1"
  fi
}

copy_one() {
  item="$1"; dest="$TARGET/$item"
  if [ -e "$dest" ]; then
    printf '  %scollision%s  %s %s(exists — skipped, yours is kept)%s\n' "$YEL" "$OFF" "$item" "$DIM" "$OFF"
    collided=$((collided + 1)); return
  fi
  printf '  %s+%s %s\n' "$GRN" "$OFF" "$item"
  copied=$((copied + 1))
  if [ "$APPLY" -eq 1 ]; then
    mkdir -p "$(dirname "$dest")"
    cp -R "$SRC/$item" "$dest"
  fi
}

echo "${BLD}── Would copy ──────────────────────────────────────────${OFF}"
for item in $BASE; do
  [ -e "$SRC/$item" ] || { echo "  ${YEL}missing in source: $item${OFF}"; continue; }
  OLDIFS="$IFS"; IFS=$'\n'
  for leaf in $(expand "$item"); do
    IFS="$OLDIFS"; copy_one "$leaf"; IFS=$'\n'
  done
  IFS="$OLDIFS"
done

echo
echo "${BLD}── Deliberately NOT copied ─────────────────────────────${OFF}"
OLDIFS="$IFS"; IFS=$'\n'
for line in $EXCLUDED; do
  [ -z "$line" ] && continue
  name="${line%%|*}"; why="${line#*|}"
  printf '  %s−%s %-22s %s%s%s\n' "$DIM" "$OFF" "$name" "$DIM" "$why" "$OFF"
  skipped=$((skipped + 1))
done
IFS="$OLDIFS"

echo
echo "${BLD}────────────────────────────────────────────────────────${OFF}"
printf '%d to copy · %d collision(s) kept as-is · %d excluded by design\n' "$copied" "$collided" "$skipped"

if [ "$APPLY" -eq 0 ]; then
  echo
  echo "Dry run only. Re-run with ${BLD}--apply${OFF} to write."
  exit 0
fi

chmod +x "$TARGET/Scripts/check.sh" "$TARGET/Scripts/detect-toolchain.sh" 2>/dev/null
[ "$QUIET_NEXT" -eq 1 ] && exit 0
cat <<NEXT

${BLD}Next, in the target repo${OFF}

  1. ${BLD}/project-init${OFF}   Detects an existing repo and follows docs/ADOPTION.md — reads its
                    CLAUDE.md, builds the rule-conflict
                    table, and asks per conflict. Keeps their rules by default — nothing is
                    overwritten without an explicit yes.

  2. ${BLD}/gaps${OFF}           Derives each gap's status from the target's own code instead of asking,
                    and reports missing safeguards as risks.

  3. ${BLD}./Scripts/detect-toolchain.sh${OFF}
                    Reads the target's own stack from its project settings, and the machine for
                    the rest. Whatever CLAUDE.md ends up saying comes from this, not from
                    GenericArch's numbers. If it reports a mismatch, ${BLD}/upgrade-stack${OFF}
                    reviews it and asks twice before changing anything.

  4. ${BLD}./Scripts/check.sh${OFF}
                    Expect failures on an existing codebase — that is the point. Triage them in
                    /project-init as "keep theirs", "new code only", or "migrate".

${DIM}No CLAUDE.md was written. The target's rules stay the target's until it decides otherwise.${OFF}
NEXT
