#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    needs-approval
#@purpose   Retire installed GenericArch files this product has DECLINED — moved to .genericarch/safetodelete/, tombstoned so no later install re-creates them, and de-referenced from the indexes.
#@usage     ga-remove.sh <path>... --reason "<why>" [--apply] | ga-remove.sh --revive <path> [--apply] | ga-remove.sh --list
#@in        path:relpath(one or more, relative to the repo root) --reason:string(required to remove) --apply:flag(without it, dry run) --untracked:flag(allow a path the manifest does not own) --revive:relpath --list:flag
#@out       stdout:plan, then the tombstone rows, the index rows pruned, any prose references left to fix, and the commit message
#@exit      0=ok 1=path not owned|missing reason 2=usage 4=declined at the prompt
#@effects   with --apply: MOVES the listed files to .genericarch/safetodelete/<path> (never deletes), appends to .genericarch/TOMBSTONES.tsv and docs/DECISIONS.md, prunes their rows from .claude/MAP.tsv and .claude/SCRIPTS.tsv
#@when      delete an installed file|drop a doc that does not apply|decline a skill|remove module docs|why did a deleted file come back|tombstone|revive a declined file|where did the file go|recover a declined file|safetodelete directory
#
# The gap this closes: install.sh treats "not on disk" as "never installed" and creates the file
# again. So a file deleted by hand — including by /project-init, which is told to delete module docs
# for packages that do not exist — comes back on the next install or upgrade. That flip happened
# four times in one adoption before anyone noticed.
#
# A deletion is a decision. This tool is the only way to make one stick, and it does four things in
# one operation so none of them can be forgotten:
#
#   1. MOVE the file to .genericarch/safetodelete/<same relative path>. Nothing is destroyed. A decline is
#      a judgement about relevance, not about the content being wrong, and the judgement is reversed
#      often enough — a package arrives, a convention is adopted — that the bytes are worth keeping.
#      `--revive` puts the file back from there, byte-identical, without needing the network or a
#      reference checkout.
#   2. TOMBSTONE it, so install.sh does not re-create it.
#   3. DE-REFERENCE it: drop its rows from .claude/MAP.tsv and .claude/SCRIPTS.tsv. An index row
#      pointing at a retired file is worse than no row — it is grepped on every lookup and leads
#      somewhere that is not there. Prose references cannot be rewritten safely, so they are
#      reported, with file and line, as work still to do.
#   4. RECORD the reason in docs/DECISIONS.md, so nobody re-proposes it.
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/ga-lifecycle.sh
. "$HERE/ga-lifecycle.sh"

TARGET="$(cd "$HERE/.." && pwd)"
APPLY=0; UNTRACKED=0; LIST=0; REASON=""; REVIVE=""; PATHS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)     APPLY=1; shift ;;
    --untracked) UNTRACKED=1; shift ;;
    --list)      LIST=1; shift ;;
    --reason)    REASON="${2:-}"; shift 2 || true ;;
    --revive)    REVIVE="${2:-}"; shift 2 || true ;;
    --target)    TARGET="$(cd "${2:-}" 2>/dev/null && pwd)" || ga_die "no such directory: ${2:-}" "$GA_EX_USAGE"; shift 2 ;;
    -h|--help)   sed -n '2,12p' "$0"; exit "$GA_EX_USAGE" ;;
    -*)          ga_die "unknown flag: $1" "$GA_EX_USAGE" ;;
    *)           PATHS="$PATHS $1"; shift ;;
  esac
done

TOMBFILE="$(ga_tombstone_path "$TARGET")"
GRAVE="$(ga_grave_path "$TARGET")"
MANIFEST=""
for m in $(ga_manifest_find "$TARGET"); do MANIFEST="$m"; done
VERSION="unknown"
[ -n "$MANIFEST" ] && VERSION="$(ga_manifest_version "$MANIFEST")"

# ── --list ─────────────────────────────────────────────────────────────────
if [ "$LIST" -eq 1 ]; then
  [ -f "$TOMBFILE" ] || { ga_info "nothing declined — no tombstones in ${TARGET##*/}"; exit "$GA_EX_OK"; }
  ga_hdr "── Declined paths ─────────────────────────────────────"
  awk -F'\t' '$1!~/^#/ {printf "  %-46s %s  %s\n", $1, $3, $5}' "$TOMBFILE"
  echo
  ga_dim "  install.sh will not re-create these. Undo one with: ga-remove.sh --revive <path> --apply"
  exit "$GA_EX_OK"
fi

# ── --revive ───────────────────────────────────────────────────────────────
if [ -n "$REVIVE" ]; then
  ga_tombstoned "$TARGET" "$REVIVE" || ga_die "not declined, nothing to revive: $REVIVE" "$GA_EX_ERR"
  saved="$(ga_grave_path "$TARGET" "$REVIVE")"
  ga_info "revive  $REVIVE  ($(ga_tombstone_reason "$TARGET" "$REVIVE"))"
  if [ -f "$saved" ]; then
    ga_dim "  restoring from $GA_STATE_DIR/$GA_GRAVEYARD/$REVIVE — byte-identical, no fetch needed"
  else
    ga_warn "not in $GA_STATE_DIR/$GA_GRAVEYARD — the tombstone will be dropped and the next install
  will create the file from the base instead."
  fi
  if [ "$APPLY" -eq 0 ]; then
    ga_warn "dry run — add --apply to restore it and drop the tombstone"
    exit "$GA_EX_OK"
  fi
  if [ -e "$TARGET/$REVIVE" ]; then
    ga_die "$REVIVE already exists on disk — refusing to overwrite it. Move it aside first." "$GA_EX_ERR"
  fi
  if [ -f "$saved" ]; then
    mkdir -p "$(dirname "$TARGET/$REVIVE")"
    mv "$saved" "$TARGET/$REVIVE"
    ga_prune_empty_dirs "$(ga_grave_path "$TARGET")" "$(dirname "$REVIVE")"
    ga_ok "restored $REVIVE"
  fi
  ga_tombstone_drop "$TARGET" "$REVIVE"
  ga_ok "tombstone dropped — install.sh may create $REVIVE again"
  ga_dim "  Two things this cannot do for you: remove the row from docs/DECISIONS.md 'Do not"
  ga_dim "  re-propose' (a reversal should read as one, not vanish), and put back the index rows —"
  ga_dim "  re-add them to .claude/MAP.tsv, or re-run register-scripts.sh for a script."
  exit "$GA_EX_OK"
fi

# ── remove ─────────────────────────────────────────────────────────────────
[ -n "$PATHS" ] || { sed -n '5,7p' "$0" >&2; ga_die "no paths given" "$GA_EX_USAGE"; }
[ -n "$REASON" ] || ga_die "--reason is required: a deletion with no recorded reason is the thing this tool exists to prevent" "$GA_EX_ERR"

# Expand directories into files: a tombstone is per-path, and "docs/modules" as one row would
# silently cover a file added to it later.
EXPANDED=""
for p in $PATHS; do
  rel="${p#./}"; rel="${rel#"$TARGET"/}"
  abs="$TARGET/$rel"
  if [ -d "$abs" ]; then
    for leaf in $(cd "$TARGET" && find "$rel" -type f | LC_ALL=C sort); do EXPANDED="$EXPANDED $leaf"; done
  elif [ -e "$abs" ]; then
    EXPANDED="$EXPANDED $rel"
  else
    ga_warn "not on disk, skipped: $rel"
  fi
done
[ -n "$EXPANDED" ] || ga_die "nothing to remove" "$GA_EX_ERR"

ga_hdr "── Plan: decline $(printf '%s\n' $EXPANDED | grep -c .) file(s) ───────────────────"
echo
notowned=""
for rel in $EXPANDED; do
  owner="untracked"
  if [ -n "$MANIFEST" ] && [ -n "$(ga_manifest_record_for "$MANIFEST" "$rel")" ]; then owner="GenericArch"; fi
  if [ "$owner" = "untracked" ]; then notowned="$notowned $rel"; fi
  printf '  %s→%s %-46s %s%s → %s/safetodelete/%s\n' \
    "$GA_YEL" "$GA_OFF" "$rel" "$GA_DIM" "$owner" "$GA_STATE_DIR" "$GA_OFF"
done
echo
printf '  reason: %s\n' "$REASON"
printf '  %sMoved, not deleted. --revive puts any of them back byte-identical.%s\n' "$GA_DIM" "$GA_OFF"

if [ -n "$notowned" ] && [ "$UNTRACKED" -eq 0 ]; then
  echo
  ga_warn "these are not in the manifest — GenericArch did not install them:"
  for f in $notowned; do printf '      %s\n' "$f"; done
  ga_die "removing a file this tooling does not own is the operator's call, not this script's. Re-run with --untracked if that is what you mean." "$GA_EX_ERR"
fi

if [ "$APPLY" -eq 0 ]; then
  echo
  ga_warn "dry run — add --apply to retire and record"
  exit "$GA_EX_OK"
fi

ga_confirm "Move these to $GA_STATE_DIR/safetodelete/ and record them as declined?" || exit "$GA_EX_ABORT"

ga_tombstone_init "$TARGET"
removed=0
for rel in $EXPANDED; do
  sha="$(ga_sha256 "$TARGET/$rel" || echo "")"
  # Move, never delete. The relative path is preserved inside the grave so a revive needs no
  # bookkeeping beyond the tombstone, and two same-named files from different directories cannot
  # collide. An existing entry from an earlier decline of the same path is replaced — the tombstone
  # already carries that history.
  mkdir -p "$GRAVE/$(dirname "$rel")"
  if ! mv -f "$TARGET/$rel" "$GRAVE/$rel"; then
    ga_die "could not move $rel into $GA_STATE_DIR/safetodelete/ — nothing further was changed" "$GA_EX_ERR"
  fi
  ga_tombstone_add "$TARGET" "$rel" "$sha" "$VERSION" "$REASON"
  printf '  %s✓%s retired  %-42s %s→ %s/safetodelete/%s%s\n' \
    "$GA_GRN" "$GA_OFF" "$rel" "$GA_DIM" "$GA_STATE_DIR" "$rel" "$GA_OFF"
  removed=$((removed + 1))
done
# Directories emptied by the removals go too — an empty docs/modules/ reads as "we have modules".
ga_prune_empty_dirs "$TARGET" $(printf '%s\n' $EXPANDED | sed 's|/[^/]*$||' | LC_ALL=C sort -u)

# ── De-reference: the indexes first ────────────────────────────────────────
# A row pointing at a retired file is read on every lookup and leads nowhere. These two files are
# machine-owned registries, so pruning them is safe and exact.
pruned=0
for idx in .claude/MAP.tsv .claude/SCRIPTS.tsv; do
  [ -f "$TARGET/$idx" ] || continue
  before=$(grep -c . "$TARGET/$idx" || true)
  tmp="$TARGET/$idx.tmp"
  awk -F'\t' -v list="$EXPANDED" '
    BEGIN { n = split(list, a, " "); for (i = 1; i <= n; i++) if (a[i] != "") gone[a[i]] = 1 }
    /^#/ || NF < 2 { print; next }
    !($1 in gone)
  ' "$TARGET/$idx" > "$tmp" && mv "$tmp" "$TARGET/$idx"
  after=$(grep -c . "$TARGET/$idx" || true)
  if [ "$before" -ne "$after" ]; then
    printf '  %s✓%s pruned   %s row(s) from %s\n' "$GA_GRN" "$GA_OFF" "$((before - after))" "$idx"
    pruned=$((pruned + before - after))
  fi
done

# ── De-reference: what is left, for a person to resolve ────────────────────
# Prose is not rewritten here. A sentence that mentions a retired doc may need deleting, rephrasing,
# or repointing somewhere else, and only a reader of the sentence can tell which. Reporting it with
# a file and line is the honest half of the job.
echo
refs=0
REFLIST="$(mktemp -t ga-remove-refs)"
for rel in $EXPANDED; do
  base="$(basename "$rel")"
  grep -rn --exclude-dir=.git --exclude-dir="$GA_STATE_DIR" --exclude='*.tmp' \
       -e "$rel" -e "$base" "$TARGET/.claude" "$TARGET/docs" "$TARGET/CLAUDE.md" 2>/dev/null \
    | sed "s|^$TARGET/||" >> "$REFLIST" || true
done
if [ -s "$REFLIST" ]; then
  refs=$(grep -c . "$REFLIST" || true)
  ga_warn "$refs remaining reference(s) — prose is not rewritten automatically:"
  sort -u "$REFLIST" | head -20 | sed 's/^/      /'
  [ "$refs" -gt 20 ] && ga_dim "      … and $((refs - 20)) more"
  ga_dim "  Each is either a sentence to drop, or a pointer to move. CLAUDE.md needs its own yes."
else
  ga_ok "no remaining references in .claude/, docs/ or CLAUDE.md"
fi
rm -f "$REFLIST"

# ── The decision record ────────────────────────────────────────────────────
# A tombstone stops the file coming back. The DECISIONS.md row stops a person proposing it again.
# Both, or it resurfaces — the same rule /gaps applies to a Skip.
DEC="$TARGET/docs/DECISIONS.md"
if [ -f "$DEC" ] && grep -q '^## Do not re-propose' "$DEC"; then
  row="| $(printf '%s' "$EXPANDED" | tr ' ' '\n' | grep -c .) declined path(s) — \`$(printf '%s' "${EXPANDED# }" | cut -d' ' -f1)\`$([ "$removed" -gt 1 ] && printf ' and %s more' "$((removed - 1))") | $REASON. Recorded in \`.genericarch/$GA_TOMBSTONES\`; install.sh will not re-create them |"
  tmp="$DEC.tmp"
  awk -v row="$row" '
    /^## Do not re-propose/ {print; inblock=1; next}
    inblock && /^\| *-+/ {print; print row; inblock=0; next}
    {print}
  ' "$DEC" > "$tmp" && mv "$tmp" "$DEC"
  ga_ok "docs/DECISIONS.md — row added under 'Do not re-propose'"
else
  ga_warn "no 'Do not re-propose' section in docs/DECISIONS.md — add the row by hand, or it resurfaces"
fi

echo
ga_ok "$removed file(s) retired to $GA_STATE_DIR/$GA_GRAVEYARD/ · $pruned index row(s) pruned · tombstoned in ${TOMBFILE#"$TARGET"/}"
ga_hdr "── Commit this as ─────────────────────────────────────"
cat <<MSG

  Decline $removed GenericArch file(s): $REASON

  Moved to .genericarch/$GA_GRAVEYARD/ rather than deleted, so a reversal costs nothing.
  Recorded in .genericarch/$GA_TOMBSTONES so no later install re-creates them,
  and in docs/DECISIONS.md so nobody re-proposes them.
  Index rows pruned: $pruned.

MSG
