#!/usr/bin/env bash
# Remove a GenericArch install, and nothing else.
#
#   ./uninstall.sh v0.5.0             # plan, then ask
#   ./uninstall.sh v0.5.0 --dry-run   # print the plan and stop
#   ./uninstall.sh v0.5.0 --yes       # skip the confirmation prompt
#   ./uninstall.sh v0.1.0 --force     # proceed even if a different version is recorded
#
#   --target DIR   the repo to clean (default: the current directory)
#   --base DIR     a GenericArch checkout to verify hashes against when there is no manifest
#   --upgrade      keep files you edited exactly where they are; the next install re-tracks them
#   --final        move them to .genericarch/safetodelete/ and record them in CLAUDE.md
#
# Exit 0 means the repo is back to its pre-install state. Exit 1 means files were left behind —
# they are listed in safetodelete-after-migration-note.md at the repo root, which outlives the
# terminal AND is read by the next install.sh, so an edited file is picked up again instead of
# going unowned forever.
#
# The version argument is REQUIRED. Supported: v0.1.0, v0.2.0, v0.3.0, v0.4.0, v0.4.1, v0.4.2,
# v0.5.0, v0.6.0, v0.6.1 (latest).
#
# What this will and will not delete:
#
#   A file is removed only when its content PROVES it is GenericArch's — its sha256 matches the
#   manifest entry that recorded it, or, with no manifest, the blob that release actually shipped.
#   A file whose hash has drifted has been edited by you. It is kept, listed, and the reason given.
#   Timestamps can corroborate ownership but never decide it: a content mismatch always wins and
#   always protects the file. A path the manifest never mentioned is not looked at.
#
# Exit codes: 0 ok · 1 error (files left behind, or a manifest this version cannot read) ·
#             2 usage · 4 declined
set -euo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SELF/Scripts/ga-lifecycle.sh" ]; then
  # shellcheck source=Scripts/ga-lifecycle.sh
  . "$SELF/Scripts/ga-lifecycle.sh"
else
  echo "uninstall.sh: cannot find Scripts/ga-lifecycle.sh next to me." >&2
  echo "  Run it from the repo it was installed into, or from a GenericArch checkout with --target." >&2
  exit 1
fi

usage() { sed -n '2,20p' "$0"; }

VERSION=""
TARGET=""
BASE=""
DRY_RUN=0
FORCE=0
# "" ask · upgrade keep them in place · final retire them. See the completion prompt at the end.
AFTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)     GA_ASSUME_YES=1; shift ;;
    -n|--dry-run) DRY_RUN=1; shift ;;
    -f|--force)   FORCE=1; shift ;;
    --upgrade)    AFTER="upgrade"; shift ;;
    --final)      AFTER="final"; shift ;;
    '#')          ga_die "a '#' comment reached this script as an argument — your shell did not
  strip it (zsh does not, by default). Paste the command without its trailing comment, or run:
      setopt interactive_comments" "$GA_EX_USAGE" ;;
    --target)     [ $# -ge 2 ] || { usage >&2; ga_die "--target needs a directory" "$GA_EX_USAGE"; }
                  TARGET="$2"; shift 2 ;;
    --base)       [ $# -ge 2 ] || { usage >&2; ga_die "--base needs a directory" "$GA_EX_USAGE"; }
                  BASE="$2"; shift 2 ;;
    -h|--help)    usage; exit "$GA_EX_OK" ;;
    -*)           usage >&2; ga_die "unknown option: $1" "$GA_EX_USAGE" ;;
    *)            [ -z "$VERSION" ] || { usage >&2; ga_die "more than one version given: $VERSION and $1" "$GA_EX_USAGE"; }
                  VERSION="$1"; shift ;;
  esac
done
GA_ASSUME_YES="${GA_ASSUME_YES:-0}"

# ── The version argument is not optional ───────────────────────────────────
# Defaulting it would mean guessing which release's footprint to delete, and a wrong guess deletes
# the wrong files. Refusing costs the operator one word.
if [ -z "$VERSION" ]; then
  usage >&2
  echo >&2
  ga_die "a version is required — e.g. ./uninstall.sh $GA_LATEST_VERSION" "$GA_EX_USAGE"
fi
case "$VERSION" in v*) ;; *) VERSION="v$VERSION" ;; esac
if ! ga_is_supported_version "$VERSION"; then
  usage >&2
  echo >&2
  ga_die "unknown version: $VERSION
  Supported: $GA_SUPPORTED_VERSIONS (latest $GA_LATEST_VERSION)" "$GA_EX_USAGE"
fi

TARGET="${TARGET:-$(pwd)}"
[ -d "$TARGET" ] || ga_die "no such directory: $TARGET" "$GA_EX_USAGE"
TARGET="$(cd "$TARGET" && pwd)"
[ -w "$TARGET" ] || ga_die "target is not writable: $TARGET" "$GA_EX_ERR"

ga_hdr "GenericArch uninstaller"
printf '  from     %s\n' "$TARGET"
printf '  version  %s%s%s\n' "$GA_BLD" "$VERSION" "$GA_OFF"
if [ "$DRY_RUN" -eq 1 ]; then
  printf '  mode     %sdry run%s — the plan only, nothing is removed\n' "$GA_YEL" "$GA_OFF"
fi

# ── Locate the manifest ────────────────────────────────────────────────────
MANIFEST="$(ga_manifest_path "$TARGET" "$VERSION")"
MODE="manifest"
if [ ! -f "$MANIFEST" ]; then
  OTHER=""
  # shellcheck disable=SC2046  # one path per line, none of them contain spaces
  for m in $(ga_manifest_find "$TARGET"); do OTHER="$m"; done
  if [ -n "$OTHER" ]; then
    INSTALLED_VERSION="$(ga_manifest_version "$OTHER")"
    printf '\n'
    ga_warn "you asked to remove $VERSION, but this repo records $INSTALLED_VERSION
  manifest: ${OTHER#"$TARGET"/}"
    if [ "$FORCE" -eq 0 ]; then
      ga_die "stopping — nothing was removed.
  Remove what is actually installed:  ./uninstall.sh $INSTALLED_VERSION
  Or override and use the recorded manifest anyway:  ./uninstall.sh $VERSION --force" "$GA_EX_ERR"
    fi
    ga_warn "--force given — using $INSTALLED_VERSION's manifest, which is the only accurate record here"
    MANIFEST="$OTHER"
  else
    MODE="fallback"
  fi
fi

REMOVE="${TMPDIR:-/tmp}/ga-uninstall.remove.$$"
KEEP="${TMPDIR:-/tmp}/ga-uninstall.keep.$$"
RESTORE="${TMPDIR:-/tmp}/ga-uninstall.restore.$$"
STRIP="${TMPDIR:-/tmp}/ga-uninstall.strip.$$"
: > "$REMOVE"; : > "$KEEP"; : > "$RESTORE"; : > "$STRIP"
trap 'rm -f "$REMOVE" "$KEEP" "$RESTORE" "$STRIP"' EXIT INT TERM

# ── Classify ───────────────────────────────────────────────────────────────
if [ "$MODE" = "manifest" ]; then
  ga_ok "manifest found: ${MANIFEST#"$TARGET"/}"
  # A manifest written by a NEWER GenericArch can carry actions this parser has never heard of, and
  # the action is what decides between "delete this" and "never touch this". Guessing is the one
  # outcome that is not allowed, so an unknown schema stops here.
  _schema="$(sed -n 's/.*"schema"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$MANIFEST" | head -1)"
  [ -n "$_schema" ] || _schema=1
  if [ "$_schema" -gt "$GA_MANIFEST_SCHEMA" ]; then
    ga_die "this manifest is schema $_schema; this uninstaller understands $GA_MANIFEST_SCHEMA.
  It was written by a newer GenericArch, and it can describe files in ways this version would
  misread — including files of yours it must not delete.

  Use the uninstall.sh that came with it: ${MANIFEST#"$TARGET"/} names its version.
  Nothing was removed." "$GA_EX_ERR"
  fi
  ga_manifest_records "$MANIFEST" | while IFS= read -r rec; do
    rel="$(ga_json_field "$rec" path)"
    act="$(ga_json_field "$rec" action)"
    want="$(ga_json_field "$rec" sha256)"
    backup="$(ga_json_field "$rec" backup || true)"
    orig="$(ga_json_field "$rec" original_sha256 || true)"
    file="$TARGET/$rel"

    case "$act" in
      skipped)
        # Never ours. It was already in the repo when we installed, and we did not write it.
        continue ;;
      orphan)
        # A file a PREVIOUS uninstall could not remove, that this install tracked rather than
        # disowned. Still not ours — but it must be carried into this run's note, or the chain
        # breaks at the second uninstall and the file goes unowned for good.
        if [ -e "$file" ]; then
          printf '%s\tstill yours — edited before an earlier uninstall, tracked ever since\n' "$rel" >> "$KEEP"
        fi
        continue ;;
      replaced)
        # We substituted this path wholesale and kept their original at $backup. Unlike `modified`
        # there is no managed block, so there is nothing to strip: either the backup restores it
        # exactly, or the file stays and we say where their copy is.
        if [ ! -f "$file" ]; then
          printf '%s\tgone — you deleted it; your original is still at %s\n' "$rel" "$backup" >> "$KEEP"
          continue
        fi
        now="$(ga_sha256 "$file")"
        if [ "$now" != "$want" ]; then
          printf '%s\tedited since install — kept; your original is still at %s\n' "$rel" "$backup" >> "$KEEP"
          continue
        fi
        if [ -z "$backup" ] || [ ! -f "$TARGET/$backup" ]; then
          printf '%s\tours, but %s is gone — kept rather than deleting a file with no original to restore\n' \
            "$rel" "${backup:-the backup}" >> "$KEEP"
          continue
        fi
        if [ "$(ga_sha256 "$TARGET/$backup")" != "$orig" ]; then
          printf '%s\t%s no longer matches the original it recorded — kept, restore it by hand\n' \
            "$rel" "$backup" >> "$KEEP"
          continue
        fi
        printf '%s\t%s\t%s\n' "$rel" "$backup" "$orig" >> "$RESTORE"
        continue ;;
      modified)
        if [ ! -f "$file" ]; then
          # Deleted by hand since install. Restoring would resurrect a file the operator removed
          # on purpose, so the backup is left where it is and its location reported — it may be
          # the only surviving copy of the original.
          if [ -n "$backup" ] && [ -f "$TARGET/$backup" ]; then
            printf '%s\tgone — you deleted it; your original is still at %s\n' "$rel" "$backup" >> "$KEEP"
          else
            printf '%s\tgone — already removed by hand\n' "$rel" >> "$KEEP"
          fi
          continue
        fi
        now="$(ga_sha256 "$file")"
        if [ "$now" = "$want" ] && [ -n "$backup" ] && [ -f "$TARGET/$backup" ]; then
          printf '%s\t%s\t%s\n' "$rel" "$backup" "$orig" >> "$RESTORE"
        elif [ "$now" = "$want" ]; then
          printf '%s\tbackup missing — the managed block will be stripped instead\n' "$rel" >> "$STRIP"
        else
          # Edited since install. Restoring the backup would throw those edits away, so only the
          # block GenericArch added comes out.
          printf '%s\tedited since install — keeping your changes, removing only the managed block\n' "$rel" >> "$STRIP"
          # Stripping leaves the file correct, so the backup is now just GenericArch state. It came
          # from the manifest, so removing it is still a manifest-driven deletion.
          [ -n "$backup" ] && [ -f "$TARGET/$backup" ] && printf '%s\n' "$backup" >> "$REMOVE"
        fi
        continue ;;
    esac

    # An action this version does not know cannot be assumed removable. The schema gate above
    # catches the ordinary case; this catches a hand-edited manifest, and errs the only safe way.
    case "$act" in
      created) ;;
      *) printf '%s\tunrecognised action "%s" in the manifest — kept, nothing was assumed\n' \
           "$rel" "$act" >> "$KEEP"; continue ;;
    esac

    # action = created
    if [ ! -e "$file" ]; then continue; fi
    now="$(ga_sha256 "$file" || echo "")"
    if [ "$now" = "$want" ]; then
      printf '%s\n' "$rel" >> "$REMOVE"
    else
      printf '%s\tyou edited it — content hash does not match the manifest\n' "$rel" >> "$KEEP"
    fi
  done
else
  # ── No manifest: install.sh never finished, or was blocked by the gate ────
  # The known file list narrows the search; it never authorises a removal. Every candidate is still
  # proven by hashing it against the blob that release actually shipped, read from a reference
  # checkout with `git cat-file` — no checkout switch, no network.
  printf '\n'
  ga_warn "no manifest in $TARGET/$GA_STATE_DIR — treating this as an incomplete install"
  if [ -z "$BASE" ]; then
    if [ -f "$SELF/Scripts/adopt.sh" ] && [ -f "$SELF/CLAUDE.md" ] \
       && grep -q "Generic Apple Platform App Architecture" "$SELF/CLAUDE.md" 2>/dev/null; then
      BASE="$SELF"
    fi
  fi
  [ -n "$BASE" ] || ga_die "without a manifest, ownership can only be proven against a reference checkout.
  Point me at one:  ./uninstall.sh $VERSION --target $TARGET --base /path/to/GenericArch
  Nothing was removed." "$GA_EX_ERR"
  [ -d "$BASE" ] || ga_die "--base is not a directory: $BASE
  Nothing was removed." "$GA_EX_USAGE"
  BASE="$(cd "$BASE" && pwd)"
  [ -d "$BASE/.git" ] || ga_die "--base must be a git checkout of GenericArch: $BASE
  Ownership is proven by hashing against the blobs $VERSION actually shipped, which needs its
  git history. Nothing was removed." "$GA_EX_USAGE"
  git -C "$BASE" cat-file -e "$VERSION^{commit}" 2>/dev/null \
    || ga_die "the reference checkout at $BASE has no $VERSION tag — cannot verify ownership.
  Fetch the tag there, or pass a different --base. Nothing was removed." "$GA_EX_ERR"
  ga_dim "  verifying against $VERSION in $BASE"

  ga_known_paths "$VERSION" | while IFS= read -r top; do
    [ -e "$TARGET/$top" ] || continue
    # Expand a directory into its files; a bare file yields itself.
    if [ -d "$TARGET/$top" ]; then
      cands="$(cd "$TARGET" && find "$top" -type f -print | LC_ALL=C sort)"
    else
      cands="$top"
    fi
    printf '%s\n' "$cands" | while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      [ -f "$TARGET/$rel" ] || continue
      # The pre-manifest version stamp is generated, never shipped, so it has no blob. Its format
      # is what proves it is ours; without that check it survives every uninstall as the one piece
      # of GenericArch left in the repo.
      if [ "$rel" = ".genericarch-version" ]; then
        if ga_is_version_stamp "$TARGET/$rel"; then
          printf '%s\n' "$rel" >> "$REMOVE"
        else
          printf '%s\tnot in GenericArch stamp format — left alone\n' "$rel" >> "$KEEP"
        fi
        continue
      fi
      if ! blob_sha="$(git -C "$BASE" cat-file blob "$VERSION:$rel" 2>/dev/null | shasum -a 256 | awk '{print $1}')" \
         || [ -z "$blob_sha" ]; then
        printf '%s\tnot shipped in %s — GenericArch cannot prove it wrote this\n' "$rel" "$VERSION" >> "$KEEP"
        continue
      fi
      if [ "$(ga_sha256 "$TARGET/$rel")" = "$blob_sha" ]; then
        printf '%s\n' "$rel" >> "$REMOVE"
      else
        printf '%s\tyou edited it — content hash does not match %s\n' "$rel" "$VERSION" >> "$KEEP"
      fi
    done
  done
  # The managed block is proven by its own delimiters, not by a hash — those markers are something
  # only install.sh writes.
  if ga_block_present "$TARGET/.gitignore"; then
    printf '%s\tmanaged block found — removing just the block\n' ".gitignore" >> "$STRIP"
  fi
fi

# GenericArch's own state directory is unambiguously ours, manifest or not.
for extra in "$GA_STATE_DIR/manifest-$VERSION.json"; do
  [ -f "$TARGET/$extra" ] && printf '%s\n' "$extra" >> "$REMOVE"
done

n_remove=$(wc -l < "$REMOVE" | tr -d ' ')
n_keep=$(wc -l < "$KEEP" | tr -d ' ')
n_restore=$(wc -l < "$RESTORE" | tr -d ' ')
n_strip=$(wc -l < "$STRIP" | tr -d ' ')

# ── The plan, in full, before anything is deleted ──────────────────────────
ga_hdr "── Removal plan ───────────────────────────────────────"
if [ "$n_remove" -gt 0 ]; then
  printf '\n%s  remove%s — %d file(s), each verified by content hash\n' "$GA_BLD" "$GA_OFF" "$n_remove"
  sed 's|^|    − |' "$REMOVE"
fi
if [ "$n_restore" -gt 0 ]; then
  printf '\n%s  restore%s — originals put back byte-for-byte from backup\n' "$GA_BLD" "$GA_OFF"
  awk -F'\t' '{printf "    ↩ %s  ← %s\n", $1, $2}' "$RESTORE"
fi
if [ "$n_strip" -gt 0 ]; then
  printf '\n%s  edit%s — only the GenericArch block comes out; your lines stay\n' "$GA_BLD" "$GA_OFF"
  awk -F'\t' '{printf "    ~ %s  (%s)\n", $1, $2}' "$STRIP"
fi
if [ "$n_keep" -gt 0 ]; then
  printf '\n%s  KEPT — not deleted%s\n' "$GA_YEL" "$GA_OFF"
  awk -F'\t' '{printf "    · %s\n        %s\n", $1, $2}' "$KEEP"
  printf '  %sThese stay because GenericArch could not prove it owns their current content.%s\n' "$GA_DIM" "$GA_OFF"
  printf '  %sReview them yourself; delete by hand if you want them gone.%s\n' "$GA_DIM" "$GA_OFF"
fi
if [ "$n_remove" -eq 0 ] && [ "$n_restore" -eq 0 ] && [ "$n_strip" -eq 0 ]; then
  echo
  ga_ok "nothing to remove — no verified GenericArch files found in $TARGET"
  [ "$n_keep" -gt 0 ] && ga_dim "($n_keep file(s) kept, listed above.)"
  exit "$GA_EX_OK"
fi

echo
printf '%s───────────────────────────────────────────────────────%s\n' "$GA_BLD" "$GA_OFF"
printf '%d remove · %d restore · %d block edit · %d kept (yours)\n' \
  "$n_remove" "$n_restore" "$n_strip" "$n_keep"

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  ga_dim "Dry run — nothing was removed."
  exit "$GA_EX_OK"
fi

echo
if ! ga_confirm "Remove GenericArch $VERSION from $TARGET?"; then
  echo
  ga_dim "Aborted — nothing was removed."
  exit "$GA_EX_ABORT"
fi

# ── Execute ────────────────────────────────────────────────────────────────
# What each kept file was FOR — read now, because .claude/MAP.tsv and .claude/SCRIPTS.tsv are
# about to be removed and they are the only things that say. A path with no row simply has no
# description; the note still carries its path and the reason it survived.
KEEPDESC="$(mktemp -t ga-uninstall-desc)"
trap 'rm -f "$REMOVE" "$KEEP" "$RESTORE" "$STRIP" "$KEEPDESC"' EXIT INT TERM
if [ "$n_keep" -gt 0 ]; then
  while IFS="$(printf '\t')" read -r krel _kreason; do
    [ -n "$krel" ] || continue
    kdesc=""
    [ -f "$TARGET/.claude/SCRIPTS.tsv" ] && kdesc="$(awk -F'\t' -v p="$krel" '$1==p {print $5; exit}' \
      "$TARGET/.claude/SCRIPTS.tsv" 2>/dev/null || true)"
    if [ -z "$kdesc" ] && [ -f "$TARGET/.claude/MAP.tsv" ]; then
      kdesc="$(awk -F'\t' -v p="$krel" '$1==p {print $4; exit}' "$TARGET/.claude/MAP.tsv" 2>/dev/null || true)"
    fi
    printf '%s\t%s\n' "$krel" "$kdesc" >> "$KEEPDESC"
  done < "$KEEP"
fi

ga_hdr "── Removing ───────────────────────────────────────────"

# Restore first: a backup lives under the state directory, which the removals below clear out.
if [ "$n_restore" -gt 0 ]; then
  while IFS="$(printf '\t')" read -r rel backup orig; do
    [ -n "$rel" ] || continue
    cp -p "$TARGET/$backup" "$TARGET/$rel"
    if [ -n "$orig" ] && [ "$orig" != "null" ]; then
      if [ "$(ga_sha256 "$TARGET/$rel")" = "$orig" ]; then
        ga_ok "restored $rel — verified against the pre-install hash"
      else
        ga_warn "restored $rel from backup, but its hash does not match the recorded original.
  The backup itself may have been altered. Check this file before trusting it."
      fi
    else
      ga_ok "restored $rel from backup"
    fi
    rm -f "$TARGET/$backup"
  done < "$RESTORE"
fi

if [ "$n_strip" -gt 0 ]; then
  while IFS="$(printf '\t')" read -r rel why; do
    [ -n "$rel" ] || continue
    if ga_block_present "$TARGET/$rel"; then
      ga_block_strip "$TARGET/$rel"
      ga_ok "removed the managed block from $rel — $why"
      ga_dim "  (line-based edit: a file that had no trailing newline before install now has one)"
    fi
  done < "$STRIP"
fi

# Removals are per-file with rm -f. There is no rm -rf anywhere in this script: every path here
# came from a manifest record or a hash-verified candidate, and a directory is only ever retired
# by rmdir, which refuses when anything of yours is still inside.
removed=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  rm -f "$TARGET/$rel"
  removed=$((removed + 1))
done < "$REMOVE"
ga_ok "removed $removed file(s)"

# Generated evidence, not installed files: ga-init-scan.sh and sync-notes.sh --evidence write here,
# install.sh runs the first of the two itself, and the managed .gitignore block already declares the
# directory untracked. Nothing in it is a decision, so leaving it behind would make "back to its
# pre-install state" a claim `git status --ignored` contradicts — and would report as an orphan a
# file no ownership check can ever prove.
rm -f "$TARGET/.claude/notes/.evidence/INIT-SCAN.md" "$TARGET/.claude/notes/.evidence/INIT-CONFLICTS.tsv"
rmdir "$TARGET/.claude/notes/.evidence" 2>/dev/null || true

# ── What could not be removed, and what becomes of it ──────────────────────
# A partial removal that reports success is the failure mode this closes. One run of an earlier
# uninstaller removed 4 files out of about 110, printed nothing durable, and the next installer
# absorbed the remainder as if it had always been there.
#
# The record lives at the repo ROOT, not in $GA_STATE_DIR. It used to live there, and that is
# exactly why nothing ever read it: a clean uninstall retires that directory, so the one artifact
# describing what survived was filed inside the thing being deleted. install.sh reads
# safetodelete-after-migration-note.md; it never read orphans-<version>.txt.
NOTE="$TARGET/safetodelete-after-migration-note.md"
RETIRED=0
if [ "$n_keep" -gt 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  # Two outcomes, and the operator picks. There is no way to infer it: the upgrade path hands them
  # this command and walks away, so the script never learns why it was run.
  if [ -z "$AFTER" ]; then
    if [ "$GA_ASSUME_YES" -eq 1 ]; then
      # --yes takes the side that destroys nothing. An unattended run must not retire files.
      AFTER="upgrade"
    else
      echo
      ga_warn "$n_keep file(s) survived because you edited them — listed above"
      ga_dim "  Leaving them in place is what an upgrade wants: the next install re-tracks them."
      ga_dim "  Retiring them is what a final removal wants: they move to $GA_STATE_DIR/$GA_GRAVEYARD/,"
      ga_dim "  which nothing deletes, and the list is written into your CLAUDE.md."
      if ga_confirm "Done with GenericArch — retire them to $GA_GRAVEYARD/ and record them?"; then
        AFTER="final"
      else
        # Also the answer when there is no terminal to ask on. ga_confirm says so and returns 1,
        # and 1 is the side that moves nothing — so an unattended run cannot retire a file.
        AFTER="upgrade"
      fi
    fi
  fi
  case "$AFTER" in
    final)   ga_dim "  → retiring them, and recording the list where you will read it" ;;
    upgrade) ga_dim "  → leaving them exactly where they are, for the next install to re-track" ;;
  esac

  {
    printf '# GenericArch %s — what the uninstall left behind\n\n' "$VERSION"
    printf 'Written %s by `uninstall.sh`. %d file(s).\n\n' "$(ga_now_iso)" "$n_keep"
    printf 'Each was edited after install, so its content no longer proved it was GenericArch'"'"'s.\n'
    printf 'A hash mismatch always protects the file — nothing here was deleted.\n\n'
    if [ "$AFTER" = "final" ]; then
      printf 'They have been moved to `%s/%s/`.\n\n' "$GA_STATE_DIR" "$GA_GRAVEYARD"
    else
      printf 'They are where they were. The next `install.sh` reads this file and re-tracks them,\n'
      printf 'so they are recorded rather than silently absorbed.\n\n'
    fi
    printf '| path | why it survived | what it was for |\n|---|---|---|\n'
    while IFS="$(printf '\t')" read -r krel kreason; do
      [ -n "$krel" ] || continue
      kdesc="$(awk -F'\t' -v p="$krel" '$1==p {print $2; exit}' "$KEEPDESC" 2>/dev/null || true)"
      printf '| `%s` | %s | %s |\n' "$krel" "$kreason" "${kdesc:-—}"
    done < "$KEEP"
  } > "$NOTE"

  if [ "$AFTER" = "final" ]; then
    while IFS="$(printf '\t')" read -r krel _kreason; do
      [ -n "$krel" ] || continue
      [ -e "$TARGET/$krel" ] || continue
      # A CLAUDE.md whose original is still sitting unrestored at CLAUDE-BK.md is a reconciliation
      # only the operator can make, not a file to put away. Retiring it would leave the repo with
      # neither their rules nor ours in place, and two files to work out why.
      if [ "$krel" = "CLAUDE.md" ] && [ -f "$TARGET/CLAUDE-BK.md" ]; then
        ga_warn "CLAUDE.md left in place — you edited it, and your original is still at CLAUDE-BK.md.
  Merge the two by hand; retiring either one would decide that for you."
        continue
      fi
      kgrave="$(ga_grave_path "$TARGET" "$krel")"
      mkdir -p "$(dirname "$kgrave")"
      mv "$TARGET/$krel" "$kgrave"
      RETIRED=$((RETIRED + 1))
    done < "$KEEP"
    [ "$RETIRED" -gt 0 ] && ga_ok "retired $RETIRED file(s) to $GA_STATE_DIR/$GA_GRAVEYARD/ — moved, never deleted"

    # The durable record goes where the operator actually reads. CLAUDE.md first — and only when it
    # carries no managed block already, because appending a second one to a file we do not own is
    # how two records become one unreadable span.
    NOTE_TARGET=""
    if [ -f "$TARGET/CLAUDE.md" ] && ! ga_block_present "$TARGET/CLAUDE.md"; then
      NOTE_TARGET="CLAUDE.md"
    else
      NOTE_TARGET="GENERICARCH-ORPHANS.md"
      # Wholly ours, so replacing an older block in it loses nothing.
      [ -f "$TARGET/$NOTE_TARGET" ] && ga_block_strip "$TARGET/$NOTE_TARGET"
    fi
    KEEPLIST=""
    while IFS="$(printf '\t')" read -r krel kreason; do
      [ -n "$krel" ] || continue
      kdesc="$(awk -F'\t' -v p="$krel" '$1==p {print $2; exit}' "$KEEPDESC" 2>/dev/null || true)"
      KEEPLIST="$KEEPLIST- \`$krel\` — $kreason${kdesc:+ · was: $kdesc}
"
    done < "$KEEP"
    ga_block_append "$TARGET/$NOTE_TARGET" \
      "## GenericArch $VERSION — $RETIRED file(s) retired on $(ga_now_iso)" \
      "" \
      "These were edited after install, so the uninstall could not prove they were GenericArch's" \
      "and refused to delete them. They are in \`$GA_STATE_DIR/$GA_GRAVEYARD/\`, moved rather than" \
      "removed — copy any of them back by hand, then delete this block." \
      "" \
      "${KEEPLIST%
}"
    ga_ok "recorded them in $NOTE_TARGET"

    # The note was the hand-off between two runs. With the files retired and the list written into
    # a file that stays, it has nothing left to carry — so it goes, without asking again.
    rm -f "$NOTE"
  else
    ga_warn "safetodelete-after-migration-note.md written — the next install reads it and
  re-tracks these files rather than absorbing them"
  fi
fi

# Retire directories that are now empty, deepest first. One holding a preserved file simply is not
# empty, so it survives without being special-cased.
DIRS="$(awk '{print}' "$REMOVE" | sed 's|/[^/]*$||' | grep -v '^$' | LC_ALL=C sort -ru || true)"
if [ -n "$DIRS" ]; then
  # shellcheck disable=SC2086
  ga_prune_empty_dirs "$TARGET" $DIRS
fi
rmdir "$TARGET/$GA_STATE_DIR/backups" 2>/dev/null || true
# The step ledger is install-time bookkeeping, not a decision: with nothing declined there is
# nothing to carry forward, and leaving it behind means "back to its pre-install state" is a claim
# `git status` contradicts. Tombstones are different — those outlive the install on purpose.
if [ ! -f "$(ga_tombstone_path "$TARGET")" ]; then
  rm -f "$(ga_step_path "$TARGET")"
fi
rmdir "$(ga_grave_path "$TARGET")" 2>/dev/null || true
rmdir "$TARGET/$GA_STATE_DIR" 2>/dev/null || true
if [ -d "$TARGET/$GA_STATE_DIR" ]; then
  ga_warn "$GA_STATE_DIR/ still holds files — left in place:"
  find "$TARGET/$GA_STATE_DIR" -type f | sed "s|$TARGET/|    |"
  ga_dim "  TOMBSTONES.tsv and STEPS.tsv are records of decisions, not installed files. They are kept"
  ga_dim "  on purpose: a re-install must still honour what this product declined."
  ga_dim "  $GA_GRAVEYARD/ holds files this product declined, moved rather than deleted. The name is the"
  ga_dim "  contract: deleting that directory loses nothing except the ability to restore them."
fi

ga_hdr "Removed GenericArch $VERSION"
if [ "$n_keep" -gt 0 ] && [ "$AFTER" != "final" ]; then
  printf '\n%s%d file(s) were preserved because you edited them.%s They are listed above and in\n' \
    "$GA_YEL" "$n_keep" "$GA_OFF"
  printf 'safetodelete-after-migration-note.md, which the next install.sh reads — they will be\n'
  printf 'tracked again rather than absorbed as if GenericArch had always owned them.\n'
  printf '\n%sThis repo is NOT back to its pre-install state%s, so this run exits non-zero. Nothing else\n' \
    "$GA_YEL" "$GA_OFF"
  printf 'GenericArch installed remains.\n'
elif [ "$n_keep" -gt 0 ]; then
  printf '\n%d file(s) you had edited were moved to %s/%s/ rather than deleted, and listed in\n' \
    "$RETIRED" "$GA_STATE_DIR" "$GA_GRAVEYARD"
  printf '%s. Nothing was destroyed.\n' "${NOTE_TARGET:-CLAUDE.md}"
  if [ "$RETIRED" -lt "$n_keep" ]; then
    printf '\n%s%d file(s) stayed where they are%s — named above, each for a reason retiring it would\n' \
      "$GA_YEL" "$((n_keep - RETIRED))" "$GA_OFF"
    printf 'have decided on your behalf. This run exits non-zero because of them.\n'
  else
    printf '\nEverything GenericArch installed is gone. Two things it did NOT install remain, both\n'
    printf 'because you asked for them: the record in %s, and %s/%s/ holding\n' \
      "$NOTE_TARGET" "$GA_STATE_DIR" "$GA_GRAVEYARD"
    printf 'the files themselves. Delete either once you are done with it.\n'
  fi
else
  printf '\nThe repo is back to its pre-install state.\n'
fi

# One root is not the checkout. An install at a nested project directory survives an uninstall run
# at the repo root and vice versa, and "back to its pre-install state" read as a statement about
# the whole checkout is then false — which is exactly how a second footprint went unnoticed long
# enough to be re-created from shell history.
OTHER=""
GITROOT="$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null || echo "")"
if [ -n "$GITROOT" ]; then
  GITROOT_P="$(cd "$GITROOT" 2>/dev/null && pwd -P || echo "$GITROOT")"
  [ "$GITROOT_P" != "$(cd "$TARGET" && pwd -P)" ] && ga_footprint_at "$GITROOT" && OTHER="$GITROOT"
fi
if [ -z "$OTHER" ]; then
  for d in "$TARGET"/*/; do
    d="${d%/}"
    [ -d "$d" ] || continue
    case "${d##*/}" in .*|Packages|Scripts|docs) continue ;; esac
    if ga_footprint_at "$d"; then OTHER="$d"; break; fi
  done
fi
if [ -n "$OTHER" ]; then
  otherver="unknown"
  # shellcheck disable=SC2046  # one path per line, none of them contain spaces
  for m in $(ga_manifest_find "$OTHER"); do
    otherver="$(ga_manifest_version "$m" 2>/dev/null || true)"
    [ -n "$otherver" ] || otherver="unreadable manifest"
  done
  echo
  ga_warn "another GenericArch install is still live in this checkout:
    $OTHER  ($otherver)
  This run cleaned $TARGET only. Uninstall that one from its own root if you meant to remove both."
fi
# An explicit exit, not a trailing `[ ... ] && ...`: as the script's last statement, a false test
# becomes the script's exit status, and a completely successful uninstall reported failure purely
# because the target was not a git repo.
if [ -d "$TARGET/.git" ]; then
  ga_dim "Confirm with: git -C $TARGET status"
fi
# Exit 1 on a partial removal. A caller — a person or CI asserting that install→uninstall is a
# round trip — must not have to parse stdout to learn that files were left behind.
#
# --final is not a partial removal. The kept files were retired to the graveyard on purpose and the
# working tree is clean, so the round-trip assertion holds and the exit code has to say so.
if [ "$AFTER" = "final" ]; then
  # --final is not a partial removal unless something refused to be retired. What was filed away
  # was filed away on purpose, so the round-trip assertion holds and the exit code says so.
  [ "$RETIRED" -lt "$n_keep" ] && exit "$GA_EX_ERR"
elif [ "$n_keep" -gt 0 ]; then
  exit "$GA_EX_ERR"
fi
exit "$GA_EX_OK"
