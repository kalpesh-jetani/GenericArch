#!/usr/bin/env bash
#@kind      workflow
#@platform  macos
#@claude    call
#@purpose   PHASE 1 intake: classify a request and record it verbatim.
#@usage     01-parse-claude-task.sh <project> <task-id> (--text STR|--file PATH|-) [--type T] [--target PATH] [--sections CSV]
#@in        project:str task-id:str request:str|path|stdin
#@out       01-task.env:kv(TASK_TYPE,TARGET,SECTION_HINTS,TASK_SCOPE) 01-request.txt:text
#@exit      0=ok 2=usage
#@effects   writes task dir
# PHASE 1 · INTAKE — extract task type, scope, target document, affected sections
# from a request in the user's own words.
#
#   ./Scripts/claude-workflows/01-parse-claude-task.sh <project> <task-id> --text "<request>"
#   ./Scripts/claude-workflows/01-parse-claude-task.sh <project> <task-id> --file req.txt
#   cat req.txt | ./Scripts/claude-workflows/01-parse-claude-task.sh <project> <task-id> -
#
#   --type <t>       override the detected type
#   --target <path>  edit a document other than the project's CLAUDE.md
#   --sections "a,b" state the affected sections instead of letting phase 4 infer them
#
# Writes 01-task.env (shell-sourceable) and 01-request.txt (the request VERBATIM).
# The verbatim copy is the point: every later phase re-reads intent from one
# recorded sentence rather than from a paraphrase that has drifted three phases
# deep. Classification here is a HINT — phase 4 matches these tokens against the
# document's real headings and is where a wrong guess gets caught.
. "$(dirname "$0")/../claude-utils/_common.sh"

usage_text() { usage_from "$0"; }

[ $# -ge 2 ] || usage
case "$1" in -h|--help) usage "$EX_OK" ;; esac

PROJECT="$1"; TASK_ID="$2"; shift 2
check_id "$PROJECT" "project name"
check_id "$TASK_ID" "task id"

REQUEST=''; GOT_REQUEST=0; TYPE_OVERRIDE=''; TARGET_OVERRIDE=''; SECTIONS_OVERRIDE=''
while [ $# -gt 0 ]; do
  case "$1" in
    --text)     [ $# -ge 2 ] || die "--text needs a value" "$EX_USAGE"
                REQUEST="$2"; GOT_REQUEST=1; shift 2 ;;
    --file)     [ $# -ge 2 ] || die "--file needs a path" "$EX_USAGE"
                [ -r "$2" ] || die "cannot read $2"
                REQUEST="$(cat "$2")"; GOT_REQUEST=1; shift 2 ;;
    -)          REQUEST="$(cat)"; GOT_REQUEST=1; shift ;;
    --type)     [ $# -ge 2 ] || die "--type needs a value" "$EX_USAGE"
                TYPE_OVERRIDE="$2"; shift 2 ;;
    --target)   [ $# -ge 2 ] || die "--target needs a path" "$EX_USAGE"
                TARGET_OVERRIDE="$2"; shift 2 ;;
    --sections) [ $# -ge 2 ] || die "--sections needs a value" "$EX_USAGE"
                SECTIONS_OVERRIDE="$2"; shift 2 ;;
    -h|--help)  usage "$EX_OK" ;;
    *)          die "unknown argument: $1" "$EX_USAGE" ;;
  esac
done

[ "$GOT_REQUEST" -eq 1 ] || die "no request given — pass --text, --file or -" "$EX_USAGE"
[ -n "$(printf '%s' "$REQUEST" | tr -d '[:space:]')" ] || die "the request is empty" "$EX_USAGE"

# The project must be registered before a task can target it: the registry is
# what supplies the CLAUDE.md path, and inventing one here would let a typo
# create a task pointed at a file that does not exist.
require_project "$PROJECT"
ROOT="$(project_field "$PROJECT" 2)"
TARGET="$(project_field "$PROJECT" 3)"
[ -n "$TARGET_OVERRIDE" ] && TARGET="$TARGET_OVERRIDE"

DIR="$(task_dir_ensure "$PROJECT" "$TASK_ID")"
printf '%s\n' "$REQUEST" > "$DIR/01-request.txt"

# ── Classify ───────────────────────────────────────────────────────────────
# Lowercased, punctuation flattened, so "API refs." and "api ref" match alike.
NORM="$(printf '%s' "$REQUEST" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9§' ' ')"

has() { case " $NORM " in *" $1 "*) return 0 ;; esac; return 1; }
has_any() { for w in $1; do has "$w" && return 0; done; return 1; }

MATCHED=''
add_match() { MATCHED="$MATCHED $1"; }

has_any "link links anchor anchors href broken 404 crossref"        && add_match fix-links
has_any "format formatting lint whitespace indentation tidy style"  && add_match reformat
has_any "api apis endpoint endpoints signature signatures protocol" && add_match update-api-refs
has_any "component components view views designsystem widget"       && add_match update-components
has_any "async await concurrency actor mainactor sendable task"     && add_match async-patterns
has_any "feature screen scaffold module package"                    && add_match feature
has_any "remove delete drop strip deprecate obsolete"               && add_match remove-section
has_any "add new introduce document create append"                  && add_match add-section
has_any "update change edit revise fix correct clarify rewrite"     && add_match update-section

# Most specific wins. A request that says "fix the broken links in the API
# section" is a link task, not an API task — the narrower repair is what the
# edit actually is, and phase 6 is what verifies it.
TASK_TYPE=''
for candidate in fix-links reformat async-patterns update-api-refs update-components \
                 feature remove-section add-section update-section; do
  case "$MATCHED" in *" $candidate"*) TASK_TYPE="$candidate"; break ;; esac
done
[ -n "$TYPE_OVERRIDE" ] && TASK_TYPE="$TYPE_OVERRIDE"
[ -n "$TASK_TYPE" ] || TASK_TYPE=unknown

# ── Section hints ──────────────────────────────────────────────────────────
# Three signals, in descending reliability: an explicit §number, a quoted or
# backticked phrase, then nothing. Phase 4 resolves these against real headings;
# guessing from bare prose here would produce confident nonsense.
if [ -n "$SECTIONS_OVERRIDE" ]; then
  HINTS="$(printf '%s' "$SECTIONS_OVERRIDE" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$')"
else
  HINTS="$(
    printf '%s' "$REQUEST" | grep -o '§[0-9][0-9.]*' 2>/dev/null
    printf '%s' "$REQUEST" | sed -n 's/.*`\([^`]\{2,\}\)`.*/\1/p' 2>/dev/null
    printf '%s' "$REQUEST" | sed -n 's/.*"\([^"]\{2,\}\)".*/\1/p' 2>/dev/null
  )"
fi
HINT_CSV="$(printf '%s' "$HINTS" | grep -v '^$' | sort -u | tr '\n' ',' | sed 's/,$//')"
HINT_N=$(printf '%s' "$HINTS" | count_stdin)

# Scope: the request's first sentence, capped. Enough to identify the task in a
# status listing without re-reading the whole request.
SCOPE="$(printf '%s' "$REQUEST" | tr '\n' ' ' | sed 's/\([.!?]\).*/\1/' | cut -c1-160)"

ENV="$DIR/01-task.env"
: > "$ENV"
kv_set "$ENV" PROJECT      "$PROJECT"
kv_set "$ENV" TASK_ID      "$TASK_ID"
kv_set "$ENV" CREATED      "$(now)"
kv_set "$ENV" TASK_TYPE    "$TASK_TYPE"
kv_set "$ENV" TASK_TYPES   "$(printf '%s' "$MATCHED" | sed 's/^ //;s/ /,/g')"
kv_set "$ENV" TASK_SCOPE   "$SCOPE"
kv_set "$ENV" PROJECT_ROOT "$ROOT"
kv_set "$ENV" TARGET       "$TARGET"
kv_set "$ENV" TARGET_IS_OVERRIDE "$([ -n "$TARGET_OVERRIDE" ] && echo 1 || echo 0)"
kv_set "$ENV" SECTION_HINTS "$HINT_CSV"
kv_set "$ENV" REQUEST_FILE  "$DIR/01-request.txt"

state_set "$PROJECT" "$TASK_ID" 1 done "$TASK_TYPE"

hdr "Phase 1 · intake — $PROJECT/$TASK_ID"
info "type      $TASK_TYPE$([ -n "$TYPE_OVERRIDE" ] && printf ' (overridden)')"
[ -n "$MATCHED" ] && dim "also matched:$(printf '%s' "$MATCHED" | sed "s/ $TASK_TYPE//")"
info "target    $TARGET$([ -n "$TARGET_OVERRIDE" ] && printf ' (override)')"
info "scope     $SCOPE"
if [ "$HINT_N" -gt 0 ]; then
  info "sections  $HINT_CSV"
else
  dim "no section hint in the request — phase 4 will need --edit to say where"
fi

if [ "$TASK_TYPE" = unknown ]; then
  warn "type is 'unknown' — no keyword matched. Re-run with --type, or phase 4 will have
    nothing to plan from. Valid: add-section update-section remove-section fix-links
    reformat update-api-refs update-components async-patterns feature"
fi

ok "wrote $(basename "$ENV")"
dim "next: run-task.sh $PROJECT $TASK_ID 2"
