#!/usr/bin/env bash
#@kind      tool
#@platform  any
#@claude    call
#@purpose   Gather every cleanup candidate this install carries — per-package docs left at the repo root, skills that cannot fire, memory rules duplicated across levels, a missing or malformed FETCH-BASE stamp — each with the evidence and the reason it is a candidate. Decides nothing and deletes nothing.
#@usage     ga-cleanup-scan.sh [target-dir] [--memory|--docs|--skills|--index] [--tsv]
#@in        target:dir(default .) --memory/--docs/--skills/--index:flag(one class only; default all) --tsv:flag(machine-readable, no colour)
#@out       stdout:sections of CANDIDATE/KEEP/REFUSE rows as class,path,evidence,reason then a count; --tsv drops the prose
#@exit      0=scan completed (candidates found or not) 1=not a GenericArch install 2=usage
#@effects   read-only; offline; opens no network and writes nothing
#@when      what can I clean up|cleanup candidates|which skills cannot fire|duplicate memory rule|stale package doc at the root|orphaned index row|before clean-up-genericarch-extra-memory|token cost of this install
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

# ── 1. per-module docs at the repo root ────────────────────────────────────
# This layer ships none: a root-level doc for a module a product may not have reads as current,
# describes code that is not there, and the index routes to it forever. A module's doc belongs
# beside its code. Any root-level one here came from an install older than that decision, or was
# written by hand — either way it is a candidate.
if want docs; then
  hdr "── per-module docs at the root ────────────────────────"
  if [ ! -d docs/modules ]; then
    say "  none — correct; a module's doc belongs beside its code"
  else
    for d in docs/modules/*.md; do
      [ -f "$d" ] || continue
      if ga_tombstoned "$TARGET" "$d"; then
        refuse docs "$d" "already tombstoned" "decided — a tombstone is not re-proposed"
      else
        row docs "$d" "root-level module doc" "move it beside the module's code, or decline it"
      fi
    done
  fi
fi

# ── 2. skills and commands that cannot fire ────────────────────────────────
# A skill costs its description in EVERY session, so one that cannot fire is a standing bill for
# nothing. This layer ships only tool-profile, which is stack-agnostic and always applicable; any
# other skill in the tree was authored by the product or left by an older install, and whether it
# can fire is a judgement about that product, not a structural fact this scanner can settle.
if want skills; then
  hdr "── skills and commands ────────────────────────────────"
  for s in .claude/skills/*/; do
    [ -d "$s" ] || continue
    refuse skills "$s" "no structural blocker found" "judge it on use, not on structure"
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
  elif grep -qE '^#[[:space:]]*FETCH-BASE' "$MAP"; then
    # Anchored on purpose. An unanchored 'FETCH-BASE' also matches the map's own header prose, which
    # explains the stamp to a reader — so the base repo reported its own documentation as a
    # malformed stamp. This form matches an attempted stamp ('#<tab>FETCH-BASE:') and not a sentence
    # mentioning one.
    row index "$MAP" "stamp present but MALFORMED" "must be '# FETCH-BASE:<tab><url>' as line 1 — every tool greps that exact form"
  elif ga_is_source_checkout "$TARGET"; then
    # The base has every docs/ file on disk, so there is nothing for a fetch base to resolve. Only
    # an install needs the stamp; install.sh adds it.
    refuse index "$MAP" "GenericArch source checkout" "no stamp needed — every docs/ row is local here"
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
  # ancestor of the install root rather than the install root itself — a project one level
  # down from its checkout is a common case. Deriving the slug from $TARGET alone finds nothing and
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
