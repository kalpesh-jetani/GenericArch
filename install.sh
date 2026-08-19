#!/usr/bin/env bash
# Install GenericArch into a target repo — additively, atomically, and reversibly.
#
#   ./install.sh                      # plan for the current directory, then ask
#   ./install.sh /path/to/TargetRepo  # plan for somewhere else
#   ./install.sh --dry-run            # print the plan and stop
#   ./install.sh --yes                # skip the confirmation prompt
#   ./install.sh --force              # install even if the repo identifies as non-Apple
#
# This script runs from a GenericArch CHECKOUT and touches the network never. To install straight
# from GitHub, use bootstrap.sh, which clones a pinned tag and then calls this.
#
# Three properties it is built to guarantee, in the order they are enforced:
#
#   1. Nothing is written before the compatibility gate has passed.
#   2. Nothing existing is ever overwritten. A path the target already owns is preserved and
#      reported; the only file GenericArch edits is a managed, delimited block it can remove again.
#   3. Either every planned file lands or none does. Files are staged into a temp tree first, and
#      any failure during the commit rolls the target back to exactly where it started.
#
# The manifest is written LAST, so its presence is itself the proof that the install completed.
# uninstall.sh reads it and nothing else.
#
# Exit codes: 0 ok · 1 error · 2 usage · 3 incompatible target · 4 declined · 78 not macOS
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"

# The helper carries the exit codes, the hashing, the manifest format and the gate. Sourcing it is
# what keeps install and uninstall from disagreeing about any of them.
if [ ! -f "$SRC/Scripts/ga-lifecycle.sh" ]; then
  echo "install.sh: cannot find Scripts/ga-lifecycle.sh next to me — is this a GenericArch checkout?" >&2
  exit 1
fi
# shellcheck source=Scripts/ga-lifecycle.sh
. "$SRC/Scripts/ga-lifecycle.sh"

usage() {
  sed -n '2,15p' "$0"
  echo
  echo "Exit codes: 0 ok · 1 error · 2 usage · 3 incompatible target · 4 declined · 78 not macOS"
}

TARGET=""
DRY_RUN=0
FORCE_COMPAT=0
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)      GA_ASSUME_YES=1; shift ;;
    -n|--dry-run)  DRY_RUN=1; shift ;;
    -f|--force)    FORCE_COMPAT=1; shift ;;
    --target)      [ $# -ge 2 ] || ga_die "--target needs a directory" "$GA_EX_USAGE"
                   TARGET="$2"; shift 2 ;;
    -h|--help)     usage; exit "$GA_EX_OK" ;;
    -*)            usage >&2; ga_die "unknown option: $1" "$GA_EX_USAGE" ;;
    *)             [ -z "$TARGET" ] || ga_die "more than one target given: $TARGET and $1" "$GA_EX_USAGE"
                   TARGET="$1"; shift ;;
  esac
done
GA_ASSUME_YES="${GA_ASSUME_YES:-0}"

# Before the target is even resolved: this layer cannot run anywhere but macOS, and an install that
# lands on Linux is a set of files whose every script refuses itself. -h is handled above, so help
# still works on any machine.
ga_require_macos

# ── Source must be a real GenericArch checkout ─────────────────────────────
# install.sh itself travels into the target (it is in adopt.sh's BASE list), so a copy of this
# file will exist in repos that have no base to install FROM. Say so plainly instead of failing
# further in with a confusing error about a missing list.
if [ ! -f "$SRC/Scripts/adopt.sh" ] || [ ! -f "$SRC/CLAUDE.md" ] \
   || ! grep -q "Generic Apple Platform App Architecture" "$SRC/CLAUDE.md" 2>/dev/null; then
  ga_die "this is not a GenericArch checkout — there is no base here to install from.
  To install from GitHub instead:  ./bootstrap.sh --apply" "$GA_EX_ERR"
fi

command -v git >/dev/null 2>&1 || ga_die "git is required" "$GA_EX_ERR"

TARGET="${TARGET:-$(pwd)}"
[ -d "$TARGET" ] || ga_die "no such directory: $TARGET" "$GA_EX_USAGE"
TARGET="$(cd "$TARGET" && pwd)"
[ "$TARGET" = "$SRC" ] && ga_die "the target is GenericArch itself — nothing to install" "$GA_EX_USAGE"
[ -w "$TARGET" ] || ga_die "target is not writable: $TARGET" "$GA_EX_ERR"

# ── Which version is being installed ───────────────────────────────────────
# The manifest is named after this and uninstall.sh validates against it, so it must be a real
# release name rather than `git describe`'s v0.2.0-1-g5196c2e, which is not a version anyone can
# ask to uninstall.
GA_VERSION="${GA_VERSION:-}"
VERSION_NOTE=""
if [ -z "$GA_VERSION" ]; then
  if GA_VERSION="$(git -C "$SRC" describe --tags --exact-match 2>/dev/null)"; then
    VERSION_NOTE="HEAD is tagged"
  elif GA_VERSION="$(git -C "$SRC" tag --sort=-v:refname --merged HEAD 2>/dev/null | head -1)" \
       && [ -n "$GA_VERSION" ]; then
    VERSION_NOTE="newest tag reachable from HEAD — the checkout may be ahead of it"
  else
    ga_die "cannot determine a version for this checkout.
  Set one explicitly:  GA_VERSION=$GA_LATEST_VERSION ./install.sh" "$GA_EX_ERR"
  fi
fi
case "$GA_VERSION" in v*) ;; *) GA_VERSION="v$GA_VERSION" ;; esac
SOURCE_REF="$(git -C "$SRC" rev-parse HEAD 2>/dev/null || echo unknown)"

ga_hdr "GenericArch installer"
printf '  from     %s\n' "$SRC"
printf '  into     %s\n' "$TARGET"
printf '  version  %s%s%s' "$GA_BLD" "$GA_VERSION" "$GA_OFF"
[ -n "$VERSION_NOTE" ] && printf ' %s(%s)%s' "$GA_DIM" "$VERSION_NOTE" "$GA_OFF"
printf '\n'
if [ "$DRY_RUN" -eq 1 ]; then
  printf '  mode     %sdry run%s — the plan only, nothing is written\n' "$GA_YEL" "$GA_OFF"
else
  printf '  mode     %sapply%s\n' "$GA_GRN" "$GA_OFF"
fi
ga_is_supported_version "$GA_VERSION" \
  || ga_warn "$GA_VERSION is not in uninstall.sh's supported list ($GA_SUPPORTED_VERSIONS).
  The manifest will still drive a clean uninstall; only the no-manifest fallback is unavailable."

# ── 1. Compatibility gate — before the first write, not alongside it ───────
ga_hdr "── Compatibility ──────────────────────────────────────"
if ! ga_check_compatible "$TARGET"; then
  printf '  %sexpected%s  an Apple-platform Swift repo: %s\n' "$GA_BLD" "$GA_OFF" \
    "*.xcodeproj, *.xcworkspace, Package.swift, or any *.swift"
  printf '  %sfound%s     ' "$GA_BLD" "$GA_OFF"
  # shellcheck disable=SC2086  # space-separated marker list, split on purpose
  for m in $GA_COMPAT_FOREIGN; do printf '%s ' "$m"; done
  printf '\n'
  echo
  if [ "$FORCE_COMPAT" -eq 1 ]; then
    ga_warn "--force given — installing into a repo that identifies as something else.
  Every rule, skill and script below targets Apple platforms; in this repo most will be wrong."
  else
    ga_die "$TARGET is not a macOS/Swift project — nothing was written.
  GenericArch installs Swift-specific rules, skills and toolchain scripts; in this repo every
  one of them would be wrong. No files were copied.
  If this really is an Apple project the markers cannot see yet, re-run with --force." "$GA_EX_COMPAT"
  fi
fi
if [ "$GA_COMPAT_KIND" = "foreign" ]; then
  : # already reported above; only reachable with --force, and claiming a Swift project here would lie
elif [ "$GA_COMPAT_KIND" = "fresh" ]; then
  ga_ok "no conflicting project type found — treating this as a fresh repo"
  ga_dim "  Nothing identifies this repo yet. That is a supported starting point: install, then"
  ga_dim "  run /project-init to scaffold the project itself."
else
  printf '  %s✓%s Apple-platform Swift project —' "$GA_GRN" "$GA_OFF"
  # shellcheck disable=SC2086  # space-separated marker list, split on purpose
  for m in $GA_COMPAT_FOUND; do printf ' %s' "$m"; done
  printf '\n'
  [ -n "$GA_COMPAT_FOREIGN" ] && ga_warn "also found non-Swift build files:$GA_COMPAT_FOREIGN
  Proceeding because the Apple markers above decide it, but check this is the repo you meant."
fi
[ -d "$TARGET/.git" ] || ga_warn "target is not a git repository — you will not be able to diff or revert this"

# ── 2. Stage into a temp tree ──────────────────────────────────────────────
# Scripts/adopt.sh owns the authoritative list of what travels, the "nothing falls through the
# lists" gate, and the scaffolding rules. Pointing it at an EMPTY directory is what makes it usable
# as a stager: with no collisions to skip, everything it would ever install lands in one tree, and
# that tree becomes the plan. Duplicating its lists here is how the two would drift apart.
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/ga-install.XXXXXX")"
PLAN="$STAGE.plan"
ADOPT_LOG="$STAGE.adopt.log"
WROTE="$STAGE.wrote"
MANIFEST_TMP="$STAGE.manifest"
: > "$PLAN"; : > "$WROTE"

COMMITTED=0
cleanup_temp() { rm -rf "$STAGE" "$PLAN" "$ADOPT_LOG" "$WROTE" "$MANIFEST_TMP"; }

# Undo a partial commit. Only paths this run actually created are removed, and only backups this
# run actually took are restored — both read from $WROTE, never from a glob or a guess.
rollback() {
  [ "$COMMITTED" -eq 1 ] || return 0
  echo
  ga_warn "install failed part-way — rolling the target back"
  # Reverse order so a directory is considered only after the files inside it are gone.
  if [ -s "$WROTE" ]; then
    sed '1!G;h;$!d' "$WROTE" | while IFS="$(printf '\t')" read -r kind path extra; do
      case "$kind" in
        file)    rm -f "$TARGET/$path" ;;
        backup)  [ -f "$extra" ] && cp -p "$extra" "$TARGET/$path" ;;
        created) rm -f "$TARGET/$path" ;;
      esac
    done
  fi
  # Directories, deepest first; a directory holding anything of the target's own survives rmdir.
  awk -F'\t' '$1=="file" || $1=="created" {print $2}' "$WROTE" \
    | sed 's|/[^/]*$||' | sort -ru | while IFS= read -r d; do
      p="$TARGET/$d"
      while [ -d "$p" ] && [ "$p" != "$TARGET" ]; do
        rmdir "$p" 2>/dev/null || break
        p="$(dirname "$p")"
      done
    done
  rmdir "$TARGET/$GA_STATE_DIR/backups" "$TARGET/$GA_STATE_DIR" 2>/dev/null || true
  ga_warn "rolled back — no GenericArch files remain from this run"
}
trap 'rc=$?; rollback; cleanup_temp; exit $rc' INT TERM
trap 'rollback; cleanup_temp' EXIT

ga_hdr "── Staging ────────────────────────────────────────────"
if ! "$SRC/Scripts/adopt.sh" "$STAGE" --apply --quiet-next > "$ADOPT_LOG" 2>&1; then
  echo
  cat "$ADOPT_LOG" >&2
  ga_die "staging failed — Scripts/adopt.sh refused (output above). Nothing was written to the target." "$GA_EX_ERR"
fi
STAGED_COUNT=$(find "$STAGE" -type f | wc -l | tr -d ' ')
[ "$STAGED_COUNT" -gt 0 ] || ga_die "staging produced no files — refusing to continue" "$GA_EX_ERR"
ga_ok "staged $STAGED_COUNT file(s) into a temp tree"
LINKS=$(find "$STAGE" -type l | wc -l | tr -d ' ')
[ "$LINKS" -gt 0 ] && ga_warn "$LINKS symlink(s) in the staged tree are not installed — they are not part of the base"

# ── 3. Build the plan ──────────────────────────────────────────────────────
# A previous manifest lets this run re-assert ownership of files it installed before, which is what
# makes a re-install idempotent instead of quietly disowning everything it already put there.
PREV_MANIFEST=""
# shellcheck disable=SC2046  # one path per line, none of them contain spaces
for m in $(ga_manifest_find "$TARGET"); do PREV_MANIFEST="$m"; done
if [ -n "$PREV_MANIFEST" ]; then
  ga_dim "  found a previous install: ${PREV_MANIFEST#"$TARGET"/} ($(ga_manifest_version "$PREV_MANIFEST"))"
fi

n_create=0; n_adopt=0; n_keep=0; n_skip=0

while IFS= read -r rel; do
  staged="$STAGE/$rel"
  tgt="$TARGET/$rel"
  ssha="$(ga_sha256 "$staged")"
  if [ ! -e "$tgt" ]; then
    printf 'create\t%s\t%s\t1\n' "$rel" "$ssha" >> "$PLAN"; n_create=$((n_create + 1)); continue
  fi
  tsha="$(ga_sha256 "$tgt" || echo "")"
  if [ "$tsha" = "$ssha" ]; then
    # Byte-identical to what GenericArch ships. That IS the proof of ownership the uninstall
    # contract asks for, so record it as ours without rewriting it.
    printf 'adopt\t%s\t%s\t0\n' "$rel" "$tsha" >> "$PLAN"; n_adopt=$((n_adopt + 1)); continue
  fi
  prev=""
  if [ -n "$PREV_MANIFEST" ]; then prev="$(ga_manifest_record_for "$PREV_MANIFEST" "$rel")"; fi
  if [ -n "$prev" ] && [ "$(ga_json_field "$prev" action)" = "created" ] \
     && [ "$(ga_json_field "$prev" sha256)" = "$tsha" ]; then
    # We installed it, it is untouched since, and the base has moved on. Not ours to overwrite —
    # Scripts/adopt-review.sh is the tool for taking an update.
    printf 'keep\t%s\t%s\t0\n' "$rel" "$tsha" >> "$PLAN"; n_keep=$((n_keep + 1)); continue
  fi
  printf 'skip\t%s\t%s\t0\n' "$rel" "$tsha" >> "$PLAN"; n_skip=$((n_skip + 1))
done <<EOF
$(cd "$STAGE" && find . -type f -print | sed 's|^\./||' | LC_ALL=C sort)
EOF

# The one file GenericArch edits rather than creates: .gitignore gains the paths its own tooling
# generates. Delimited, idempotent, backed up, and removed again by uninstall.sh.
GITIGNORE_ACTION="none"
if ! ga_block_present "$TARGET/.gitignore"; then
  if [ -f "$TARGET/.gitignore" ]; then GITIGNORE_ACTION="modify"; else GITIGNORE_ACTION="create"; fi
fi

ga_hdr "── Plan: $(wc -l < "$PLAN" | tr -d ' ') file(s) ────────────────────────────────"
echo
if [ "$n_create" -gt 0 ]; then
  printf '%s  create%s — new files, none of yours touched\n' "$GA_BLD" "$GA_OFF"
  awk -F'\t' '$1=="create" {print "    + " $2}' "$PLAN"
fi
if [ "$n_adopt" -gt 0 ]; then
  printf '\n%s  already present, identical%s — recorded as ours, not rewritten\n' "$GA_BLD" "$GA_OFF"
  awk -F'\t' '$1=="adopt" {print "    = " $2}' "$PLAN"
fi
if [ "$n_keep" -gt 0 ]; then
  printf '\n%s  installed earlier, base has moved%s — left as-is (see Scripts/adopt-review.sh)\n' "$GA_BLD" "$GA_OFF"
  awk -F'\t' '$1=="keep" {print "    ~ " $2}' "$PLAN"
fi
if [ "$n_skip" -gt 0 ]; then
  printf '\n%s  yours — skipped, kept exactly as they are%s\n' "$GA_YEL" "$GA_OFF"
  awk -F'\t' '$1=="skip" {print "    · " $2}' "$PLAN"
fi
case "$GITIGNORE_ACTION" in
  modify) printf '\n%s  append%s — .gitignore gains a managed block (original backed up first)\n' "$GA_BLD" "$GA_OFF"
          printf '    ~ .gitignore  %s.claude/claude-tasks/ and dist/%s\n' "$GA_DIM" "$GA_OFF" ;;
  create) printf '\n%s  create%s — .gitignore\n' "$GA_BLD" "$GA_OFF"
          printf '    + .gitignore  %s.claude/claude-tasks/ and dist/%s\n' "$GA_DIM" "$GA_OFF" ;;
  none)   [ -f "$TARGET/.gitignore" ] && printf '\n%s  .gitignore already carries the managed block — unchanged%s\n' "$GA_DIM" "$GA_OFF" ;;
esac
printf '\n%s  manifest%s\n' "$GA_BLD" "$GA_OFF"
printf '    + %s/manifest-%s.json  %swritten last, on full success only%s\n' \
  "$GA_STATE_DIR" "$GA_VERSION" "$GA_DIM" "$GA_OFF"

echo
printf '%s───────────────────────────────────────────────────────%s\n' "$GA_BLD" "$GA_OFF"
printf '%d create · %d already ours · %d left at older version · %d yours (skipped)\n' \
  "$n_create" "$n_adopt" "$n_keep" "$n_skip"
[ "$n_skip" -gt 0 ] && ga_dim "Nothing in the skipped list is read, moved or rewritten."

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  ga_dim "Dry run — nothing was written. Re-run without --dry-run to apply."
  COMMITTED=0
  exit "$GA_EX_OK"
fi

if [ "$n_create" -eq 0 ] && [ "$GITIGNORE_ACTION" = "none" ]; then
  echo
  ga_ok "already installed and up to date — nothing to write"
  ga_dim "Refreshing the manifest so it reflects what is on disk now."
fi

echo
if ! ga_confirm "Install into $TARGET?"; then
  echo
  ga_dim "Aborted — nothing was written."
  COMMITTED=0
  exit "$GA_EX_ABORT"
fi

# ── 4. Commit ──────────────────────────────────────────────────────────────
COMMITTED=1
INSTALLED_AT="$(ga_now_iso)"
ga_manifest_begin "$MANIFEST_TMP"
BACKUP_DIR="$TARGET/$GA_STATE_DIR/backups"

ga_hdr "── Installing ─────────────────────────────────────────"
while IFS="$(printf '\t')" read -r act rel sha needs_write; do
  if [ "$needs_write" = "1" ]; then
    mkdir -p "$(dirname "$TARGET/$rel")"
    cp -p "$STAGE/$rel" "$TARGET/$rel"
    printf 'file\t%s\t\n' "$rel" >> "$WROTE"
    sha="$(ga_sha256 "$TARGET/$rel")"
  fi
  case "$act" in
    skip) ga_manifest_add "$rel" skipped   "$sha" "$(ga_mtime_iso "$TARGET/$rel")" "" "$GA_VERSION" ;;
    *)    ga_manifest_add "$rel" created   "$sha" "$(ga_mtime_iso "$TARGET/$rel")" "" "$GA_VERSION" ;;
  esac
done < "$PLAN"
ga_ok "wrote $n_create file(s)"

case "$GITIGNORE_ACTION" in
  modify)
    orig_sha="$(ga_sha256 "$TARGET/.gitignore")"
    mkdir -p "$BACKUP_DIR"
    backup_rel="$GA_STATE_DIR/backups/gitignore.$GA_VERSION.bak"
    cp -p "$TARGET/.gitignore" "$TARGET/$backup_rel"
    printf 'backup\t%s\t%s\n' ".gitignore" "$TARGET/$backup_rel" >> "$WROTE"
    printf 'file\t%s\t\n' "$backup_rel" >> "$WROTE"
    ga_block_append "$TARGET/.gitignore" ".claude/claude-tasks/" "dist/"
    ga_manifest_add ".gitignore" modified "$(ga_sha256 "$TARGET/.gitignore")" \
      "$(ga_mtime_iso "$TARGET/.gitignore")" "$backup_rel" "$GA_VERSION" "$orig_sha"
    ga_ok "appended the managed block to .gitignore (original at $backup_rel)"
    ;;
  create)
    ga_block_append "$TARGET/.gitignore" ".claude/claude-tasks/" "dist/"
    printf 'file\t%s\t\n' ".gitignore" >> "$WROTE"
    ga_manifest_add ".gitignore" created "$(ga_sha256 "$TARGET/.gitignore")" \
      "$(ga_mtime_iso "$TARGET/.gitignore")" "" "$GA_VERSION"
    ga_ok "created .gitignore with the managed block"
    ;;
  none)
    # The block is already in place from an earlier run. Its record still has to be carried into
    # THIS manifest — the manifest is a complete statement of what GenericArch owns, not a diff.
    # Dropping it here is how a re-install would quietly orphan the block and its backup, leaving
    # uninstall with nothing to restore.
    if ga_block_present "$TARGET/.gitignore"; then
      prev_gi=""
      [ -n "$PREV_MANIFEST" ] && prev_gi="$(ga_manifest_record_for "$PREV_MANIFEST" ".gitignore")"
      gi_backup=""; gi_orig=""; gi_act="modified"
      if [ -n "$prev_gi" ]; then
        gi_backup="$(ga_json_field "$prev_gi" backup || true)"
        gi_orig="$(ga_json_field "$prev_gi" original_sha256 || true)"
        # A recorded backup that is no longer on disk must not be promised to uninstall.
        if [ -n "$gi_backup" ] && [ ! -f "$TARGET/$gi_backup" ]; then gi_backup=""; gi_orig=""; fi
        [ "$(ga_json_field "$prev_gi" action)" = "created" ] && gi_act="created"
      fi
      # Self-heal: the backup is on disk but no record points at it — the manifest was deleted, or
      # written by a version that did not carry it forward. Adopt it rather than abandoning a
      # perfectly good original, and derive the pre-install hash from the backup itself, which is
      # the only remaining evidence of what that file used to be.
      if [ -z "$gi_backup" ]; then
        gi_cand="$GA_STATE_DIR/backups/gitignore.$GA_VERSION.bak"
        if [ -f "$TARGET/$gi_cand" ]; then
          gi_backup="$gi_cand"
          gi_orig="$(ga_sha256 "$TARGET/$gi_cand")"
          ga_dim "  recovered an orphaned .gitignore backup: $gi_cand"
        fi
      fi
      ga_manifest_add ".gitignore" "$gi_act" "$(ga_sha256 "$TARGET/.gitignore")" \
        "$(ga_mtime_iso "$TARGET/.gitignore")" "$gi_backup" "$GA_VERSION" "$gi_orig"
      ga_dim "  .gitignore already carries the managed block — record carried forward"
    fi
    ;;
esac

# ── 5. Manifest last ───────────────────────────────────────────────────────
MANIFEST="$(ga_manifest_path "$TARGET" "$GA_VERSION")"
ga_manifest_commit "$MANIFEST" "$GA_VERSION" "$TARGET" "$SOURCE_REF" "$INSTALLED_AT"
printf 'file\t%s\t\n' "${MANIFEST#"$TARGET"/}" >> "$WROTE"
ga_ok "manifest written: ${MANIFEST#"$TARGET"/}"

COMMITTED=0   # past the point of rollback — the install is complete
trap - INT TERM
trap 'cleanup_temp' EXIT

ga_hdr "Installed $GA_VERSION"
cat <<NEXT

  1. ${GA_BLD}/project-init${GA_OFF}
       Reads your CLAUDE.md in full, builds the rule-conflict table, and asks per conflict.
       Your rules win by default; nothing is overwritten without an explicit yes.
  2. ${GA_BLD}/gaps${GA_OFF}
       Derives each gap's status from your code instead of asking.
  3. ${GA_BLD}./Scripts/detect-toolchain.sh${GA_OFF}
       Your project defines the baseline, not GenericArch's numbers.

${GA_DIM}No CLAUDE.md was written. Your rules stay yours until you decide otherwise.
To remove everything again:  ./uninstall.sh $GA_VERSION${GA_OFF}
NEXT
exit "$GA_EX_OK"
