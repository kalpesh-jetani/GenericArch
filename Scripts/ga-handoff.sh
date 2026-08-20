#!/usr/bin/env bash
#@kind      lib
#@platform  macos
#@claude    call
#@purpose   Write a small, bounded failure report when a script fails, so the agent fixes it from the diagnosis instead of reading the script.
#@usage     ga-handoff.sh <script> <exit-code> [--cause TEXT] [--file PATH] [--line N] [--got TEXT] [--want TEXT]
#@in        script:path exit:int --cause:string(one line, what went wrong) --file:path(the input it choked on) --line:int(where) --got:string --want:string
#@out       stdout:the report path and a one-line summary; file:.genericarch/failures/<script>-<n>.md
#@exit      0=report written 2=usage
#@effects   writes one file under .genericarch/failures/, capped at 60 lines
#@when      a script failed|hand a failure to claude|script broke on this repo|fix a script|adapt a script to this machine|handoff report
#
# The point of this file is what it does NOT do: it does not put a script's source into the agent's
# context. A 200-line scanner is 700 tokens to read and re-derive; the fifteen lines that explain
# why it failed on THIS repo are sixty. So a failing script writes a diagnosis — what ran, what it
# expected, what it found, and the machine facts that matter — and the agent works from that.
#
# Every report is bounded on purpose. An unbounded log is a script body with extra steps.
set -o pipefail

SCRIPT="${1:-}"; CODE="${2:-}"
[ -n "$SCRIPT" ] && [ -n "$CODE" ] || { echo "usage: ga-handoff.sh <script> <exit-code> [--cause T] [--file P] [--line N] [--got T] [--want T]" >&2; exit 2; }
shift 2

CAUSE=""; FILE=""; LINE=""; GOT=""; WANT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --cause) CAUSE="${2:-}"; shift 2 || true ;;
    --file)  FILE="${2:-}";  shift 2 || true ;;
    --line)  LINE="${2:-}";  shift 2 || true ;;
    --got)   GOT="${2:-}";   shift 2 || true ;;
    --want)  WANT="${2:-}";  shift 2 || true ;;
    *) shift ;;
  esac
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
DIR="$ROOT/.genericarch/failures"
mkdir -p "$DIR"
BASE="$(basename "$SCRIPT" | sed 's/\.[^.]*$//')"
n=1
while [ -e "$DIR/$BASE-$n.md" ]; do n=$((n + 1)); done
OUT="$DIR/$BASE-$n.md"

{
  printf '# %s failed (exit %s)\n\n' "$SCRIPT" "$CODE"
  printf '**Fix the script, not the symptom.** This report exists so you do not have to read the\n'
  printf 'script to know what broke. When the fix is specific to this repo or machine, say so in the\n'
  printf 'change and add a row to `docs/DECISIONS.md` — the next machine will differ again.\n\n'

  [ -n "$CAUSE" ] && printf '**Cause:** %s\n\n' "$CAUSE"
  if [ -n "$WANT" ] || [ -n "$GOT" ]; then
    printf '| | |\n|---|---|\n'
    [ -n "$WANT" ] && printf '| expected | %s |\n' "$WANT"
    [ -n "$GOT" ]  && printf '| found | %s |\n' "$GOT"
    printf '\n'
  fi

  if [ -n "$FILE" ] && [ -f "$FILE" ]; then
    printf '## The input it choked on\n\n`%s`' "${FILE#"$ROOT"/}"
    [ -n "$LINE" ] && printf ' line %s' "$LINE"
    printf '\n\n```\n'
    if [ -n "$LINE" ] && [ "$LINE" -gt 0 ] 2>/dev/null; then
      from=$((LINE - 5)); [ "$from" -lt 1 ] && from=1
      sed -n "${from},$((from + 14))p" "$FILE" | cut -c1-120
    else
      head -15 "$FILE" | cut -c1-120
    fi
    printf '```\n\n'
  elif [ -n "$FILE" ]; then
    printf '## The input it expected\n\n`%s` — **not on disk.** That absence may be the whole bug.\n\n' "${FILE#"$ROOT"/}"
  fi

  # One process per fact, and no `head` inside the pipe: closing the pipe early makes the whole
  # pipeline fail under `pipefail`, so the `||` fallback fires and BOTH values get printed.
  printf '## This machine\n\n'
  printf '```\nmacOS   %s\n' "$(sw_vers -productVersion 2>/dev/null || echo '?')"
  printf 'python3 %s\n' "$(python3 -V 2>&1 | awk 'NR==1 {print $2; exit}')"
  printf 'swift   %s\n' "$(swift --version 2>/dev/null | awk 'NR==1 {sub(/.*version /, ""); sub(/ .*/, ""); print; exit}')"
  printf 'xcode   %s\n```\n\n' "$(xcodebuild -version 2>/dev/null | awk 'NR==1 {print $2; exit}')"

  printf '## What to do\n\n'
  printf '1. Change the **script** so this repo shape works — a per-repo special case in the script is\n'
  printf '   better than a note nobody reads, and better than doing the scan by hand every time.\n'
  printf '2. Re-run it. If it now passes, delete this report in the same change.\n'
  printf '3. If it cannot be made mechanical, say so plainly and record which note stays manual.\n'
} > "$OUT"

# Hard cap. A report that grows past this is a script body with extra steps, and re-reading it every
# session costs more than the fix it was meant to make cheap.
if [ "$(grep -c '' "$OUT")" -gt 60 ]; then
  head -60 "$OUT" > "$OUT.tmp" && printf '\n_(truncated at 60 lines — the cap is deliberate)_\n' >> "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
fi

printf '\n  handoff written: %s\n' "${OUT#"$ROOT"/}" >&2
printf '  give that file to Claude — it does not need the script itself.\n' >&2
