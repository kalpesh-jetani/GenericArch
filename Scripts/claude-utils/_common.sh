#!/usr/bin/env bash
# Shared helpers for the CLAUDE.md task pipeline. SOURCED, never executed.
#
#   . "$(dirname "$0")/../claude-utils/_common.sh"
#
# Exists so the fifteen pipeline scripts share one definition of an error, one
# artifact layout, and one exit-code vocabulary. Fifteen copies of `die()` drift,
# and a pipeline whose phases disagree about what "failed" means cannot be run
# unattended.
#
# Portable to bash 3.2 (macOS system bash) — no associative arrays, no mapfile,
# no ${var^^}, no `&>>`. Same constraint as Scripts/check.sh.

# Guard against double-sourcing: run-task.sh sources this, then invokes phases
# that source it again as children. Harmless, but re-running the tty probe per
# phase is waste.
[ -n "${GA_COMMON_LOADED:-}" ] && return 0
GA_COMMON_LOADED=1

set -u

# ── Exit codes ─────────────────────────────────────────────────────────────
# A caller must be able to tell "this phase found problems" from "this phase
# could not run" from "this phase needs your approval". One code for all three
# is what makes a pipeline undebuggable.
EX_OK=0          # phase completed, nothing wrong
EX_ERR=1         # phase ran and found a real problem
EX_USAGE=2       # bad arguments — caller's fault, not the file's
EX_PRECOND=3     # a prior phase has not run, or its artifact is missing
EX_APPROVAL=4    # refusing to proceed without an explicit --approve

# ── Output ─────────────────────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; CYA=$'\033[36m'
  DIM=$'\033[2m'; BLD=$'\033[1m'; OFF=$'\033[0m'
else
  RED=''; YEL=''; GRN=''; CYA=''; DIM=''; BLD=''; OFF=''
fi

# die <message> [exit-code]
# Every failure path goes through here so no script exits silently on a
# condition another script would have reported.
die()  { printf '%s✗ %s%s\n' "$RED" "$1" "$OFF" >&2; exit "${2:-$EX_ERR}"; }
warn() { printf '%s⚠ %s%s\n' "$YEL" "$1" "$OFF" >&2; }
ok()   { printf '%s✓ %s%s\n' "$GRN" "$1" "$OFF"; }
info() { printf '  %s\n' "$1"; }
dim()  { printf '%s  %s%s\n' "$DIM" "$1" "$OFF"; }
hdr()  { printf '\n%s── %s%s\n' "$BLD" "$1" "$OFF"; }

# usage <exit-code> — scripts define usage_text(); this prints and exits.
usage() { usage_text >&2; exit "${1:-$EX_USAGE}"; }

now()   { date +%Y-%m-%dT%H:%M:%S; }
today() { date +%Y-%m-%d; }

# ── Locations ──────────────────────────────────────────────────────────────
# GA_HOME is the GenericArch checkout that owns these scripts — the tooling
# root. It is NOT the project being worked on: a task may target another repo's
# CLAUDE.md entirely, which is the whole point of the project registry.
ga_home() {
  if [ -n "${GA_HOME:-}" ]; then printf '%s\n' "$GA_HOME"; return 0; fi
  # Resolve from this file's own location: Scripts/claude-utils/_common.sh → up 2.
  ( cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd )
}

TASKS_ROOT="$(ga_home)/.claude/claude-tasks"
REGISTRY="$TASKS_ROOT/projects.tsv"

# task_dir <project> <task-id> — path only; does not create.
task_dir() { printf '%s/%s/%s\n' "$TASKS_ROOT" "$1" "$2"; }

# task_dir_ensure <project> <task-id> — path, created.
task_dir_ensure() {
  d="$(task_dir "$1" "$2")"
  mkdir -p "$d" || die "cannot create task dir: $d"
  printf '%s\n' "$d"
}

# ── Identifiers ────────────────────────────────────────────────────────────
# Project and task ids become path components. Anything that could escape the
# tasks root, or collide after normalisation, is rejected rather than sanitised
# — silently rewriting an id makes the next lookup miss.
slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//'
}

check_id() {
  case "$1" in
    ''|*/*|*..*|-*) die "invalid ${2:-id} '$1' — use letters, digits, dashes" "$EX_USAGE" ;;
  esac
  case "$1" in
    *[!a-zA-Z0-9._-]*) die "invalid ${2:-id} '$1' — use letters, digits, dashes" "$EX_USAGE" ;;
  esac
}

# ── KV artifacts ───────────────────────────────────────────────────────────
# Phase artifacts that carry named values are shell-sourceable KEY='value'
# files. Sourceable means the next phase reads them with `.` instead of parsing,
# and a human can cat one. Single-quote escaping is the only quoting rule.
kv_esc() { printf '%s' "$1" | sed "s/'/'\\\\''/g"; }

# kv_set <file> <KEY> <value> — idempotent; replaces an existing KEY.
kv_set() {
  _f="$1"; _k="$2"; _v="$3"
  [ -f "$_f" ] || : > "$_f"
  # Rewrite via temp so a crash mid-write cannot leave a half-file that the
  # next phase would source and act on.
  _t="$_f.tmp.$$"
  grep -v "^$_k=" "$_f" > "$_t" 2>/dev/null || : > "$_t"
  printf "%s='%s'\n" "$_k" "$(kv_esc "$_v")" >> "$_t"
  mv "$_t" "$_f" || die "cannot write $_f"
}

# kv_get <file> <KEY> — empty string when absent. Never sources the file.
kv_get() {
  [ -f "$1" ] || return 0
  sed -n "s/^$2='\(.*\)'$/\1/p" "$1" | tail -1 | sed "s/'\\\\''/'/g"
}

# ── Counting ───────────────────────────────────────────────────────────────
# `grep -c` prints 0 AND exits non-zero when nothing matches, so the obvious
# `$(grep -c … || echo 0)` emits "0\n0" — and every arithmetic expansion
# downstream then dies with "syntax error in expression". These wrappers always
# print exactly one integer, including for a missing file.
count_rows() {                                  # data rows in a TSV artifact
  [ -f "$1" ] || { printf '0'; return 0; }
  grep -cv -e '^#' -e '^[[:space:]]*$' "$1" 2>/dev/null || true
}

count_match() {                                 # lines of <file> matching <pattern>
  [ -f "$2" ] || { printf '0'; return 0; }
  grep -c -e "$1" "$2" 2>/dev/null || true
}

count_stdin() {                                 # non-blank lines on stdin
  grep -c . 2>/dev/null || true
}

# ── Phase state ────────────────────────────────────────────────────────────
# STATE.tsv is the pipeline's memory: which phase ran, when, and how it ended.
# run-task.sh reads it to answer "what is next" without re-running anything.
state_file() { printf '%s/STATE.tsv\n' "$(task_dir "$1" "$2")"; }

state_set() {
  _p="$1"; _t="$2"; _phase="$3"; _status="$4"; _note="${5:-}"
  _sf="$(state_file "$_p" "$_t")"
  _note="$(printf '%s' "$_note" | tr '\t\n' '  ')"
  if [ ! -f "$_sf" ]; then
    printf '# phase\tstatus\ttimestamp\tnote\n' > "$_sf"
  fi
  _tmp="$_sf.tmp.$$"
  grep -v "^$_phase	" "$_sf" > "$_tmp" 2>/dev/null || : > "$_tmp"
  printf '%s\t%s\t%s\t%s\n' "$_phase" "$_status" "$(now)" "$_note" >> "$_tmp"
  # Keep the header first, then phases in numeric order — a state file that
  # reads out of order is the one nobody trusts.
  { grep '^#' "$_tmp"; grep -v '^#' "$_tmp" | sort -t'	' -k1,1; } > "$_sf"
  rm -f "$_tmp"
}

state_get() {
  _sf="$(state_file "$1" "$2")"
  [ -f "$_sf" ] || return 0
  awk -F'\t' -v p="$3" '$1==p {print $2}' "$_sf" | tail -1
}

# ── Preconditions ──────────────────────────────────────────────────────────
# need_artifact <project> <task> <artifact-name> <producing-phase-hint>
# A phase that reads a missing artifact must say which phase to run, not just
# "file not found". Exit 3 so run-task.sh can distinguish it from a real fault.
need_artifact() {
  _f="$(task_dir "$1" "$2")/$3"
  [ -f "$_f" ] || die "missing $3 — run phase $4 first:
    ./Scripts/claude-workflows/run-task.sh $1 $2 $4" "$EX_PRECOND"
  printf '%s\n' "$_f"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1" "$EX_PRECOND"
}

# ── Project registry ───────────────────────────────────────────────────────
# projects.tsv columns: name  root  claude_md  test_cmd  source_glob
registry_row() {
  [ -f "$REGISTRY" ] || die "no project registry — run:
    ./Scripts/claude-utils/init-claude-env.sh --add <name> <path>" "$EX_PRECOND"
  awk -F'\t' -v n="$1" '$1==n {print; found=1} END {exit !found}' "$REGISTRY" \
    || die "unknown project '$1'. Registered:
$(awk -F'\t' '!/^#/ {printf "    %s\t%s\n", $1, $2}' "$REGISTRY")" "$EX_USAGE"
}

project_field() { registry_row "$1" | awk -F'\t' -v c="$2" '{print $c}'; }

# ── Markdown section inventory ─────────────────────────────────────────────
# The one piece of parsing more than one script needs, so it lives here rather
# than being reimplemented per phase with slightly different fence handling.
#
# md_sections <file>  →  level<TAB>start<TAB>end<TAB>slug<TAB>title
#
# `end` is the line before the NEXT heading of any level, so a parent section's
# extent stops at its first subsection. That is deliberate: phase 8 maps diff
# hunks to the narrowest enclosing heading, which is the useful one to report.
# Fenced code is skipped — `# not a heading` inside a bash block is not one.
md_sections() {
  awk '
    /^[ \t]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    /^#{1,6}[ \t]/ {
      match($0, /^#+/); lvl = RLENGTH
      title = $0
      sub(/^#+[ \t]+/, "", title)
      sub(/[ \t]+$/, "", title)
      sub(/[ \t]*#+[ \t]*$/, "", title)          # closed ATX: "## Title ##"
      slug = tolower(title)
      gsub(/[^a-z0-9 _-]/, "", slug)
      gsub(/ +/, "-", slug)
      n++
      L[n] = lvl; S[n] = NR; T[n] = title; G[n] = slug
    }
    END {
      for (i = 1; i <= n; i++) {
        end = (i < n) ? S[i+1] - 1 : NR
        printf "%d\t%d\t%d\t%s\t%s\n", L[i], S[i], end, G[i], T[i]
      }
    }
  ' "$1"
}

# md_symbols <file>  →  kind<TAB>line<TAB>section<TAB>symbol   (kind: api|component)
#
# The symbols a document names in inline code spans, attributed to their heading.
# Lives here, not in the audit phase, because phase 3 and phase 7 must classify
# identically while reading DIFFERENT versions of the file: phase 3 audits the
# document before the edit, phase 7 checks it after. Sharing one function is what
# stops phase 7 reporting a symbol that phase 5 has already deleted.
#
# Code fences are skipped — a backtick inside a fenced block is code, not a span.
md_symbols() {
  _mssec="${TMPDIR:-/tmp}/ga-symsec.$$"
  md_sections "$1" > "$_mssec"
  awk -F'\t' '
    FNR == NR { n++; S[n] = $2; E[n] = $3; T[n] = $5; next }

    function section_of(ln) {
      for (i = 1; i <= n; i++) if (S[i] <= ln && ln <= E[i]) return T[i]
      return "(preamble)"
    }

    /^[ \t]*(```|~~~)/ { fence = !fence; next }
    fence { next }

    {
      tmp = $0
      while (match(tmp, /`[^`]+`/)) {
        tok = substr(tmp, RSTART + 1, RLENGTH - 2)
        tmp = substr(tmp, RSTART + RLENGTH)
        kind = ""
        # func-like: has an argument list
        if (tok ~ /^[A-Za-z_][A-Za-z0-9_]*\(/) kind = "api"
        # type-like: UpperCamelCase carrying at least one lowercase letter
        else if (tok ~ /^[A-Z][A-Za-z0-9_]*$/ && tok ~ /[a-z]/)
          kind = (tok ~ /(View|Screen|Cell|Button|Card|Row|Modifier|Style|Bar|Sheet|Kit)$/) \
                 ? "component" : "api"
        # dotted member path, e.g. `URLSession.shared`
        else if (tok ~ /^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_]/) kind = "api"
        if (kind != "") printf "%s\t%d\t%s\t%s\n", kind, FNR, section_of(FNR), tok
      }
    }
  ' "$_mssec" "$1"
  rm -f "$_mssec"
}

# section_for_line <sections.tsv> <line-no> — narrowest heading containing it.
section_for_line() {
  awk -F'\t' -v want="$2" '
    $2 <= want && want <= $3 { print $5; found = 1; exit }
    END { if (!found) print "(preamble)" }
  ' "$1"
}
