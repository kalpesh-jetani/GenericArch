#!/usr/bin/env bash
#@kind      workflow
#@platform  macos
#@claude    call
#@purpose   PHASE 4 plan: validate each edit against the real document, flag cross-refs, normalise payloads.
#@usage     04-plan-claude-edits.sh <project> <task-id> (--edit 'SECTION|ACTION|OLD|NEW|NOTE'... | --from TSV | --template)
#@in        03-sections.tsv 01-task.env edit-specs:str  ACTION=replace|delete|append|insert-after|new-section  OLD/NEW=literal|@path
#@out       04-plan.tsv:tsv(section,action,old_payload,new_payload,occurrences,note) 04-outline.md:md 04-plan.env:kv 04-payload-N.old/.new
#@exit      0=ok 1=an edit was rejected 2=usage 3=missing-phase-3
#@effects   writes plan + payloads only; never touches the target
# PHASE 4 · PLAN — turn intent into a validated edit list: map each change to a
# real section, pre-flight every match, and flag cross-references that the edit
# would break.
#
#   ./Scripts/claude-workflows/04-plan-claude-edits.sh <project> <task-id> --template
#   ./Scripts/claude-workflows/04-plan-claude-edits.sh <project> <task-id> \
#       --edit 'Concurrency|replace|@old.txt|@new.txt|drop the DispatchQueue example'
#   ./Scripts/claude-workflows/04-plan-claude-edits.sh <project> <task-id> --from myplan.tsv
#
# An --edit is five |-separated fields:  SECTION|ACTION|OLD|NEW|NOTE
#   ACTION  replace · delete · append · insert-after · new-section
#   OLD/NEW literal single-line text, or @path to a file (use @file for anything
#           multi-line, or containing a | character)
#
# Writes 04-plan.tsv · 04-outline.md · 04-plan.env, and normalises every payload
# into 04-payload-N.{old,new} so phase 5 does exact-literal file reads only.
#
# This phase is where a wrong edit is supposed to die. It refuses a plan whose
# OLD text is absent, or ambiguous — matching twice is the classic way a
# str_replace lands in the wrong section, and it costs nothing to catch here.
. "$(dirname "$0")/../claude-utils/_common.sh"

usage_text() { usage_from "$0"; }

[ $# -ge 2 ] || usage
case "$1" in -h|--help) usage "$EX_OK" ;; esac

PROJECT="$1"; TASK_ID="$2"; shift 2
check_id "$PROJECT" "project name"; check_id "$TASK_ID" "task id"

TEMPLATE=0; FROM=''; EDIT_N=0
EDITS_RAW=''   # newline-separated; bash 3.2 has no arrays worth the trouble here
while [ $# -gt 0 ]; do
  case "$1" in
    --template) TEMPLATE=1; shift ;;
    --edit)     [ $# -ge 2 ] || die "--edit needs a spec" "$EX_USAGE"
                EDITS_RAW="$EDITS_RAW$2
"; EDIT_N=$((EDIT_N + 1)); shift 2 ;;
    --from)     [ $# -ge 2 ] || die "--from needs a path" "$EX_USAGE"
                [ -r "$2" ] || die "cannot read $2"
                FROM="$2"; shift 2 ;;
    -h|--help)  usage "$EX_OK" ;;
    *)          die "unknown argument: $1" "$EX_USAGE" ;;
  esac
done

TASK_ENV="$(need_artifact "$PROJECT" "$TASK_ID" 01-task.env 1)" || exit $?
FILE_ENV="$(need_artifact "$PROJECT" "$TASK_ID" 02-file.env 2)" || exit $?
DIR="$(task_dir "$PROJECT" "$TASK_ID")"
TARGET="$(kv_get "$FILE_ENV" TARGET)"
SECTIONS="$DIR/03-sections.tsv"
SYMBOLS="$DIR/03-symbols.tsv"

# Phase 3 is optional only when the target is new — there is nothing to audit.
TARGET_EXISTS="$(kv_get "$FILE_ENV" EXISTS)"
if [ "$TARGET_EXISTS" = 1 ] && [ ! -f "$SECTIONS" ]; then
  die "no section inventory — run phase 3 first:
    ./Scripts/claude-workflows/run-task.sh $PROJECT $TASK_ID 3" "$EX_PRECOND"
fi

PLAN="$DIR/04-plan.tsv"
OUTLINE="$DIR/04-outline.md"

# ── --template: emit a plan skeleton from the phase-1 hints ─────────────────
# So the pipeline can be driven without hand-writing TSV. The skeleton is
# deliberately invalid until payloads are filled in — a template that validated
# would get run by accident.
if [ "$TEMPLATE" -eq 1 ]; then
  TPL="$DIR/04-plan.template.tsv"
  {
    printf '# section\taction\told\tnew\tnote\n'
    printf '#\n# Fill in, then: 04-plan-claude-edits.sh %s %s --from %s\n' "$PROJECT" "$TASK_ID" "$TPL"
    printf '# OLD/NEW are literal text or @path. Actions: replace delete append insert-after new-section\n#\n'
    HINTS="$(kv_get "$TASK_ENV" SECTION_HINTS)"
    if [ -n "$HINTS" ]; then
      printf '%s' "$HINTS" | tr ',' '\n' | while IFS= read -r h; do
        [ -n "$h" ] || continue
        # Resolve the hint to a real heading when one matches, so the template
        # starts from the document rather than from the request's wording.
        real=$(awk -F'\t' -v h="$h" 'BEGIN{IGNORECASE=1} !/^#/ && index(tolower($5), tolower(h)) {print $5; exit}' "$SECTIONS" 2>/dev/null)
        printf '%s\treplace\t@FIXME.old\t@FIXME.new\tfrom hint: %s\n' "${real:-$h}" "$h"
      done
    else
      printf '%s\treplace\t@FIXME.old\t@FIXME.new\tno hint from phase 1 — name the section\n' 'SECTION-NAME'
    fi
  } > "$TPL"
  state_set "$PROJECT" "$TASK_ID" 4 template "awaiting payloads"
  hdr "Phase 4 · plan template"
  cat "$TPL"
  ok "wrote $TPL"
  dim "fill it in, then re-run with --from $TPL"
  exit "$EX_OK"
fi

# ── Gather edit specs ──────────────────────────────────────────────────────
if [ -n "$FROM" ]; then
  # A TSV plan file: tab-separated, comments and blanks skipped. Converted to
  # the same |-form as --edit so there is one validation path, not two.
  EDITS_RAW="$EDITS_RAW$(awk -F'\t' '!/^[ \t]*#/ && NF >= 2 {
    printf "%s|%s|%s|%s|%s\n", $1, $2, $3, $4, $5
  }' "$FROM")
"
fi
EDITS_RAW="$(printf '%s' "$EDITS_RAW" | grep -v '^[ 	]*$' || true)"
[ -n "$EDITS_RAW" ] || die "no edits given — pass --edit, --from, or --template to generate a skeleton" "$EX_USAGE"

need_cmd python3

printf '# section\taction\told_payload\tnew_payload\toccurrences\tnote\n' > "$PLAN"
: > "$OUTLINE"

N=0
# Appended to by the subshell loop below; read back after it.
EVENTS="$DIR/.events.$$"
: > "$EVENTS"

# resolve_payload <spec> <dest> — writes the payload file, returns 0 if there is
# content, 1 if the spec was empty (legitimate for append/delete's NEW field).
resolve_payload() {
  spec="$1"; dest="$2"
  case "$spec" in
    '') return 1 ;;
    @*) src="${spec#@}"
        [ -r "$src" ] || die "payload file not readable: $src" "$EX_USAGE"
        cp "$src" "$dest" || die "cannot write $dest"
        ;;
    *)  printf '%s\n' "$spec" > "$dest" ;;
  esac
  return 0
}

# count_literal <needle-file> <haystack-file> — exact substring occurrences.
# python3 rather than grep: the payload is literal text that may contain regex
# metacharacters and newlines, and grep would treat both as syntax.
count_literal() {
  python3 - "$1" "$2" <<'PY'
import sys
needle = open(sys.argv[1], encoding='utf-8').read()
hay = open(sys.argv[2], encoding='utf-8').read()
# A trailing newline on a single-line payload is an artifact of how it was
# written, not part of what the author meant to match.
if needle.endswith('\n') and needle.count('\n') == 1:
    needle = needle[:-1]
print(0 if not needle else hay.count(needle))
PY
}

printf '# Edit outline — %s/%s\n\n' "$PROJECT" "$TASK_ID" >> "$OUTLINE"
printf 'Target: `%s`\n\n' "$TARGET" >> "$OUTLINE"

# IFS-based field split; the payload-in-a-file design means no field needs to
# survive a newline, which is what makes this safe.
printf '%s\n' "$EDITS_RAW" | while IFS= read -r spec; do
  [ -n "$spec" ] || continue
  N=$((N + 1))

  SEC=$(printf '%s' "$spec"  | cut -d'|' -f1 | sed 's/^ *//;s/ *$//')
  ACT=$(printf '%s' "$spec"  | cut -d'|' -f2 | sed 's/^ *//;s/ *$//')
  OLD=$(printf '%s' "$spec"  | cut -d'|' -f3)
  NEW=$(printf '%s' "$spec"  | cut -d'|' -f4)
  NOTE=$(printf '%s' "$spec" | cut -d'|' -f5-)

  [ -n "$SEC" ] || { warn "edit $N: empty section — skipped"; continue; }

  case "$ACT" in
    replace|delete|append|insert-after|new-section) ;;
    '') die "edit $N ($SEC): no action given" "$EX_USAGE" ;;
    *)  die "edit $N ($SEC): unknown action '$ACT'
    valid: replace delete append insert-after new-section" "$EX_USAGE" ;;
  esac

  # ── the section must be real ───────────────────────────────────────────
  SEC_ROW=''
  if [ "$TARGET_EXISTS" = 1 ]; then
    SEC_ROW=$(awk -F'\t' -v s="$SEC" '!/^#/ && $5 == s {print; exit}' "$SECTIONS")
    if [ -z "$SEC_ROW" ]; then
      # Fall back to a substring match before failing — a caller naming "§6
      # Concurrency" when the heading is "Concurrency" is a near miss, not a
      # different intent.
      SEC_ROW=$(awk -F'\t' -v s="$SEC" '!/^#/ && index($5, s) {print; exit}' "$SECTIONS")
      if [ -n "$SEC_ROW" ]; then
        REAL=$(printf '%s' "$SEC_ROW" | cut -f5)
        warn "edit $N: \"$SEC\" matched section \"$REAL\" by substring"
        SEC="$REAL"
        printf 'warn\n' >> "$EVENTS"
      elif [ "$ACT" != new-section ]; then
        printf '%s✗ edit %d: no section "%s" in %s%s\n' "$RED" "$N" "$SEC" "$(basename "$TARGET")" "$OFF" >&2
        printf '%s    closest headings:%s\n' "$DIM" "$OFF" >&2
        awk -F'\t' '!/^#/ {print "      " $5}' "$SECTIONS" | head -8 >&2
        continue
      fi
    fi
  fi

  OLD_FILE=''; NEW_FILE=''; OCC='—'

  if resolve_payload "$OLD" "$DIR/04-payload-$N.old"; then OLD_FILE="$DIR/04-payload-$N.old"; fi
  if resolve_payload "$NEW" "$DIR/04-payload-$N.new"; then NEW_FILE="$DIR/04-payload-$N.new"; fi

  case "$ACT" in
    replace)
      [ -n "$OLD_FILE" ] || { printf '%s✗ edit %d (%s): replace needs OLD text%s\n' "$RED" "$N" "$SEC" "$OFF" >&2; continue; }
      [ -n "$NEW_FILE" ] || { printf '%s✗ edit %d (%s): replace needs NEW text (use delete to remove)%s\n' "$RED" "$N" "$SEC" "$OFF" >&2; continue; }
      ;;
    delete)
      [ -n "$OLD_FILE" ] || { printf '%s✗ edit %d (%s): delete needs OLD text%s\n' "$RED" "$N" "$SEC" "$OFF" >&2; continue; }
      ;;
    append|insert-after|new-section)
      [ -n "$NEW_FILE" ] || { printf '%s✗ edit %d (%s): %s needs NEW text%s\n' "$RED" "$N" "$SEC" "$ACT" "$OFF" >&2; continue; }
      ;;
  esac

  # ── pre-flight the match ───────────────────────────────────────────────
  if [ -n "$OLD_FILE" ] && [ "$TARGET_EXISTS" = 1 ]; then
    OCC=$(count_literal "$OLD_FILE" "$TARGET")
    if [ "$OCC" -eq 0 ]; then
      printf '%s✗ edit %d (%s): OLD text is not in the file — nothing would match%s\n' "$RED" "$N" "$SEC" "$OFF" >&2
      printf '%s    first line looked for: %s%s\n' "$DIM" "$(head -1 "$OLD_FILE" | cut -c1-70)" "$OFF" >&2
      continue
    elif [ "$OCC" -gt 1 ]; then
      printf '%s✗ edit %d (%s): OLD text matches %d times — ambiguous%s\n' "$RED" "$N" "$SEC" "$OCC" "$OFF" >&2
      printf '%s    extend it with surrounding context until it is unique%s\n' "$DIM" "$OFF" >&2
      continue
    fi
  fi

  # ── cross-references ───────────────────────────────────────────────────
  # Deleting or renaming a heading orphans every anchor link pointing at it.
  # Phase 6 would catch the broken link afterwards; naming it here means the
  # plan can be fixed before the edit rather than after.
  if [ "$ACT" = delete ] && [ -f "$SYMBOLS" ]; then
    SLUG=$(printf '%s' "$SEC_ROW" | cut -f4)
    if [ -n "$SLUG" ]; then
      REFS=$(awk -F'\t' -v a="#$SLUG" '$1=="link-anchor" && $4==a {print $2}' "$SYMBOLS" | tr '\n' ' ')
      if [ -n "$REFS" ]; then
        warn "edit $N: #$SLUG is linked from line(s) $REFS — those links would break"
        printf 'warn\n' >> "$EVENTS"
      fi
    fi
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$SEC" "$ACT" "${OLD_FILE:-—}" "${NEW_FILE:-—}" "$OCC" "$NOTE" >> "$PLAN"

  # ── outline ────────────────────────────────────────────────────────────
  {
    printf '## %d. %s — %s\n\n' "$N" "$ACT" "$SEC"
    [ -n "$NOTE" ] && printf '%s\n\n' "$NOTE"
    if [ -n "$OLD_FILE" ]; then
      printf '```diff\n'
      sed 's/^/- /' "$OLD_FILE" | head -20
      [ -n "$NEW_FILE" ] && sed 's/^/+ /' "$NEW_FILE" | head -20
      printf '```\n\n'
    elif [ -n "$NEW_FILE" ]; then
      printf '```diff\n'
      sed 's/^/+ /' "$NEW_FILE" | head -20
      printf '```\n\n'
    fi
  } >> "$OUTLINE"
done

# The loop body runs in a subshell, so nothing it assigned to a variable
# survives here. Blockers are therefore DERIVED — every attempted edit that did
# not reach the plan was rejected — and warnings are counted from the events file
# the loop appended to. Deriving is more robust than counting: a future `continue`
# added without a matching counter bump cannot make the two disagree.
PLANNED=$(count_rows "$PLAN")
ATTEMPTED=$(printf '%s\n' "$EDITS_RAW" | count_stdin)
B=$((ATTEMPTED - PLANNED))
W=$(count_match '^warn' "$EVENTS")
rm -f "$EVENTS"

ENV="$DIR/04-plan.env"
: > "$ENV"
kv_set "$ENV" PLANNED   "$PLANNED"
kv_set "$ENV" ATTEMPTED "$ATTEMPTED"
kv_set "$ENV" BLOCKED   "$B"
kv_set "$ENV" WARNINGS  "$W"
kv_set "$ENV" TARGET    "$TARGET"
kv_set "$ENV" DIGEST    "$(kv_get "$FILE_ENV" DIGEST)"

hdr "Phase 4 · plan — $PLANNED edit(s)"
if [ "$PLANNED" -gt 0 ]; then
  awk -F'\t' '!/^#/ {printf "  %-12s %-28s %s\n", $2, substr($1,1,28), $6}' "$PLAN"
fi

if [ "$B" -gt 0 ]; then
  state_set "$PROJECT" "$TASK_ID" 4 blocked "$B of $ATTEMPTED rejected"
  die "$B of $ATTEMPTED edit(s) rejected — the plan is incomplete.
    Fix the specs above and re-run. Phase 5 will not apply a partial plan." "$EX_ERR"
fi

state_set "$PROJECT" "$TASK_ID" 4 done "$PLANNED edits"
ok "wrote 04-plan.tsv · 04-outline.md · 04-plan.env"
info "outline   $OUTLINE"
[ "$W" -gt 0 ] && dim "$W warning(s) above — not blocking, but read them"
dim "next: run-task.sh $PROJECT $TASK_ID 5 --approve   (phase 5 refuses without it)"
