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
docs/ADOPTION.md
docs/SHARING.md
Scripts/adopt.sh
Scripts/build-plugin.sh
install.sh
"

# ── What must NOT travel, and why ──────────────────────────────────────────
# Each is this product's state. Carrying it into another repo makes the target's docs lie.
EXCLUDED="
CLAUDE.md|the target's rules are its own — /project-init reconciles instead of overwriting
docs/DECISIONS.md|THIS product's answers — an empty one is created instead (see Scaffolded)
docs/GAPS.md|gap statuses are per-product — an empty one is created instead (see Scaffolded)
Packages|this product's code
App|this product's app shells
README.md|the target has its own
.gitignore|the target has its own; merge by hand if needed
"

# ── Nothing may fall through the lists ─────────────────────────────────────
# ADOPTION.md, SHARING.md and install.sh were silently not installed for weeks: they were added
# after these lists were written and nobody updated them. A missing file is invisible at adopt
# time and only surfaces when a command references it in someone else's repo. So: fail loudly.
SCAFFOLDED="docs/DECISIONS.md docs/GAPS.md .claude/notes"
# BASE is newline-separated and EXCLUDED is "path|reason" — flatten both to a space-delimited
# list of bare paths before matching, or every entry looks unaccounted for.
KNOWN=" $(echo $BASE) $(printf '%s\n' "$EXCLUDED" | sed 's/|.*//' | tr '\n' ' ') $SCAFFOLDED "
unaccounted=""
for f in $(ls -d docs/*.md docs/modules Scripts/* .swiftlint.yml .swiftformat .gitignore \
                 install.sh README.md CLAUDE.md .claude/skills .claude/commands .claude/notes \
                 Packages App 2>/dev/null); do
  case "$KNOWN" in *" $f "*) continue ;; esac
  unaccounted="$unaccounted $f"
done
if [ -n "$unaccounted" ]; then
  echo
  echo "${RED}✗ these are in neither BASE, EXCLUDED nor SCAFFOLDED — they would be silently skipped${OFF}"
  for f in $unaccounted; do echo "    $f"; done
  echo "  ${DIM}Add each to one of the three lists in this script, then re-run.${OFF}"
  exit 1
fi

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

# ── Scaffolded: created empty in the target, never copied from here ────────
# /decide, /gaps and /project-init all write to these. Without them the commands have nowhere to
# go; with our copies the target inherits this product's decisions. So: create, don't copy.
echo
echo "${BLD}── Created empty (never copied) ────────────────────────${OFF}"
scaffolded=0
for pair in "docs/DECISIONS.md|the target records its own decisions here — /decide" \
            "docs/GAPS.md|the target triages its own gaps here — /gaps" \
            ".claude/notes|the eight inventories, prose kept and data rows blanked"; do
  f="${pair%%|*}"; why="${pair#*|}"
  if [ -e "$TARGET/$f" ]; then
    printf '  %scollision%s  %s %s(exists — kept)%s\n' "$YEL" "$OFF" "$f" "$DIM" "$OFF"
  else
    printf '  %s+%s %s %s— %s%s\n' "$GRN" "$OFF" "$f" "$DIM" "$why" "$OFF"
    scaffolded=$((scaffolded + 1))
  fi
done

if [ "$APPLY" -eq 1 ] && [ ! -e "$TARGET/.claude/notes" ]; then
  mkdir -p "$TARGET/.claude"
  cp -R "$SRC/.claude/notes" "$TARGET/.claude/notes"
  # Keep every heading, rule and commented example; blank only filled data rows. A row is data if
  # it has 3+ cells and is not the header or its separator.
  for n in "$TARGET"/.claude/notes/*.md; do
    python3 - "$n" <<'PY'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1]); out = []; prev_header = False
for line in p.read_text().splitlines():
    st = line.strip()
    is_row = st.startswith("|") and st.endswith("|") and st.count("|") >= 3
    is_sep = bool(re.fullmatch(r"\|[\s\-:|]+\|", st))
    is_dash = is_row and all(c.strip() in ("", "—", "-") for c in st.strip("|").split("|"))
    if is_row and not is_sep and not is_dash and not prev_header:
        continue                      # a filled data row — this product's state
    out.append(line)
    prev_header = is_row and not is_sep
p.write_text("\n".join(out) + "\n")
PY
  done
fi

if [ "$APPLY" -eq 1 ]; then
  mkdir -p "$TARGET/docs"
  [ -e "$TARGET/docs/DECISIONS.md" ] || cat > "$TARGET/docs/DECISIONS.md" <<'DEC'
# Decisions

Settled choices. **Read this before asking a CLAUDE.md §0 question** — it may already be answered.
Add a row when a §0 decision is made; never remove one.

## Settled — follow these, don't re-derive

| Scope | Decision | Why | Detail |
|---|---|---|---|
| — | — | — | — |

## Ask every time — never assume

Presentation pattern (per feature/screen) · persistence engine (only if data is stored) · caching
and offline policy (any remote fetch) · any new external dependency · extracting a package.
Options and phrasing: CLAUDE.md §0. Record the answer here with `/decide`.

## Do not re-propose

Rejected with reasons recorded — reopen only with new information, not a fresh preference.

| Rejected | Where the reasoning lives |
|---|---|
| — | — |

## Open

| Question | Blocks | Note |
|---|---|---|
| — | — | — |

---

## Per feature

| Date | Feature | Presentation | Persistence | Caching / offline |
|---|---|---|---|---|
| — | — | — | — | — |
DEC
  [ -e "$TARGET/docs/GAPS.md" ] || cat > "$TARGET/docs/GAPS.md" <<'GAP'
# Gaps

What this architecture does not cover **for this product**, as decisions to make rather than a
backlog to burn down. Run `/gaps` to triage.

`/gaps` behaves differently by repo state: on an existing repo it derives each status from the code
without asking; on a fresh one it asks per item. Absence of evidence is not always a decision — no
StoreKit means the product doesn't monetise, but no crash reporting is a **missing safeguard**,
reported as a risk rather than silently skipped.

## Status legend

| Status | Meaning | Gets re-raised? |
|---|---|---|
| ✅ **Applied** | Landed. The row records where | No |
| ▶ **Open** | Needs a decision | Yes, by `/gaps` |
| ⏸ **Deferred** | Tracked, with a named revisit trigger | Only when the trigger fires |
| ⛔ **Skipped** | Decided against. Also recorded in DECISIONS.md *Do not re-propose* | **No** |

**Skip is a real answer.** Most capabilities should end up Skipped for any given product.

## ▶ Open

| Item | Cost of skipping | Status |
|---|---|---|
| Feature flags / remote config | No kill switch — a bad release is only fixable by another release | ▶ |
| Crash reporting + dSYM upload | Crash reports unreadable, unrecoverable after the fact | ▶ |
| SwiftLint / SwiftFormat config | Rules stay review-only and decay | ▶ |
| Analytics event taxonomy | Events accrete ad-hoc and become unqueryable | ▶ |
| Auth flows · IAP · CloudKit · widgets · search · haptics · biometrics | — | ▶ |

Run `/gaps` to work through these; it fills in what your code already answers.

## Recording an answer

- **Adopt** → do the work, move the row to Applied with where it landed.
- **Defer** → ⏸ and **name the trigger**. A deferral with no trigger is an Open item pretending.
- **Skip** → ⛔ **and** a DECISIONS.md *Do not re-propose* row. Both, or it comes back.

Never delete a row. The value is knowing what was considered and declined.
GAP
fi

echo
echo "${BLD}────────────────────────────────────────────────────────${OFF}"
printf '%d to copy · %d created empty · %d collision(s) kept · %d excluded by design\n' \
  "$copied" "$scaffolded" "$collided" "$skipped"

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
