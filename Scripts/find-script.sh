#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Intent phrase to the registered script that answers it, scored against the registry.
#@usage     find-script.sh "<intent in 3-8 words>" [--all] [--min N]
#@in        intent:str --all:flag(every scoring row, not just the best) --min:int(score floor 0-100, default 40)
#@out       stdout:tsv(score,path,claude,purpose) best first; a miss prints the record-it hint
#@exit      0=a script answers this 1=nothing scored above the floor 2=usage 3=tool missing
#@effects   read-only. Never touches the network and never invokes a compiler.
#@when      which script does this|is there a script for|what script|do we have a script|before writing a script|find a script|script exists

# Why this exists: the most expensive thing in a session is re-deriving a pipeline that is
# already a registered script. Grepping .claude/SCRIPTS.tsv works only if you guess the same
# word the author used in `purpose`. This scores an intent against the `when` trigger phrases
# AND the purpose text, so "why won't it build" finds a script whose purpose says "diagnostics".
#
# A registry hit costs ~20 tokens. Re-deriving the pipeline costs a few thousand and produces
# something subtly different each time. That gap is the entire argument for this script.
#
# skill = script: this replaces the "which tool for which question" decision table that would
# otherwise live as prose in a skill body and be re-read every session.

set -o pipefail

REG=".claude/SCRIPTS.tsv"
MIN=40
ALL=0
INTENT=""

usage() {
  printf 'usage: find-script.sh "<intent in 3-8 words>" [--all] [--min N]\n' >&2
  printf 'example: ./Scripts/find-script.sh "check the memory store is consistent"\n' >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --all)     ALL=1; shift ;;
    --min)     MIN="$2"; shift 2 || usage ;;
    -h|--help) usage ;;
    -*)        printf 'find-script.sh: unknown flag %s\n' "$1" >&2; usage ;;
    *)         [ -n "$INTENT" ] && { printf 'find-script.sh: one intent at a time\n' >&2; usage; }
               INTENT="$1"; shift ;;
  esac
done

[ -n "$INTENT" ] || usage
case "$MIN" in ''|*[!0-9]*) printf 'find-script.sh: --min takes an integer\n' >&2; usage ;; esac

for t in awk tr grep; do
  command -v "$t" >/dev/null 2>&1 || { printf 'find-script.sh: missing required tool: %s\n' "$t" >&2; exit 3; }
done

# Resolve from this file so the script works from any cwd inside the repo.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || { printf 'find-script.sh: cannot enter %s\n' "$ROOT" >&2; exit 2; }
[ -f "$REG" ] || { printf 'find-script.sh: no %s — run register-scripts.sh first\n' "$REG" >&2; exit 2; }

# Stopwords carry no routing signal and would match everything. Kept deliberately short: an
# aggressive list throws away the verb, and the verb is usually the most discriminating word.
STOP=" a an and are as at be by can do does for from get how i in is it its of on or our that the their then this to us was what when where which who will with your "

# Score = weighted term overlap, normalised to 0-100.
#   a term found in `when`    scores 3  — that field exists purely for routing
#   a term found in `purpose` scores 2
#   a term found in `usage`   scores 1  — catches a flag or subcommand name
# Normalising by the number of scorable terms keeps a long intent from out-scoring a short one
# purely by having more words.
awk -F'\t' -v intent="$INTENT" -v stop="$STOP" -v min="$MIN" -v all="$ALL" '
function lc(s) { return tolower(s) }
BEGIN {
  n = split(lc(intent), raw, /[^a-z0-9]+/)
  terms = 0
  for (i = 1; i <= n; i++) {
    t = raw[i]
    if (length(t) < 3) continue
    if (index(stop, " " t " ") > 0) continue
    # crude singularisation so "warnings" matches "warning"
    if (length(t) > 4 && substr(t, length(t)) == "s") t = substr(t, 1, length(t) - 1)
    if (t in seen) continue
    seen[t] = 1
    term[++terms] = t
  }
}
/^#/ { next }
NF < 11 { next }
{
  path = $1; claude = $4; purpose = lc($5); use = lc($6); whenf = lc($11)
  hit = 0; matched = 0
  for (i = 1; i <= terms; i++) {
    w = 0
    if (whenf   != "" && index(whenf, term[i])   > 0) w = 3
    else if (index(purpose, term[i]) > 0)             w = 2
    else if (index(use, term[i])     > 0)             w = 1
    if (w > 0) { hit += w; matched++ }
  }
  if (terms == 0 || matched == 0) next
  # max attainable is 3 per term; scale against that
  score = int((hit * 100) / (terms * 3))
  # a script with no when= can never reach the top band, so lift it slightly to stay
  # competitive on purpose-only matches rather than being permanently unfindable
  if (whenf == "" && score > 0) score += 8
  if (score > 100) score = 100
  if (score < min) next
  printf "%d\t%s\t%s\t%s\n", score, path, claude, $5
}
' "$REG" | sort -rn -k1,1 > "$$.scored"

if [ ! -s "$$.scored" ]; then
  rm -f "$$.scored"
  printf 'no registered script scores above %s for: %s\n' "$MIN" "$INTENT" >&2
  printf 'improvise it once, then register it:\n' >&2
  printf '  ./Scripts/session-script.sh add --intent "%s" --cmd '"'"'<the pipeline>'"'"'\n' "$INTENT" >&2
  exit 1
fi

if [ "$ALL" -eq 1 ]; then
  cat "$$.scored"
else
  head -5 "$$.scored"
fi
rm -f "$$.scored"
exit 0
