#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Append one decision entry to .claude/log.md under the current session, so no reusable file carries meta-commentary.
#@usage     ga-log.sh --decided "<what>" --why "<reason>" [--how "<approach>"] [--session NAME] [--list]
#@in        --decided:string(required) --why:string(required) --how:string --session:name(default $GA_SESSION, else today) --list:flag(print the headings and entry counts)
#@out       stdout:the file and the session heading it appended under
#@exit      0=appended 2=usage
#@effects   appends to .claude/log.md — creates the file and the session heading if absent. Never rewrites an existing entry
#@when      log this decision|why did we do it this way|record the approach|meta comment|session log|decision journal|where do i put commentary

set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/ga-lifecycle.sh
. "$HERE/ga-lifecycle.sh"

TARGET="$(cd "$HERE/.." && pwd)"
LOG=".claude/log.md"
SESSION="${GA_SESSION:-$(date +%Y-%m-%d)}"
DECIDED=""; WHY=""; HOW=""; LIST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --decided) DECIDED="${2:-}"; shift 2 ;;
    --why)     WHY="${2:-}"; shift 2 ;;
    --how)     HOW="${2:-}"; shift 2 ;;
    --session) SESSION="${2:-}"; shift 2 ;;
    --target)  TARGET="${2:-}"; shift 2 ;;
    --list)    LIST=1; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit "$GA_EX_USAGE" ;;
    *) ga_die "unknown argument: $1" "$GA_EX_USAGE" ;;
  esac
done

cd "$TARGET" || ga_die "no such directory: $TARGET" "$GA_EX_USAGE"

if [ "$LIST" -eq 1 ]; then
  [ -f "$LOG" ] || { printf 'no %s yet\n' "$LOG"; exit "$GA_EX_OK"; }
  awk '/^## /{if(h)printf "  %-44s %d entr%s\n", h, n, (n==1?"y":"ies"); h=substr($0,4); n=0; next}
       /^- \*\*Decided:\*\*/{n++}
       END{if(h)printf "  %-44s %d entr%s\n", h, n, (n==1?"y":"ies")}' "$LOG"
  exit "$GA_EX_OK"
fi

[ -n "$DECIDED" ] || ga_die "--decided is required" "$GA_EX_USAGE"
[ -n "$WHY" ]     || ga_die "--why is required — an entry with no reason is the thing this file exists to capture" "$GA_EX_USAGE"

clean() { printf '%s' "$1" | tr '\t\n' '  ' | sed 's/  */ /g; s/^ //; s/ $//'; }
DECIDED="$(clean "$DECIDED")"
WHY="$(clean "$WHY")"
HOW="$(clean "$HOW")"
HEADING="## $SESSION"

if [ ! -f "$LOG" ]; then
  mkdir -p .claude
  cat > "$LOG" <<'HEADER'
# Decision log

**For the reader, not for Claude.** What was decided, why, when, and by what approach. It is
**never read to decide anything** — that is `docs/DECISIONS.md`, which is normative and is read
before every §0 question. This file is the story of arriving there.

Append-only, one section per session, written only by:

```bash
./Scripts/ga-log.sh --decided "<what>" --why "<reason>" --how "<approach>"
```

Meta-commentary belongs here and nowhere else — not in a skill, a command, a script, a doc or a
`#` comment. Those carry the rule; this carries the reasoning
([STRUCTURE.md](../docs/STRUCTURE.md)).

---
HEADER
  CREATED="created "
else
  CREATED=""
fi

TMP="$LOG.tmp.$$"
ENTRY="$LOG.entry.$$"
trap 'rm -f "$TMP" "$ENTRY"' EXIT

{
  printf -- '- **Decided:** %s\n' "$DECIDED"
  printf -- '  **Why:** %s\n' "$WHY"
  [ -n "$HOW" ] && printf -- '  **How:** %s\n' "$HOW"
  printf -- '  *(%s)*\n' "$(ga_now_iso)"
} > "$ENTRY"

if grep -qx -- "$HEADING" "$LOG" 2>/dev/null; then
  awk -v h="$HEADING" -v f="$ENTRY" '
    function emit() { while ((getline line < f) > 0) print line; close(f); done = 1 }
    !done && seen && /^## / && $0 != h { emit(); print ""; print; next }
    { print }
    $0 == h { seen = 1 }
    END { if (!done) { print ""; emit() } }
  ' "$LOG" > "$TMP" \
    || ga_die "could not insert under $HEADING — $LOG is unchanged" "$GA_EX_ERR"
  [ -s "$TMP" ] || ga_die "refusing to write an empty $LOG" "$GA_EX_ERR"
  mv "$TMP" "$LOG" || ga_die "could not replace $LOG" "$GA_EX_ERR"
  WHERE="existing"
else
  { printf '\n%s\n\n' "$HEADING"; cat "$ENTRY"; } >> "$LOG" \
    || ga_die "could not append to $LOG" "$GA_EX_ERR"
  WHERE="new"
fi

printf '%sappended\t%s\t%s session heading\t%s\n' "$CREATED" "$LOG" "$WHERE" "$HEADING"
