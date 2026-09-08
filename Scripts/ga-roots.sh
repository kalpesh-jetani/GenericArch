#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Find every GenericArch root in a checkout, report how far each got, and recommend which to keep. Decides nothing and removes nothing.
#@usage     ga-roots.sh [checkout-dir] [--tsv]
#@in        checkout:dir(default .) --tsv:flag(machine-readable rows)
#@out       stdout:one row per root with manifest versions, last step reached and a KEEP/RETIRE recommendation, then the exact commands to retire
#@exit      0=one root, or none 1=more than one root — a decision is pending 2=usage
#@effects   read-only; never opens the network
#@when      two install roots|which root do I keep|consolidate genericarch roots|already installed at another root|second root refused my install|nested install
#
# The missing half of the second-root guard. install.sh and ga-sync-scan.sh both refuse when a
# checkout has two roots, and both are right to — a sync would update one and leave the other
# shadowing it. Neither could say WHICH to keep, so the refusal had no next step: install.sh offered
# "install into that root instead" and ga-sync-scan.sh said consolidating "is its own decision".
# A real checkout hit exactly that and had nowhere to go.
#
# So: classify. A root that reached `ready` with one manifest is the live one; a root carrying two
# manifests and stuck at `install` is residue from installs that were never removed. That is a
# judgement a script can make from the ledger, and it is the judgement the operator was missing.
#
# It does NOT retire anything. Removing a root is uninstall.sh's job, per root, with its manifest as
# the authority — that is what proves ownership before deleting, and no shortcut here should bypass
# it. What this prints is the command to run.
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/ga-lifecycle.sh
. "$HERE/ga-lifecycle.sh"

ROOT="."; TSV=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tsv)     TSV=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit "$GA_EX_OK" ;;
    -*)        ga_die "unknown option: $1" "$GA_EX_USAGE" ;;
    *)         ROOT="$1"; shift ;;
  esac
done
[ -d "$ROOT" ] || ga_die "no such directory: $ROOT" "$GA_EX_USAGE"
ROOT="$(cd "$ROOT" && pwd)"

# Search the git checkout when there is one, so a root at the repo top is found from a subdirectory.
SCAN="$ROOT"
_git="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || echo "")"
[ -n "$_git" ] && SCAN="$(cd "$_git" && pwd -P)"

say() { [ "$TSV" -eq 1 ] || printf '%s\n' "$1"; }

# One level down only, and skipping the directories a root never is. Deeper nesting has never been
# seen and walking the whole tree would stat every SourcePackages checkout in a large project.
roots=""
ga_footprint_at "$SCAN" && roots="$SCAN"
for d in "$SCAN"/*/; do
  d="${d%/}"
  [ -d "$d" ] || continue
  case "${d##*/}" in .*|Packages|Scripts|docs|node_modules|build|DerivedData) continue ;; esac
  ga_footprint_at "$d" && roots="$roots
$d"
done
roots="$(printf '%s\n' "$roots" | grep -v '^$' || true)"

n=0
for r in $roots; do n=$((n + 1)); done
if [ "$n" -eq 0 ]; then
  say "no GenericArch root in $SCAN"
  exit "$GA_EX_OK"
fi

# ── Classify ───────────────────────────────────────────────────────────────
# Furthest along wins: position in GA_STEPS is the whole ranking. A root at `ready` has answered the
# §0 questions, triaged the gaps and generated the notes; a root at `install` has a copy of the
# tooling and nothing else. Manifest count breaks the tie downward — two manifests means installs
# were stacked without an uninstall between, which is residue by definition.
best=""; best_rank=-1
for r in $roots; do
  vers=""; mcount=0
  for m in $(ga_manifest_find "$r"); do
    mcount=$((mcount + 1))
    v="$(ga_manifest_version "$m" 2>/dev/null || echo unreadable)"
    vers="$vers${vers:+,}$v"
  done
  [ -n "$vers" ] || vers="none"

  step="none"
  ledger="$(ga_step_path "$r")"
  if [ -f "$ledger" ]; then
    step="$(awk -F'\t' '$0 !~ /^#/ && NF>=2 {s=$1} END {print (s ? s : "none")}' "$ledger")"
  fi
  rank="$(ga_step_pos "$step" 2>/dev/null || echo 0)"
  [ "$mcount" -gt 1 ] && rank=$((rank - 10))

  if [ "$rank" -gt "$best_rank" ]; then best_rank="$rank"; best="$r"; fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$r" "$vers" "$mcount" "$step" "$rank" >> "${TMPDIR:-/tmp}/ga-roots.$$"
done

if [ "$TSV" -eq 1 ]; then
  while IFS="$(printf '\t')" read -r r vers mcount step _rank; do
    verdict=KEEP; [ "$r" = "$best" ] || verdict=RETIRE
    printf '%s\t%s\t%s\t%s\t%s\n' "$verdict" "$r" "$vers" "$mcount" "$step"
  done < "${TMPDIR:-/tmp}/ga-roots.$$"
  rm -f "${TMPDIR:-/tmp}/ga-roots.$$"
  [ "$n" -gt 1 ] && exit "$GA_EX_ERR"
  exit "$GA_EX_OK"
fi

ga_hdr "── GenericArch roots in $SCAN ─────────────────────────"
while IFS="$(printf '\t')" read -r r vers mcount step _rank; do
  rel="${r#"$SCAN"/}"; [ "$rel" = "$r" ] && rel="."
  if [ "$r" = "$best" ]; then
    printf '  %sKEEP  %s%-28s%s versions: %-16s steps reached: %s\n' \
      "$GA_GRN" "$GA_OFF" "$rel" "$GA_DIM$GA_OFF" "$vers" "$step"
  else
    printf '  %sRETIRE%s %-28s versions: %-16s steps reached: %s\n' \
      "$GA_YEL" "$GA_OFF" "$rel" "$vers" "$step"
  fi
  [ "$mcount" -gt 1 ] && ga_dim "         $mcount manifests here — installs were stacked without an uninstall between"
done < "${TMPDIR:-/tmp}/ga-roots.$$"

if [ "$n" -eq 1 ]; then
  echo
  ga_ok "one root — nothing to consolidate"
  rm -f "${TMPDIR:-/tmp}/ga-roots.$$"
  exit "$GA_EX_OK"
fi

echo
say "${GA_BLD}Two live copies duplicate every command and skill, and a sync would update only one.${GA_OFF}"
say "Keeping the root that got furthest through the sequence. To retire the others, run each one's"
say "own uninstaller from its own root — its manifest is what proves ownership before anything is"
say "deleted, and nothing here bypasses that:"
echo
while IFS="$(printf '\t')" read -r r vers mcount step _rank; do
  [ "$r" = "$best" ] && continue
  # Newest first, which is the order the text below promises: each run removes only its own
  # version's records, so stopping halfway leaves the newest gone rather than an arbitrary mix.
  for v in $(printf '%s' "$vers" | tr ',' '\n' | LC_ALL=C sort -rV 2>/dev/null \
             || printf '%s' "$vers" | tr ',' '\n' | LC_ALL=C sort -r); do
    [ "$v" = "none" ] && continue
    printf '    ( cd "%s" && ./uninstall.sh %s )\n' "$r" "$v"
  done
  [ "$vers" = "none" ] && printf '    %s# %s has no manifest — uninstall.sh needs --base to prove ownership%s\n' \
    "$GA_DIM" "$r" "$GA_OFF"
done < "${TMPDIR:-/tmp}/ga-roots.$$"
say ""
say "${GA_DIM}Newest version first where a root carries more than one, or the leftovers keep it live."
say "Re-run this to confirm, then install or sync against the root that remains.${GA_OFF}"
rm -f "${TMPDIR:-/tmp}/ga-roots.$$"
exit "$GA_EX_ERR"
