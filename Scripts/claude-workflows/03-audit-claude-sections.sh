#!/usr/bin/env bash
#@kind      workflow
#@platform  macos
#@claude    call
#@purpose   PHASE 3 audit: inventory sections, symbols, links; detect duplicate headings and anchors.
#@usage     03-audit-claude-sections.sh <project> <task-id> [--verbose]
#@in        02-file.env project:str task-id:str
#@out       03-sections.tsv:tsv(level,start,end,slug,title) 03-symbols.tsv:tsv(kind,line,section,symbol) 03-issues.tsv:tsv(kind,detail,lines) 03-audit.env:kv
#@exit      0=ok always when readable 2=usage 3=missing-phase-2
#@effects   read-only
# PHASE 3 · AUDIT — inventory the target document: sections, API references,
# components, async patterns, links; detect duplicate headings and anchors.
#
#   ./Scripts/claude-workflows/03-audit-claude-sections.sh <project> <task-id>
#   ./Scripts/claude-workflows/03-audit-claude-sections.sh <project> <task-id> --verbose
#
# Writes 03-sections.tsv · 03-symbols.tsv · 03-issues.tsv · 03-audit.env.
#
# Read-only. Everything is emitted as TSV so the next phase (and a human) greps
# a row instead of re-parsing the document — the whole reason the pipeline keeps
# artifacts at all. The default output is a count summary; the rows live in the
# files.
. "$(dirname "$0")/../claude-utils/_common.sh"

usage_text() { usage_from "$0"; }

[ $# -ge 2 ] || usage
case "$1" in -h|--help) usage "$EX_OK" ;; esac

PROJECT="$1"; TASK_ID="$2"; shift 2
check_id "$PROJECT" "project name"; check_id "$TASK_ID" "task id"

VERBOSE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --verbose|-v) VERBOSE=1; shift ;;
    -h|--help)    usage "$EX_OK" ;;
    *)            die "unknown argument: $1" "$EX_USAGE" ;;
  esac
done

FILE_ENV="$(need_artifact "$PROJECT" "$TASK_ID" 02-file.env 2)" || exit $?
DIR="$(task_dir "$PROJECT" "$TASK_ID")"
TARGET="$(kv_get "$FILE_ENV" TARGET)"
[ "$(kv_get "$FILE_ENV" EXISTS)" = 1 ] || die "target does not exist — nothing to audit:
    $TARGET
    A new file has no sections; skip to phase 4 and plan a new-section edit." "$EX_PRECOND"
[ -r "$TARGET" ] || die "target became unreadable since phase 2: $TARGET" "$EX_PRECOND"

SECTIONS="$DIR/03-sections.tsv"
SYMBOLS="$DIR/03-symbols.tsv"
ISSUES="$DIR/03-issues.tsv"

# ── Sections ───────────────────────────────────────────────────────────────
printf '# level\tstart\tend\tslug\ttitle\n' > "$SECTIONS"
md_sections "$TARGET" >> "$SECTIONS"
N_SECTIONS=$(count_rows "$SECTIONS")
MAX_DEPTH=$(awk -F'\t' '!/^#/ {if ($1 > m) m = $1} END {print m + 0}' "$SECTIONS")

# ── Symbols, per section ───────────────────────────────────────────────────
# One awk pass over both files: sections first (to build the line→section map),
# then the document. Attributing every symbol to its heading is what lets phase
# 4 answer "which sections does this edit touch" without a second scan.
printf '# kind\tline\tsection\tsymbol\n' > "$SYMBOLS"
awk -F'\t' '
  # ---- pass 1: the section map
  FNR == NR {
    if ($0 !~ /^#/) { n++; S[n] = $2; E[n] = $3; T[n] = $5 }
    next
  }
  # ---- pass 2: the document
  FNR == 1 { fence = 0; lang = "" }

  function section_of(ln) {
    for (i = 1; i <= n; i++) if (S[i] <= ln && ln <= E[i]) return T[i]
    return "(preamble)"
  }
  function emit(kind, sym) { printf "%s\t%d\t%s\t%s\n", kind, FNR, section_of(FNR), sym }

  # Fenced blocks: record the language on the opening marker.
  /^[ \t]*(```|~~~)/ {
    if (!fence) { lang = $0; sub(/^[ \t]*(```|~~~)[ \t]*/, "", lang); emit("code", (lang == "" ? "(none)" : lang)) }
    fence = !fence
    next
  }

  {
    line = $0

    # Concurrency vocabulary is scanned everywhere, fences INCLUDED — the code
    # block is precisely where a document demonstrates its concurrency model, so
    # skipping fences here would report a doc full of actors as having none.
    # The last group is what CLAUDE.md §1 forbids in new code; a doc that still
    # teaches it is the doc drifting behind the rules, which is worth a row.
    if (line ~ /(^|[^A-Za-z])async let([^A-Za-z]|$)/) emit("async", "async let")
    else if (line ~ /(^|[^A-Za-z])async([^A-Za-z]|$)/) emit("async", "async")
    if (line ~ /(^|[^A-Za-z])await([^A-Za-z]|$)/)      emit("async", "await")
    if (line ~ /TaskGroup/)                            emit("async", "TaskGroup")
    if (line ~ /Task[ \t]*\{/)                         emit("async", "Task {")
    if (line ~ /@MainActor/)                           emit("async", "@MainActor")
    # "actors" and "actor" both count — a rule stated in prose is usually plural.
    if (line ~ /(^|[^A-Za-z])actors?([^A-Za-z]|$)/)    emit("async", "actor")
    if (line ~ /Sendable/)                             emit("async", "Sendable")
    if (line ~ /AsyncStream|AsyncSequence/)            emit("async", "AsyncStream")
    if (line ~ /DispatchQueue/)                        emit("legacy-async", "DispatchQueue")
    if (line ~ /completion[ \t]*:/)                    emit("legacy-async", "completion:")
    if (line ~ /(^|[^A-Za-z])Combine([^A-Za-z]|$)/)    emit("legacy-async", "Combine")
    if (line ~ /AnyPublisher|PassthroughSubject/)      emit("legacy-async", "Combine publisher")

    # Links, split by kind — phase 6 resolves them, this only counts them.
    if (!fence) {
      tmp = line
      while (match(tmp, /\]\([^)]+\)/)) {
        dest = substr(tmp, RSTART + 2, RLENGTH - 3)
        tmp = substr(tmp, RSTART + RLENGTH)
        if (dest ~ /^https?:/)     emit("link-external", dest)
        else if (dest ~ /^#/)      emit("link-anchor", dest)
        else                       emit("link-internal", dest)
      }
    }
  }
' "$SECTIONS" "$TARGET" >> "$SYMBOLS"

# api/component rows come from the shared classifier so phase 7 cannot disagree
# with this phase about what counts as a symbol. Merged in line order.
md_symbols "$TARGET" >> "$SYMBOLS"
{ grep '^#' "$SYMBOLS"; grep -v '^#' "$SYMBOLS" | sort -t'	' -k2,2n -s; } > "$SYMBOLS.tmp" \
  && mv "$SYMBOLS.tmp" "$SYMBOLS"

count_kind() { awk -F'\t' -v k="$1" '$1==k' "$SYMBOLS" | wc -l | tr -d ' '; }

N_API=$(count_kind api)
N_COMPONENT=$(count_kind component)
N_ASYNC=$(count_kind async)
N_LEGACY=$(count_kind legacy-async)
N_CODE=$(count_kind code)
N_LINK_EXT=$(count_kind link-external)
N_LINK_INT=$(count_kind link-internal)
N_LINK_ANC=$(count_kind link-anchor)

# ── Issues ─────────────────────────────────────────────────────────────────
# Duplicate SLUGS are the one that bites: two headings normalising to the same
# anchor make every `[x](#that-anchor)` link silently ambiguous, and which one
# a renderer picks is not defined. Duplicate titles at the same level are a
# softer smell (a section that grew a twin instead of being extended).
printf '# kind\tdetail\tlines\n' > "$ISSUES"

awk -F'\t' '!/^#/ {c[$4]++; if (c[$4] == 1) first[$4] = $2; else lines[$4] = lines[$4] " " $2}
  END {for (s in c) if (c[s] > 1) printf "duplicate-anchor\t#%s (%d headings)\t%s%s\n", s, c[s], first[s], lines[s]}
' "$SECTIONS" >> "$ISSUES"

awk -F'\t' '!/^#/ {k = $1 "|" $5; c[k]++; if (c[k] == 1) first[k] = $2; else lines[k] = lines[k] " " $2}
  END {for (k in c) if (c[k] > 1) {split(k, p, "|"); printf "duplicate-title\th%s \"%s\" (%d)\t%s%s\n", p[1], p[2], c[k], first[k], lines[k]}}
' "$SECTIONS" >> "$ISSUES"

# A heading that jumps more than one level (h2 → h4) breaks outline tools and
# screen-reader navigation both.
awk -F'\t' '!/^#/ {if (prev && $1 > prev + 1) printf "heading-jump\th%d → h%d at \"%s\"\t%s\n", prev, $1, $5, $2; prev = $1}' \
  "$SECTIONS" >> "$ISSUES"

# Unbalanced code fences make everything after them render as code.
FENCE_N=$(count_match '^[ 	]*\(```\|~~~\)' "$TARGET")
if [ $((FENCE_N % 2)) -ne 0 ]; then
  printf 'unbalanced-fence\t%s fence markers (odd)\t—\n' "$FENCE_N" >> "$ISSUES"
fi

# An empty section is usually a heading someone added and never filled.
awk -F'\t' '!/^#/ {if ($3 - $2 < 1) printf "empty-section\t\"%s\"\t%s\n", $5, $2}' "$SECTIONS" >> "$ISSUES"

N_ISSUES=$(count_rows "$ISSUES")
N_DUP_ANCHOR=$(count_match '^duplicate-anchor' "$ISSUES")

ENV="$DIR/03-audit.env"
: > "$ENV"
kv_set "$ENV" TARGET        "$TARGET"
kv_set "$ENV" AUDITED       "$(now)"
kv_set "$ENV" SECTIONS      "$N_SECTIONS"
kv_set "$ENV" MAX_DEPTH     "$MAX_DEPTH"
kv_set "$ENV" API_REFS      "$N_API"
kv_set "$ENV" COMPONENTS    "$N_COMPONENT"
kv_set "$ENV" ASYNC_REFS    "$N_ASYNC"
kv_set "$ENV" LEGACY_ASYNC  "$N_LEGACY"
kv_set "$ENV" CODE_BLOCKS   "$N_CODE"
kv_set "$ENV" LINKS_EXT     "$N_LINK_EXT"
kv_set "$ENV" LINKS_INT     "$N_LINK_INT"
kv_set "$ENV" LINKS_ANCHOR  "$N_LINK_ANC"
kv_set "$ENV" ISSUES        "$N_ISSUES"
kv_set "$ENV" DUP_ANCHORS   "$N_DUP_ANCHOR"

state_set "$PROJECT" "$TASK_ID" 3 done "$N_SECTIONS sections, $N_ISSUES issues"

hdr "Phase 3 · audit — $(basename "$TARGET")"
info "sections     $N_SECTIONS (max depth h$MAX_DEPTH)"
info "code blocks  $N_CODE"
info "symbols      $N_API api · $N_COMPONENT components"
info "concurrency  $N_ASYNC modern$([ "$N_LEGACY" -gt 0 ] && printf ' · %s LEGACY (DispatchQueue/completion/Combine)' "$N_LEGACY")"
info "links        $N_LINK_INT internal · $N_LINK_ANC anchor · $N_LINK_EXT external"

if [ "$N_ISSUES" -gt 0 ]; then
  hdr "issues ($N_ISSUES)"
  awk -F'\t' -v d="$DIM" -v o="$OFF" \
    '!/^#/ {printf "  %-18s %s  %s(lines %s)%s\n", $1, $2, d, $3, o}' "$ISSUES"
fi

if [ "$VERBOSE" -eq 1 ]; then
  hdr "sections"
  awk -F'\t' -v d="$DIM" -v o="$OFF" \
    '!/^#/ {printf "  %*s%s %s(%s-%s, #%s)%s\n", ($1-1)*2, "", $5, d, $2, $3, $4, o}' "$SECTIONS"
fi

[ "$N_LEGACY" -gt 0 ] && warn "$N_LEGACY legacy-concurrency reference(s) — CLAUDE.md §1 forbids these in new
    code. If the doc still teaches them, the doc is behind the rules:
      grep '^legacy-async' $SYMBOLS"

ok "wrote 03-sections.tsv · 03-symbols.tsv · 03-issues.tsv · 03-audit.env"
dim "next: run-task.sh $PROJECT $TASK_ID 4"

# Always exit 0 when the file could be read. The issues above describe the
# document as it already was — they are findings for the planner, not failures of
# this phase. Exiting non-zero would abort `run-task.sh all` on any document that
# already had a duplicate heading, which is most of them.
exit "$EX_OK"
