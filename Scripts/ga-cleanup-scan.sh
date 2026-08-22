#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Gather every cleanup candidate this install carries — orphan module docs, skills that cannot fire, memory rules duplicated across levels, a missing or malformed FETCH-BASE stamp — each with the evidence and the reason it is a candidate. Decides nothing and deletes nothing.
#@usage     ga-cleanup-scan.sh [target-dir] [--memory|--docs|--skills|--index] [--tsv]
#@in        target:dir(default .) --memory/--docs/--skills/--index:flag(one class only; default all) --tsv:flag(machine-readable, no colour)
#@out       stdout:sections of CANDIDATE/KEEP/REFUSE rows as class,path,evidence,reason then a count; --tsv drops the prose
#@exit      0=scan completed (candidates found or not) 1=not a GenericArch install 2=usage
#@effects   read-only; offline; opens no network and writes nothing
#@when      what can I clean up|cleanup candidates|which skills cannot fire|duplicate memory rule|orphan module docs|orphaned index row|before clean-up-genericarch-extra-memory|token cost of this install
#
# The half of /clean-up-genericarch-extra-memory that is deterministic. Finding a candidate is
# evidence-gathering — greps and file tests — while DECIDING is judgement, and only the second half
# needs the model. Splitting them means the expensive half is a fixed cost paid once per run rather
# than a conversation, and the cheap half cannot be got wrong by a tired reader.
#
# Three rules it holds to, because each one was a real mistake:
#   1. A `:remote` MAP row is NOT a candidate. It names a surface that exists upstream and this
#      product did not take — that row is doing its job.
#   2. A `docs/` path that is not on disk is NOT a candidate. Reference docs are fetched on demand;
#      a missing one is a fetch instruction, and the FETCH-BASE line says where from.
#   3. Anything already tombstoned is NOT a candidate. It is decided. Re-proposing it is the exact
#      loop the tombstone exists to stop.
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/ga-lifecycle.sh
. "$HERE/ga-lifecycle.sh"

TARGET="."; ONLY=""; TSV=0
while [ $# -gt 0 ]; do
  case "$1" in
    --memory) ONLY=memory; shift ;;
    --docs)   ONLY=docs;   shift ;;
    --skills) ONLY=skills; shift ;;
    --index)  ONLY=index;  shift ;;
    --tsv)    TSV=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit "$GA_EX_OK" ;;
    -*) ga_die "unknown option: $1" "$GA_EX_USAGE" ;;
    *)  TARGET="$1"; shift ;;
  esac
done
[ -d "$TARGET" ] || ga_die "no such directory: $TARGET" "$GA_EX_USAGE"
TARGET="$(cd "$TARGET" && pwd)"
cd "$TARGET" || exit "$GA_EX_ERR"
[ -d "$GA_STATE_DIR" ] || ga_die "not a GenericArch install: no $GA_STATE_DIR/ in $TARGET" "$GA_EX_ERR"

n_cand=0
want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }
# class, path, evidence, reason — one row per finding, and the count is what the caller acts on.
row() {
  n_cand=$((n_cand + 1))
  if [ "$TSV" -eq 1 ]; then printf 'CANDIDATE\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
  else printf '  %sCANDIDATE%s  %-11s %s\n              %s%s — %s%s\n' \
       "$GA_YEL" "$GA_OFF" "$1" "$2" "$GA_DIM" "$3" "$4" "$GA_OFF"; fi
}
refuse() {
  if [ "$TSV" -eq 1 ]; then printf 'REFUSE\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
  else printf '  %sREFUSE%s     %-11s %s\n              %s%s — %s%s\n' \
       "$GA_GRN" "$GA_OFF" "$1" "$2" "$GA_DIM" "$3" "$4" "$GA_OFF"; fi
}
say() { [ "$TSV" -eq 1 ] || printf '%s\n' "$1"; }
# grep -c already prints 0 when it finds nothing, and then exits 1 — so `|| echo 0` appends a
# SECOND line and every arithmetic test on the result dies with "integer expression expected".
count() { c="$("$@" 2>/dev/null | tr -d " " | head -1)"; case "$c" in ""|*[!0-9]*) printf '0' ;; *) printf '%s' "$c" ;; esac; }
hdr() { [ "$TSV" -eq 1 ] || ga_hdr "$1"; }

MAP=".claude/MAP.tsv"
MANIFEST=""; for m in $(ga_manifest_find "$TARGET"); do MANIFEST="$m"; done

[ "$TSV" -eq 1 ] || {
  ga_hdr "── ga-cleanup-scan ────────────────────────────────────"
  printf '  target   %s\n' "$TARGET"
  printf '  version  %s\n' "$([ -n "$MANIFEST" ] && ga_manifest_version "$MANIFEST" || echo unknown)"
  ga_dim "  Read-only and offline. Every row is evidence; none of them is a decision."
  echo
}

# ── 1. module docs with no package behind them ─────────────────────────────
if want docs; then
  hdr "── module docs ────────────────────────────────────────"
  if [ ! -d docs/modules ]; then
    say "  none on disk — current installs fetch them on demand, which is correct"
  else
    for d in docs/modules/*.md; do
      [ -f "$d" ] || continue
      pkg="$(basename "$d" .md)"
      if [ -d "Packages/$pkg" ] || [ -d "Packages/Features/$pkg" ]; then
        refuse docs "$d" "Packages/$pkg exists" "the package it documents is here"
      elif ga_tombstoned "$TARGET" "$d"; then
        refuse docs "$d" "already tombstoned" "decided — a tombstone is not re-proposed"
      else
        row docs "$d" "no Packages/$pkg" "documents a package that does not exist here"
      fi
    done
  fi
fi

# ── 2. skills and commands that cannot fire ────────────────────────────────
# A skill costs its description in EVERY session, so one that cannot fire is a standing bill for
# nothing. What makes it unable to fire is structural, not a matter of taste: new-feature scaffolds
# Packages/Features, so with no Packages/ it produces something the app cannot consume.
if want skills; then
  hdr "── skills and commands ────────────────────────────────"
  for s in .claude/skills/*/; do
    [ -d "$s" ] || continue
    name="$(basename "$s")"
    case "$name" in
      new-feature)
        if [ -d Packages/Features ] || [ -d Packages ]; then
          refuse skills "$s" "Packages/ exists" "it can scaffold into this repo"
        else
          row skills "$s" "no Packages/" "scaffolds Packages/Features — nothing here can consume it"
        fi ;;
      style-guide)
        t=$(count grep -c '^| `' .claude/notes/STYLE-GUIDE.md)
        [ "$t" -gt 0 ] && refuse skills "$s" "$t token row(s)" "it governs registered tokens" \
                       || row skills "$s" "0 token rows in STYLE-GUIDE.md" "fires on nothing until tokens are registered" ;;
      rtl-support)
        r=$(find . -name '*.lproj' 2>/dev/null | grep -cE '/(ar|he|fa|ur)\.lproj' | tr -d ' ' | head -1); r=${r:-0}
        [ "${r:-0}" -gt 0 ] && refuse skills "$s" "$r RTL locale(s)" "an RTL language ships here" \
                            || row skills "$s" "no ar/he/fa/ur locale" "no RTL language ships here" ;;
      dark-light-mode)
        d=$(grep -rl '"dark"' --include='Contents.json' . 2>/dev/null | wc -l | tr -d ' '); d=${d:-0}
        [ "${d:-0}" -gt 0 ] && refuse skills "$s" "$d dark asset variant(s)" "dark mode is real here" \
                            || row skills "$s" "no dark asset variants" "nothing for it to check" ;;
      release-bump)
        row skills "$s" "release-workflow tool" "not code generation; belongs to a distributed package, not an app" ;;
      *) refuse skills "$s" "no structural blocker found" "judge it on use, not on structure" ;;
    esac
  done
fi

# ── 3. the FETCH-BASE stamp ────────────────────────────────────────────────
# Route health belongs to ga-init-scan.sh — it holds the must-be-local list and the fetchable rule,
# and a second implementation here would drift from it and then disagree with it. What that tool
# CANNOT see is a stamp that is present but malformed: it greps `^# FETCH-BASE:`, so a stamp written
# with a tab after the `#` reads as absent, and every docs/ row silently becomes unresolvable.
if want index; then
  hdr "── the FETCH-BASE stamp ───────────────────────────────"
  if [ ! -f "$MAP" ]; then
    say "  no .claude/MAP.tsv here"
  elif awk -F'\t' '/^# FETCH-BASE:/{found=1} END{exit !found}' "$MAP"; then
    refuse index "$MAP" "stamp well-formed" "docs/ rows resolve; ga-init-scan.sh reports the counts"
  elif grep -q 'FETCH-BASE' "$MAP"; then
    row index "$MAP" "stamp present but MALFORMED" "must be '# FETCH-BASE:<tab><url>' as line 1 — every tool greps that exact form"
  else
    row index "$MAP" "no stamp at all" "every docs/ row is unresolvable until one is added"
  fi
  say ""
  say "  Route counts are ga-init-scan.sh's to report, not this script's:"
  say "      ./Scripts/ga-init-scan.sh . --write   # route issues must be 0"
fi

# ── 4. memory duplicated across levels ─────────────────────────────────────
# A project-scoped machine-local memory adds NO reach over the repo itself, so a rule in both is
# pure duplication — and the machine-local copy is the one nobody else ever sees.
if want memory; then
  hdr "── memory levels ──────────────────────────────────────"
  ENT="/Library/Application Support/ClaudeCode/managed-settings.json"
  [ -f "$ENT" ] && refuse memory "$ENT" "enterprise level" "read-only — never a candidate"
  # The machine-local store is keyed on the directory Claude was STARTED in, which is often an
  # ancestor of the install root rather than the install root itself — an Xcode project one level
  # down from its checkout is the normal case. Deriving the slug from $TARGET alone finds nothing and
  # reports "no store" for a repo that has one, so try every ancestor.
  LOCAL_MEM=""
  d="$TARGET"
  while [ "$d" != "/" ]; do
    cand="$HOME/.claude/projects/$(printf '%s' "$d" | tr '/.' '--')/memory"
    [ -d "$cand" ] && { LOCAL_MEM="$cand"; break; }
    d="$(dirname "$d")"
  done
  if [ -n "$LOCAL_MEM" ]; then
    say "  machine-local store: $LOCAL_MEM"
    for f in "$LOCAL_MEM"/*.md; do
      [ -f "$f" ] || continue
      b="$(basename "$f")"; [ "$b" = "MEMORY.md" ] && continue
      slug="${b%.md}"
      # type: user is per-person and deliberately never committed — not duplication.
      if grep -q '^  type: user' "$f" 2>/dev/null || grep -q 'type: user' "$f" 2>/dev/null; then
        refuse memory "$b" "type: user" "per-person; committing it would push one dev's prefs on everyone"
      elif [ -f .claude/memory/INDEX.md ] && grep -q "$slug" .claude/memory/INDEX.md 2>/dev/null; then
        row memory "$b" "also in .claude/memory/INDEX.md" "duplicated — the in-repo copy has strictly more reach"
      else
        refuse memory "$b" "no in-repo counterpart" "not duplication; check it is still true instead"
      fi
    done
  else
    say "  no machine-local store for this target"
  fi
  # An in-repo memory with no index row is the other failure: present, and unfindable.
  if [ -f .claude/memory/INDEX.md ]; then
    for f in .claude/memory/*.md; do
      [ -f "$f" ] || continue
      b="$(basename "$f")"; [ "$b" = "INDEX.md" ] && continue
      grep -q "$b" .claude/memory/INDEX.md 2>/dev/null \
        || row memory ".claude/memory/$b" "no INDEX.md row" "unfindable — add the row or retire the file"
    done
  fi
fi

# ── summary ────────────────────────────────────────────────────────────────
if [ "$TSV" -eq 1 ]; then
  printf 'SUMMARY\tcandidates\t%d\n' "$n_cand"
else
  echo
  printf '%s───────────────────────────────────────────────────────%s\n' "$GA_BLD" "$GA_OFF"
  if [ "$n_cand" -eq 0 ]; then
    ga_ok "no cleanup candidates — nothing to retire"
    ga_dim "That is a useful result: it stops the next session going looking."
  else
    printf '%d candidate(s). %sNone of them is a decision.%s\n' "$n_cand" "$GA_BLD" "$GA_OFF"
    ga_dim "Retire one with:  ./Scripts/ga-remove.sh <path> --reason \"…\" --apply
  Ask per candidate; a decline is a judgement about relevance, not about the content being wrong."
  fi
fi
exit "$GA_EX_OK"
