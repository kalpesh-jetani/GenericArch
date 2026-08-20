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
ROOT_OK=0
MODE=""
WITH_ARCH=0
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)      GA_ASSUME_YES=1; shift ;;
    -n|--dry-run)  DRY_RUN=1; shift ;;
    -f|--force)    FORCE_COMPAT=1; shift ;;
    --root-ok)     ROOT_OK=1; shift ;;
    --with-architecture) WITH_ARCH=1; shift ;;
    --mode)        [ $# -ge 2 ] || ga_die "--mode needs existing or new" "$GA_EX_USAGE"
                   case "$2" in existing|new) MODE="$2" ;; *) ga_die "--mode takes existing or new, not $2" "$GA_EX_USAGE" ;; esac
                   shift 2 ;;
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

# ── One install per repo, at one root ──────────────────────────────────────
# The failure this prevents: the layer installed at a repo root AND at the nested Xcode-project
# directory beside it. Both copies are live, the commands and skills are duplicated under names
# Claude resolves ambiguously, and only one of them has a manifest — so the other can never be
# uninstalled. That cost three commits to create and one hand cleanup to undo, and the second
# install had no way to know the first existed.
#
# So: look up to the git root and down one level for an existing footprint, and refuse rather than
# create the second one. --root-ok is the operator's override for the case where two independent
# products genuinely share a checkout.
ga_footprint_at() {
  [ -d "$1/$GA_STATE_DIR" ] || [ -d "$1/.claude/commands" ]
}
OTHER_ROOT=""
# Compare PHYSICAL paths on both sides. `git rev-parse` resolves symlinks and `cd`+`pwd` does not,
# so on a symlinked tree (/var → /private/var on macOS, or any repo reached through a link) the
# same directory compares unequal and the target is reported as a second root against itself.
TARGET_P="$(cd "$TARGET" && pwd -P)"
GIT_ROOT="$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null || echo "")"
if [ -n "$GIT_ROOT" ]; then
  GIT_ROOT_P="$(cd "$GIT_ROOT" 2>/dev/null && pwd -P || echo "$GIT_ROOT")"
  if [ "$GIT_ROOT_P" != "$TARGET_P" ] && ga_footprint_at "$GIT_ROOT"; then
    OTHER_ROOT="$GIT_ROOT"
  fi
fi
if [ -z "$OTHER_ROOT" ]; then
  for d in "$TARGET"/*/; do
    d="${d%/}"
    [ -d "$d" ] || continue
    case "${d##*/}" in .*|Packages|Scripts|docs) continue ;; esac
    if ga_footprint_at "$d"; then OTHER_ROOT="$d"; break; fi
  done
fi
if [ -n "$OTHER_ROOT" ] && [ "$ROOT_OK" -eq 0 ]; then
  installed_ver="unknown"
  for m in $(ga_manifest_find "$OTHER_ROOT"); do installed_ver="$(ga_manifest_version "$m")"; done
  ga_die "GenericArch is already installed at another root in this checkout:
    here:      $TARGET
    already:   $OTHER_ROOT  ($installed_ver)
  Two live copies duplicate every command and skill, and only one of them can be uninstalled.
  Install into that root instead, or upgrade it:  ./install.sh \"$OTHER_ROOT\"
  If two products really do share this checkout, re-run with --root-ok." "$GA_EX_ERR"
fi
[ -n "$OTHER_ROOT" ] && ga_warn "--root-ok given — a second footprint exists at $OTHER_ROOT.
  Every command and skill now resolves ambiguously between the two."

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

# ── Which of the two installs this is ──────────────────────────────────────
# They differ in exactly one thing: whether the target gets the predefined MODULE material.
#
#   existing — a repo that already has a shape. It gets rules, indexes and tooling and NOTHING
#              module-shaped: no Packages/, no docs/modules/, no scaffold. Imposing a layout on a
#              codebase that already has one is the adoption failure /project-init exists to avoid,
#              and a module doc for a package the repo does not have is a dead lookup forever.
#
#   new      — a repo with no shape yet. The module material is exactly what it needs, so it also
#              gets Scaffold/ and ga-scaffold.sh: the predefined structure, the seed packages, and
#              the notes that turn "which layers?" into a decision instead of a guess.
#
# Derived from the same compatibility gate above, so the two can never disagree. --mode overrides it
# for the case the markers get wrong — a repo cleared out to be rebuilt, say.
if [ -z "$MODE" ]; then
  case "$GA_COMPAT_KIND" in
    fresh) MODE="new" ;;
    *)     MODE="existing" ;;
  esac
  MODE_WHY="derived from the compatibility gate"
else
  MODE_WHY="given with --mode"
fi
printf '\n  %sinstall mode%s  %s%s%s  %s(%s)%s\n' \
  "$GA_BLD" "$GA_OFF" "$GA_BLD" "$MODE" "$GA_OFF" "$GA_DIM" "$MODE_WHY" "$GA_OFF"
if [ "$MODE" = "new" ]; then
  ga_dim "  Adds the scaffold: Scaffold/LAYOUT.tsv, its templates, the architecture notes, and"
  ga_dim "  ga-scaffold.sh — the predefined structure and seed packages, applied when you run it."
elif [ "$WITH_ARCH" -eq 1 ]; then
  ga_dim "  --with-architecture given: new-feature and /review come too. Take this only once the"
  ga_dim "  product has actually adopted §2/§3 — /project-init is where that is decided."
else
  ga_dim "  Tooling and lookup only. No Packages/, no docs/modules/, no scaffold — and no new-feature"
  ga_dim "  or /review, because both enforce an architecture this repo has not adopted: new-feature"
  ga_dim "  would scaffold a package the app cannot consume, /review would report rules you declined."
  ga_dim "  /project-init offers them once the rule-conflict table is settled."
fi

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
ADOPT_ARGS="--apply --quiet-next"
[ "$MODE" = "new" ] && ADOPT_ARGS="$ADOPT_ARGS --fresh"
# --fresh implies it inside adopt.sh — starting a repo from this base IS the decision — so this only
# ever adds it for an existing repo whose operator asked.
[ "$WITH_ARCH" -eq 1 ] && ADOPT_ARGS="$ADOPT_ARGS --with-architecture"
# shellcheck disable=SC2086  # deliberate word splitting of a flag list
if ! "$SRC/Scripts/adopt.sh" "$STAGE" $ADOPT_ARGS > "$ADOPT_LOG" 2>&1; then
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

n_create=0; n_adopt=0; n_keep=0; n_skip=0; n_declined=0

while IFS= read -r rel; do
  staged="$STAGE/$rel"
  tgt="$TARGET/$rel"
  ssha="$(ga_sha256 "$staged")"
  if [ ! -e "$tgt" ]; then
    # Not on disk is not the same as never installed. A path this product DECLINED carries a
    # tombstone, and re-creating it is how a recorded decision gets silently reversed — four times,
    # in the adoption that made this check necessary.
    if ga_tombstoned "$TARGET" "$rel"; then
      printf 'declined\t%s\t%s\t0\n' "$rel" "$ssha" >> "$PLAN"; n_declined=$((n_declined + 1)); continue
    fi
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
if [ "$n_declined" -gt 0 ]; then
  printf '\n%s  declined by this product%s — not created; see %s/%s\n' \
    "$GA_BLD" "$GA_OFF" "$GA_STATE_DIR" "$GA_TOMBSTONES"
  awk -F'\t' '$1=="declined" {print "    ⊘ " $2}' "$PLAN"
  ga_dim "    To take one back: ./Scripts/ga-remove.sh --revive <path> --apply, then re-run."
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
printf '%d create · %d already ours · %d left at older version · %d yours (skipped) · %d declined\n' \
  "$n_create" "$n_adopt" "$n_keep" "$n_skip" "$n_declined"
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
    # Recorded so the manifest is a complete statement of what GenericArch would own here, and so
    # `declined` survives a re-install rather than being re-derived from the tombstone file alone.
    declined) ga_manifest_add "$rel" declined "$sha" "$(ga_now_iso)" "" "$GA_VERSION" ;;
    skip)     ga_manifest_add "$rel" skipped  "$sha" "$(ga_mtime_iso "$TARGET/$rel")" "" "$GA_VERSION" ;;
    *)        ga_manifest_add "$rel" created  "$sha" "$(ga_mtime_iso "$TARGET/$rel")" "" "$GA_VERSION" ;;
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
    ga_block_append "$TARGET/.gitignore" ".claude/claude-tasks/" ".claude/notes/.evidence/" "dist/"
    ga_manifest_add ".gitignore" modified "$(ga_sha256 "$TARGET/.gitignore")" \
      "$(ga_mtime_iso "$TARGET/.gitignore")" "$backup_rel" "$GA_VERSION" "$orig_sha"
    ga_ok "appended the managed block to .gitignore (original at $backup_rel)"
    ;;
  create)
    ga_block_append "$TARGET/.gitignore" ".claude/claude-tasks/" ".claude/notes/.evidence/" "dist/"
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

# The first step in the ledger. Every command gates on this, so an install that did not record it
# would block the whole sequence it just enabled.
ga_step_record "$TARGET" install "$MODE install of $GA_VERSION from $SOURCE_REF"
if [ "$MODE" = "existing" ]; then
  # Not applicable rather than pending: this repo has a structure, so the step will never run and a
  # gate that waits for it forever would block every command behind it.
  ga_step_record "$TARGET" scaffold "not applicable: existing repo keeps its own structure"
fi

if [ "$MODE" = "new" ]; then
  # Every escape passed as an argument: the here-doc below expands $SCAFFOLD_STEP but does not
  # re-expand what is inside it, so a ${GA_BLD} written into the format string arrives literally.
  SCAFFOLD_STEP="$(printf '%s./Scripts/ga-scaffold.sh . --list%s
       Read %sScaffold/ARCHITECTURE-OPTIONS.md%s, choose your layers, then:
         ./Scripts/ga-scaffold.sh . --with navigation,design,storage,messaging --apply
       It creates the structure, seeds Core and DIKit, and records what you chose.' \
    "$GA_BLD" "$GA_OFF" "$GA_BLD" "$GA_OFF")"
else
  SCAFFOLD_STEP="$(printf '%sscaffold — not applicable%s
       Your repo has its own structure. Recorded, so nothing waits on it.' "$GA_DIM" "$GA_OFF")"
fi

ga_hdr "Installed $GA_VERSION ($MODE$([ "$WITH_ARCH" -eq 1 ] && printf ', with architecture'))"
cat <<NEXT

  The commands run ${GA_BLD}in this order${GA_OFF} — each one leaves the repo in the state the next assumes.
  ${GA_DIM}./Scripts/ga-step.sh show${GA_OFF} at any point says where you are and what is next.

  1. ${SCAFFOLD_STEP}
  2. ${GA_BLD}/project-init${GA_OFF}
       Reads your CLAUDE.md in full, builds the rule-conflict table, and asks per conflict.
       Your rules win by default; nothing is overwritten without an explicit yes.
  3. ${GA_BLD}/gaps${GA_OFF}
       Derives each gap's status from your code instead of asking.
  4. ${GA_BLD}/sync-app-notes${GA_OFF}
       Builds the nine inventories every later lookup reads instead of searching.

  Then the repo is ${GA_BLD}ready${GA_OFF}: skills, /find, /decide, /learn, /review, /verify, /build.

${GA_DIM}Also: ./Scripts/detect-toolchain.sh — your project defines the baseline, not GenericArch's numbers.
No CLAUDE.md was written. Your rules stay yours until you decide otherwise.
To decline a file so no later install re-creates it:  ./Scripts/ga-remove.sh <path> --reason "..."
To remove everything again:  ./uninstall.sh $GA_VERSION${GA_OFF}
NEXT
exit "$GA_EX_OK"
