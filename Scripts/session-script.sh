#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    needs-approval
#@purpose   Stage a script per session; promote to the shared tree only once a second session needs it.
#@usage     session-script.sh add --intent S --cmd C | list [--promotable] | show ID | promote ID [--apply] [--allow-mutating] | drop ID
#@in        --intent:str --cmd:str --session:id(default today) --apply:flag --allow-mutating:flag ID:slug
#@out       stdout:tsv(id,sessions,uses,status,intent) for list; for promote, one pass/fail line per promotion gate then the verdict
#@exit      0=ok 1=nothing promotable|gate failed 2=usage 3=tool missing
#@effects   writes .claude/CANDIDATES.tsv (tracked) + staging under .claude/claude-tasks/ (gitignored); promote --apply writes Scripts/
#@when      promote a script|is this reusable|same pipeline again|stage a script|candidate script|i keep typing this

# Why this exists: a pipeline improvised once is noise; the same pipeline needed in a LATER
# session is a real capability. So a generated script is staged session-locally and only earns a
# place in the shared tree when a second, distinct session asks for the same intent.
#
# Two stores, deliberately different in kind:
#   .claude/claude-tasks/sessions/<sid>/   staged scripts. Gitignored, ephemeral, per session.
#   .claude/CANDIDATES.tsv                 the recurrence ledger. TRACKED, because it is the
#                                          only thing that can observe "a second session", and
#                                          CLAUDE.md section 5 forbids a machine-local store for
#                                          anything that must survive a clone.
#
# skill = script: promotion writes a SCRIPT and re-runs register-scripts.sh. The shared skill
# gains a generated row via the registry; no skill prose is ever hand-written. That is the whole
# reason a promoted capability costs nothing until it is called.
#
# Session identity defaults to the calendar day. Two uses on different days is a stronger signal
# of a real pattern than two uses in one sitting, and unlike a pid it is stable across the
# invocations within one session. Override with --session or $GA_SESSION when you have a real id.

set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || { printf 'session-script.sh: cannot enter %s\n' "$ROOT" >&2; exit 2; }

LEDGER=".claude/CANDIDATES.tsv"
STAGE_ROOT=".claude/claude-tasks/sessions"
PROMOTED_MAX="${PROMOTED_MAX:-20}"
SESSION="${GA_SESSION:-$(date +%Y-%m-%d)}"
APPLY=0
ALLOW_MUTATING=0
INTENT=""
CMD=""
ID=""
PROMOTABLE=0

usage() {
  printf 'usage: session-script.sh add --intent S --cmd C | list [--promotable] | show ID | promote ID [--apply] | drop ID\n' >&2
  printf 'example: ./Scripts/session-script.sh add --intent "count swift files per target" --cmd '"'"'rg -c ...'"'"'\n' >&2
  exit 2
}

for t in awk sed grep shasum date; do
  command -v "$t" >/dev/null 2>&1 || { printf 'session-script.sh: missing required tool: %s\n' "$t" >&2; exit 3; }
done

ACTION="${1:-}"; [ -n "$ACTION" ] || usage; shift 2>/dev/null || true

while [ $# -gt 0 ]; do
  case "$1" in
    --intent)          INTENT="$2"; shift 2 || usage ;;
    --cmd)             CMD="$2"; shift 2 || usage ;;
    --session)         SESSION="$2"; shift 2 || usage ;;
    --apply)           APPLY=1; shift ;;
    --allow-mutating)  ALLOW_MUTATING=1; shift ;;
    --promotable)      PROMOTABLE=1; shift ;;
    -h|--help)         usage ;;
    -*)                printf 'session-script.sh: unknown flag %s\n' "$1" >&2; usage ;;
    *)                 [ -z "$ID" ] && ID="$1" || usage; shift ;;
  esac
done

# ── ledger plumbing ───────────────────────────────────────────────────────────
ensure_ledger() {
  [ -f "$LEDGER" ] && return
  mkdir -p .claude
  {
    printf '#\tGenericArch candidate ledger — cross-session recurrence. TRACKED on purpose.\n'
    printf '#\tA staged script is promoted only after a SECOND distinct session needs it.\n'
    printf '#\t  ./Scripts/session-script.sh list --promotable\n'
    printf '#\tColumns: id\tintent\tfirst_session\tlast_session\tsessions\tuses\tcmd_sha\tstatus\tpromoted_path\n'
  } > "$LEDGER"
}

slug_of() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//' | cut -c1-40
}
sha_of() { printf '%s' "$1" | shasum -a 256 | cut -c1-8; }
row_of() { awk -F'\t' -v i="$ID" '!/^#/ && $1==i' "$LEDGER" 2>/dev/null | head -1; }
field()  { printf '%s' "$1" | awk -F'\t' -v n="$2" '{print $n}'; }

case "$ACTION" in

add)
  [ -n "$INTENT" ] && [ -n "$CMD" ] || { printf 'session-script.sh: add needs --intent and --cmd\n' >&2; usage; }
  ensure_ledger
  ID=$(slug_of "$INTENT")
  [ -n "$ID" ] || { printf 'session-script.sh: intent produced an empty slug\n' >&2; exit 2; }
  sha=$(sha_of "$CMD")

  # Reuse first: a candidate that duplicates a registered script is not a candidate.
  if ./Scripts/find-script.sh "$INTENT" --min 70 >/dev/null 2>&1; then
    printf 'already registered — use it instead of staging a duplicate:\n'
    ./Scripts/find-script.sh "$INTENT" --min 70 | head -2
    exit 1
  fi

  mkdir -p "$STAGE_ROOT/$SESSION"
  staged="$STAGE_ROOT/$SESSION/$ID.sh"
  if [ ! -f "$staged" ]; then
    { printf '#!/usr/bin/env bash\n'
      printf '# staged candidate — session %s — intent: %s\n' "$SESSION" "$INTENT"
      printf '# Not registered. Promote with: ./Scripts/session-script.sh promote %s\n' "$ID"
      printf 'set -o pipefail\n'
      printf '%s\n' "$CMD"
    } > "$staged"
    chmod +x "$staged"
  fi

  existing=$(row_of)
  if [ -z "$existing" ]; then
    printf '%s\t%s\t%s\t%s\t1\t1\t%s\tstaged\t-\n' "$ID" "$INTENT" "$SESSION" "$SESSION" "$sha" >> "$LEDGER"
    printf 'staged\t%s\tsessions=1\t%s\n' "$ID" "$staged"
  else
    last=$(field "$existing" 4); sessions=$(field "$existing" 5); uses=$(field "$existing" 6)
    uses=$((uses + 1))
    # A distinct session is what promotion turns on, so only bump the session count when the
    # session id actually changed. Re-running inside one session must never earn a promotion.
    if [ "$last" != "$SESSION" ]; then sessions=$((sessions + 1)); fi
    awk -F'\t' -v OFS='\t' -v i="$ID" -v s="$SESSION" -v n="$sessions" -v u="$uses" \
      '!/^#/ && $1==i { $4=s; $5=n; $6=u } { print }' "$LEDGER" > "$LEDGER.tmp" && mv "$LEDGER.tmp" "$LEDGER"
    printf 'staged\t%s\tsessions=%s\tuses=%s\t%s\n' "$ID" "$sessions" "$uses" "$staged"
    [ "$sessions" -ge 2 ] && printf 'promotable — a second session needed this. Run: ./Scripts/session-script.sh promote %s\n' "$ID"
  fi
  exit 0
  ;;

list)
  [ -f "$LEDGER" ] || { printf 'no candidates yet\n' >&2; exit 1; }
  if [ "$PROMOTABLE" -eq 1 ]; then
    out=$(awk -F'\t' -v OFS='\t' '!/^#/ && $5>=2 && $8=="staged" {print $1,$5,$6,$8,$2}' "$LEDGER")
  else
    out=$(awk -F'\t' -v OFS='\t' '!/^#/ {print $1,$5,$6,$8,$2}' "$LEDGER")
  fi
  [ -n "$out" ] || { printf 'nothing%s\n' "$([ "$PROMOTABLE" -eq 1 ] && printf ' promotable')" >&2; exit 1; }
  printf '%s\n' "$out" | head -20
  exit 0
  ;;

show)
  [ -n "$ID" ] || usage
  r=$(row_of); [ -n "$r" ] || { printf 'session-script.sh: no candidate %s\n' "$ID" >&2; exit 1; }
  printf '%s\n' "$r" | awk -F'\t' '{printf "id            %s\nintent        %s\nfirst_session %s\nlast_session  %s\nsessions      %s\nuses          %s\nstatus        %s\n", $1,$2,$3,$4,$8,$6,$8}'
  find "$STAGE_ROOT" -name "$ID.sh" 2>/dev/null | sed 's/^/staged        /'
  exit 0
  ;;

drop)
  [ -n "$ID" ] || usage
  row_of >/dev/null || { printf 'session-script.sh: no candidate %s\n' "$ID" >&2; exit 1; }
  if [ "$APPLY" -eq 0 ]; then printf 'would drop %s (and its staged copies). Re-run with --apply\n' "$ID"; exit 0; fi
  awk -F'\t' -v i="$ID" '/^#/ || $1!=i' "$LEDGER" > "$LEDGER.tmp" && mv "$LEDGER.tmp" "$LEDGER"
  find "$STAGE_ROOT" -name "$ID.sh" -delete 2>/dev/null
  printf 'dropped\t%s\n' "$ID"
  exit 0
  ;;

promote)
  [ -n "$ID" ] || usage
  r=$(row_of); [ -n "$r" ] || { printf 'session-script.sh: no candidate %s\n' "$ID" >&2; exit 1; }
  intent=$(field "$r" 2); sessions=$(field "$r" 5); status=$(field "$r" 8)
  staged=$(find "$STAGE_ROOT" -name "$ID.sh" 2>/dev/null | head -1)
  target="Scripts/$ID.sh"
  promoted_count=$(awk -F'\t' '!/^#/ && $8=="promoted"' "$LEDGER" | wc -l | tr -d ' ')

  pass=0; fail=0
  gate() { # name, ok(0/1), detail
    if [ "$2" -eq 0 ]; then printf '  PASS  %-22s %s\n' "$1" "$3"; pass=$((pass+1))
    else printf '  FAIL  %-22s %s\n' "$1" "$3"; fail=$((fail+1)); fi
  }

  printf 'promotion gates for %s\n' "$ID"

  [ "$sessions" -ge 2 ] && gate cross-session 0 "$sessions distinct sessions" \
                        || gate cross-session 1 "only $sessions session — a one-off is not a capability"
  [ "$status" = "staged" ] && gate not-already 0 "status=staged" \
                           || gate not-already 1 "status=$status"
  [ -n "$staged" ] && [ -f "$staged" ] && gate staged-exists 0 "$staged" \
                   || gate staged-exists 1 "no staged file found under $STAGE_ROOT"
  [ ! -e "$target" ] && gate name-free 0 "$target" \
                     || gate name-free 1 "$target already exists"
  if [ -n "$staged" ] && grep -qE 'curl|wget|(^|[^a-z])nc |git +(push|commit)|sudo' "$staged" 2>/dev/null; then
    gate offline-safe 1 "body contains a network, commit or sudo call"
  else
    gate offline-safe 0 "no network, no commit, no sudo"
  fi
  if [ -n "$staged" ] && grep -qE 'xcodebuild|swift +(build|test)|simctl +boot' "$staged" 2>/dev/null; then
    gate no-compiler 1 "body invokes a compiler — must be emit-only, not promoted as callable (rule 2.12)"
  else
    gate no-compiler 0 "does not invoke a compiler"
  fi
  [ "$promoted_count" -lt "$PROMOTED_MAX" ] && gate under-cap 0 "$promoted_count/$PROMOTED_MAX" \
                                            || gate under-cap 1 "at cap $PROMOTED_MAX — prune first"

  printf '\n  %d passed, %d failed\n' "$pass" "$fail"
  [ "$fail" -gt 0 ] && { printf '\nnot promoted\n' >&2; exit 1; }

  if [ "$APPLY" -eq 0 ]; then
    printf '\nall gates green. Re-run with --apply to write %s\n' "$target"
    exit 0
  fi

  # Promote: the staged body gains a real #@ header so register-scripts.sh can see it, which is
  # what puts it in front of Claude. No skill prose is written — the registry row IS the skill.
  {
    printf '#!/usr/bin/env bash\n'
    printf '#@kind      tool\n'
    printf '#@platform  macos\n'
    printf '#@claude    call\n'
    printf '#@purpose   %s\n' "$intent"
    printf '#@usage     %s\n' "$ID.sh"
    printf '#@in        none\n'
    printf '#@out       stdout:see body\n'
    printf '#@exit      0=ok 1=nothing found 2=usage 3=tool missing\n'
    printf '#@effects   read-only\n'
    printf '#@when      %s\n' "$intent"
    printf '# Promoted from a session candidate after %s distinct sessions needed it.\n' "$sessions"
    printf '# Original intent: %s\n' "$intent"
    sed '1{/^#!/d;}' "$staged" | sed '/^# staged candidate/d; /^# Not registered/d'
  } > "$target"
  chmod +x "$target"

  awk -F'\t' -v OFS='\t' -v i="$ID" -v p="$target" '!/^#/ && $1==i { $8="promoted"; $9=p } { print }' \
    "$LEDGER" > "$LEDGER.tmp" && mv "$LEDGER.tmp" "$LEDGER"

  ./Scripts/claude-utils/register-scripts.sh >/dev/null 2>&1 \
    && printf '\npromoted\t%s\t%s\tregistry regenerated\n' "$ID" "$target" \
    || { printf '\npromoted %s but register-scripts.sh failed — fix the header\n' "$target" >&2; exit 1; }
  printf 'review the generated header before relying on it: %s\n' "$target"
  exit 0
  ;;

*) printf 'session-script.sh: unknown action %s\n' "$ACTION" >&2; usage ;;
esac
