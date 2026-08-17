#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Verify the .claude/memory/ store: index bijection, frontmatter validity, no user-type leak.
#@usage     verify-memory.sh [--dir DIR] [--quiet]
#@in        --dir:path(memory dir, default .claude/memory) --quiet:flag(violations only, no tally)
#@out       stdout:tsv(file,rule,detail) one violation per line, then a per-rule tally
#@exit      0=consistent 1=violations found 2=usage 3=tool missing
#@effects   read-only. Never touches the network and never invokes a compiler.
#@when      memory consistent|check memory|memory index broken|orphan memory|is the memory store ok|verify memory

# Why this exists: Scripts/memory-add.py validates a memory as it is WRITTEN, but nothing
# re-checks the store afterwards. Hand edits, merge conflicts and a fresh adopt.sh install are
# all points where a memory file loses its index row, or an index row outlives its file. A
# memory nobody finds is the failure mode .claude/memory/INDEX.md is explicit about, so this
# turns that from a convention into an exit code CI can gate on.

set -o pipefail

MEM=".claude/memory"
QUIET=0
MAX_LINES="${MAX_LINES:-100}"

usage() {
  printf 'usage: verify-memory.sh [--dir DIR] [--quiet]\n' >&2
  printf 'example: ./Scripts/verify-memory.sh --quiet\n' >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)   MEM="$2"; shift 2 || usage ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) usage ;;
    *) printf 'verify-memory.sh: unknown argument %s\n' "$1" >&2; usage ;;
  esac
done

for t in grep sed awk basename; do
  command -v "$t" >/dev/null 2>&1 || { printf 'verify-memory.sh: missing required tool: %s\n' "$t" >&2; exit 3; }
done

[ -d "$MEM" ] || { printf 'verify-memory.sh: no such directory: %s\n' "$MEM" >&2; exit 2; }
INDEX="$MEM/INDEX.md"
[ -f "$INDEX" ] || { printf 'verify-memory.sh: no %s — this repo has not adopted the memory layout.\n' "$INDEX" >&2; exit 2; }

VIOL=$(mktemp)
trap 'rm -f "$VIOL"' EXIT

record() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$VIOL"; }

# ── field extraction ───────────────────────────────────────────────────────
# Frontmatter is the block between the first two `---` lines. Reading only that block keeps a
# body that happens to contain `name:` from being mistaken for the header.
frontmatter() { awk 'NR==1 && $0!="---"{exit} NR==1{next} /^---$/{exit} {print}' "$1"; }
field() { frontmatter "$1" | grep -m1 "^$2:" | sed "s/^$2:[[:space:]]*//"; }
nested() { frontmatter "$1" | grep -m1 "^[[:space:]]\{1,\}$2:" | sed "s/^[[:space:]]*$2:[[:space:]]*//"; }

VALID_TYPES="project reference feedback"

# ── every memory file is well-formed and indexed ───────────────────────────
count=0
for f in "$MEM"/*.md; do
  [ -e "$f" ] || break
  base=$(basename "$f")
  [ "$base" = "INDEX.md" ] && continue
  count=$((count + 1))
  slug="${base%.md}"

  if [ "$(head -1 "$f")" != "---" ]; then
    record "$base" no-frontmatter "first line is not ---; the file cannot be parsed as a memory"
    continue
  fi

  name=$(field "$f" name)
  desc=$(field "$f" description)
  type=$(nested "$f" type)

  [ -n "$name" ] || record "$base" missing-name "frontmatter has no name:"
  [ -n "$desc" ] || record "$base" missing-description "frontmatter has no description: — recall matches on this line"
  if [ -n "$name" ] && [ "$name" != "$slug" ]; then
    record "$base" name-mismatch "name: is '$name' but the filename slug is '$slug'; [[wikilinks]] resolve by name"
  fi

  if [ -z "$type" ]; then
    record "$base" missing-type "frontmatter has no metadata.type:"
  elif [ "$type" = "user" ]; then
    record "$base" user-type-committed "type: user is per-person and must never be committed — move it to the machine-local store"
  else
    case " $VALID_TYPES " in
      *" $type "*) ;;
      *) record "$base" bad-type "type: '$type' is not one of: $VALID_TYPES" ;;
    esac
  fi

  case "$type" in
    feedback|project)
      grep -q '\*\*Why:\*\*' "$f" || record "$base" missing-why "type '$type' requires a **Why:** line (Scripts/memory-add.py enforces this on write)"
      ;;
  esac

  grep -qF "$base" "$INDEX" || record "$base" not-indexed "no row in INDEX.md mentions this file — a memory with no row is a memory nobody finds"
done

# ── every index row that names a .md points at a real file ─────────────────
# Only the FIRST cell of a table row is the reference; the second is a human hook that may
# legitimately mention another .md in prose (a row about CLAUDE.md is not a row pointing at a
# file called CLAUDE.md). The shipped INDEX.md also carries a `| — | — |` placeholder and an
# HTML-commented example, so a fresh install with no memories must still pass.
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  [ -f "$MEM/$ref" ] || record "INDEX.md" orphan-row "row references $ref but $MEM/$ref does not exist"
done <<EOF
$(awk -F'|' '/^\|/ && !/^\|[[:space:]]*(Memory|-{1,})/ {print $2}' "$INDEX" \
  | grep -oE '[A-Za-z0-9._-]+\.md' | sort -u)
EOF

# ── report ────────────────────────────────────────────────────────────────
total=$(wc -l <"$VIOL" | tr -d ' ')

if [ "$total" -eq 0 ]; then
  [ "$QUIET" -eq 1 ] || printf 'memory: %s consistent — %d memor%s, index bijective\n' "$MEM" "$count" "$([ "$count" -eq 1 ] && echo y || echo ies)"
  exit 0
fi

sort "$VIOL" | head -n "$MAX_LINES"
if [ "$total" -gt "$MAX_LINES" ]; then
  printf '...+%d more\n' "$((total - MAX_LINES))"
fi

if [ "$QUIET" -eq 0 ]; then
  printf '\n'
  awk -F'\t' '{c[$2]++} END{for (r in c) printf "  %4d  %s\n", c[r], r}' "$VIOL" | sort -rn
  printf '\n  %d violation(s) across %d memor%s\n' "$total" "$count" "$([ "$count" -eq 1 ] && echo y || echo ies)"
fi

exit 1
