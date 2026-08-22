#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    needs-approval
#@purpose   Compare an installed target against the base and list per-file decisions, CLAUDE.md included.
#@usage     adopt-review.sh <target-dir> [--base DIR] [--diff N] [--take LIST|--take all]
#@in        target:dir --base:dir(default this repo) --diff:int(context lines to show, default 0) --take:csv(item numbers)
#@out       stdout:numbered table(n,state,path,delta) then a decision footer; --take applies only those items
#@exit      0=target matches the base 1=decisions pending 2=usage 3=tool missing
#@effects   read-only unless --take is passed, which overwrites exactly the listed target files
#@when      what would change on update|is my install stale|did the base move|review an install|what did adopt skip|update my claude md

# Why this exists: adopt.sh reports "N collision(s) kept as-is" and moves on. That sentence hides
# the only question worth asking — did the incoming file actually CHANGE, and do you want it? A
# count of skipped files is not a decision; it is the absence of one.
#
# So this classifies every shipped path against the target and prints a numbered list. Nothing is
# written unless you pass --take with the numbers you chose. Claude must never pass --take: the
# whole point is that overwriting a file in someone's shipping repo is a human decision, and an
# approval never carries from one run to the next.
#
# CLAUDE.md is included, unlike in adopt.sh where it is flat-excluded. Excluding it entirely was
# right for a first install — the target's rules are its own — but it means a genuinely useful new
# rule can never reach a project that already adopted. Comparison is per SECTION, keyed on the
# numbered headings, so the output is "you do not have section 12" rather than a whole-file diff
# nobody reads. Applying one is still yours to decide, and CLAUDE.md is never written by --take:
# it routes to the pipeline that edits it under a record.

set -o pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
TARGET=""
CTX=0
TAKE=""
MAX_LINES="${MAX_LINES:-100}"

usage() {
  printf 'usage: adopt-review.sh <target-dir> [--base DIR] [--diff N] [--take LIST|all]\n' >&2
  printf 'example: ./Scripts/adopt-review.sh ~/code/ts-ios --diff 3\n' >&2
  exit 2
}

for t in awk sed grep diff shasum; do
  command -v "$t" >/dev/null 2>&1 || { printf 'adopt-review.sh: missing required tool: %s\n' "$t" >&2; exit 3; }
done

while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="$2"; shift 2 || usage ;;
    --diff) CTX="$2"; shift 2 || usage ;;
    --take) TAKE="$2"; shift 2 || usage ;;
    -h|--help) usage ;;
    -*) printf 'adopt-review.sh: unknown flag %s\n' "$1" >&2; usage ;;
    *) [ -z "$TARGET" ] && TARGET="$1" || usage; shift ;;
  esac
done

[ -n "$TARGET" ] || usage
[ -d "$TARGET" ] || { printf 'adopt-review.sh: no such directory: %s\n' "$TARGET" >&2; exit 2; }
[ -f "$BASE/Scripts/adopt.sh" ] || { printf 'adopt-review.sh: --base %s has no Scripts/adopt.sh\n' "$BASE" >&2; exit 2; }
case "$CTX" in ''|*[!0-9]*) printf 'adopt-review.sh: --diff takes an integer\n' >&2; usage ;; esac
TARGET="$(cd "$TARGET" && pwd)"

# The shipped set comes out of adopt.sh's own BASE list. Re-listing it here is how the two would
# disagree, which is the bug docs/SHARING.md already warns about.
shipped() {
  awk '/^BASE="/{f=1;next} f&&/^"/{exit} f&&NF{print}' "$BASE/Scripts/adopt.sh"
}

# One entry per FILE, so a decision is per file rather than per directory.
expand() {
  if [ -d "$BASE/$1" ]; then (cd "$BASE" && find "$1" -type f 2>/dev/null | sort)
  elif [ -f "$BASE/$1" ]; then printf '%s\n' "$1"; fi
}

ROWS=$(mktemp); trap 'rm -f "$ROWS"' EXIT
n=0
for item in $(shipped); do
  for f in $(expand "$item"); do
    if [ ! -e "$TARGET/$f" ]; then
      n=$((n+1)); printf '%s\tmissing\t%s\tnot installed\n' "$n" "$f" >> "$ROWS"
    elif shasum -a256 "$BASE/$f" 2>/dev/null | cut -d' ' -f1 | \
         grep -qxF "$(shasum -a256 "$TARGET/$f" 2>/dev/null | cut -d' ' -f1)"; then
      : # identical — the common case, and printing it would bury the decisions
    else
      add=$(diff -u "$TARGET/$f" "$BASE/$f" 2>/dev/null | grep -c '^+[^+]')
      del=$(diff -u "$TARGET/$f" "$BASE/$f" 2>/dev/null | grep -c '^-[^-]')
      n=$((n+1)); printf '%s\tdiffers\t%s\t+%s/-%s vs base\n' "$n" "$f" "$add" "$del" >> "$ROWS"
    fi
  done
done

# ── apply mode ────────────────────────────────────────────────────────────────
if [ -n "$TAKE" ]; then
  [ -s "$ROWS" ] || { printf 'nothing to take — target matches the base\n'; exit 0; }
  applied=0
  while IFS="$(printf '\t')" read -r num state path _; do
    want=0
    if [ "$TAKE" = all ]; then want=1
    else case ",$TAKE," in *",$num,"*) want=1 ;; esac; fi
    [ "$want" -eq 1 ] || continue
    # CLAUDE.md is never overwritten here. It loads into every session, so it goes through the
    # pipeline that edits it section by section under a record, with its own approval gate.
    case "$path" in
      CLAUDE.md|*/CLAUDE.md)
        printf '  SKIP  %-46s use the CLAUDE.md pipeline, not a file copy\n' "$path"; continue ;;
    esac
    mkdir -p "$TARGET/$(dirname "$path")"
    # MAP.tsv carries a `# FETCH-BASE:` stamp that install.sh adds and the base therefore does not
    # have. Copying the base over it drops the stamp, and every `docs/…` row in the map — the ones
    # that are fetched rather than installed — stops resolving. The failure is silent: the rows are
    # still there, they just point nowhere. So carry the stamp across.
    stamp=""
    [ -f "$TARGET/$path" ] && stamp="$(grep -m1 '^# FETCH-BASE:' "$TARGET/$path" 2>/dev/null || true)"
    cp "$BASE/$path" "$TARGET/$path" && { printf '  took  %-46s (%s)\n' "$path" "$state"; applied=$((applied+1)); }
    if [ -n "$stamp" ] && ! grep -q '^# FETCH-BASE:' "$TARGET/$path" 2>/dev/null; then
      { printf '%s\n' "$stamp"; cat "$TARGET/$path"; } > "$TARGET/$path.ga.tmp" \
        && mv "$TARGET/$path.ga.tmp" "$TARGET/$path"
      printf '        %s kept the FETCH-BASE stamp the base does not carry\n' "↳"
    fi
  done < "$ROWS"
  printf '\n%d file(s) taken from the base. Review with: git -C %s diff\n' "$applied" "$TARGET"
  exit 0
fi

# ── report mode ───────────────────────────────────────────────────────────────
total=$(wc -l <"$ROWS" | tr -d ' ')

printf '\nadopt-review  %s\n' "$TARGET"
printf '  base %s\n\n' "$BASE"

if [ "$total" -eq 0 ]; then
  printf '  every shipped file matches the base — nothing to decide\n'
else
  printf '  %-3s %-8s %-46s %s\n' "n" "state" "path" "delta"
  awk -F'\t' -v m="$MAX_LINES" 'NR<=m {printf "  %-3s %-8s %-46s %s\n", $1, $2, $3, $4}' "$ROWS"
  [ "$total" -gt "$MAX_LINES" ] && printf '  ...+%d more\n' "$((total - MAX_LINES))"
  if [ "$CTX" -gt 0 ]; then
    printf '\n'
    awk -F'\t' '$2=="differs"{print $3}' "$ROWS" | while IFS= read -r p; do
      printf '  --- %s\n' "$p"
      diff -U "$CTX" "$TARGET/$p" "$BASE/$p" 2>/dev/null | sed -n "3,$((CTX*4+8))p" | sed 's/^/      /'
    done
  fi
fi

# ── CLAUDE.md, section by section ─────────────────────────────────────────────
printf '\n  CLAUDE.md\n'
if [ ! -f "$TARGET/CLAUDE.md" ]; then
  printf '    the target has none — /project-init writes one with your approval\n'
elif [ ! -f "$BASE/CLAUDE.md" ]; then
  printf '    the base has none to compare against\n'
else
  bs=$(mktemp); ts=$(mktemp)
  # Sort numerically on the section number, not lexically: a plain sort puts 10 before 2, which
  # reads as a missing section list in the wrong order and makes the output hard to scan.
  grep -E '^## [0-9]+\.' "$BASE/CLAUDE.md"   | sed 's/^## //' | sort -t. -k1,1n > "$bs"
  grep -E '^## [0-9]+\.' "$TARGET/CLAUDE.md" | sed 's/^## //' | sort -t. -k1,1n > "$ts"
  pad() { awk -F. '{printf "%03d\t%s\n", $1, $0}' "$1" | sort; }
  only_base=$(comm -23 <(pad "$bs") <(pad "$ts") | cut -f2)
  only_target=$(comm -13 <(pad "$bs") <(pad "$ts") | cut -f2)
  if [ -z "$only_base" ] && [ -z "$only_target" ]; then
    printf '    same section set — differences, if any, are inside sections and are yours to keep\n'
  fi
  [ -n "$only_base" ] && { printf '    in the base, not in yours — candidates, none applied automatically:\n'
                           printf '%s\n' "$only_base" | sed 's/^/      + /'; }
  [ -n "$only_target" ] && { printf '    yours only — kept, never touched:\n'
                             printf '%s\n' "$only_target" | sed 's/^/      - /'; }
  printf '    to adopt one, run it through the pipeline so it lands under a record:\n'
  printf '      ./Scripts/claude-workflows/run-task.sh <project> <task-id> all --text "add section N from the base"\n'
  rm -f "$bs" "$ts"
fi

if [ "$total" -eq 0 ]; then printf '\n'; exit 0; fi
printf '\n  %d decision(s) pending. Nothing was written.\n' "$total"
printf '    take some:  ./Scripts/adopt-review.sh %s --take 1,4,7\n' "$TARGET"
printf '    take all:   ./Scripts/adopt-review.sh %s --take all\n' "$TARGET"
printf '    see diffs:  ./Scripts/adopt-review.sh %s --diff 3\n\n' "$TARGET"
exit 1
