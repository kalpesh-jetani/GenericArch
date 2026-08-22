#!/usr/bin/env bash
# Install GenericArch into a target repo — additively, atomically, and reversibly.
#
#   ./install.sh                      # plan for the current directory, then ask
#   ./install.sh /path/to/TargetRepo  # plan for somewhere else
#   ./install.sh --dry-run            # print the plan and stop
#   ./install.sh --yes                # skip the confirmation prompt
#   ./install.sh --force              # install even if the repo identifies as non-Apple
#   ./install.sh --project-setup      # always run the Xcode project setup step first
#   ./install.sh --no-project-setup   # never offer it
#   ./install.sh --no-preflight       # skip the /project-init evidence scan at the end
#   ./install.sh --in-place           # upgrade over an existing install instead of uninstalling first
#   ./install.sh --with-claude-md     # take GenericArch's CLAUDE.md; yours is kept at CLAUDE-BK.md
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
# Exit codes: 0 ok · 1 error · 2 usage · 3 incompatible target · 4 declined · 6 uninstall first ·
#             78 not macOS
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
  sed -n '2,18p' "$0"
  echo
  echo "Exit codes: 0 ok · 1 error · 2 usage · 3 incompatible target · 4 declined · 6 uninstall first"
  echo "            78 not macOS"
}

TARGET=""
DRY_RUN=0
FORCE_COMPAT=0
ROOT_OK=0
WITH_ARCH=0
WITH_CLAUDE=0
IN_PLACE=0     # upgrade over an older install instead of refusing until it is uninstalled
PROJECT_SETUP=""   # "" ask when it applies · yes always · no never
PREFLIGHT=1        # run the /project-init evidence scan once the install has landed
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)      GA_ASSUME_YES=1; shift ;;
    -n|--dry-run)  DRY_RUN=1; shift ;;
    -f|--force)    FORCE_COMPAT=1; shift ;;
    --root-ok)     ROOT_OK=1; shift ;;
    --with-architecture) WITH_ARCH=1; shift ;;
    --with-claude-md)    WITH_CLAUDE=1; shift ;;
    --in-place)          IN_PLACE=1; shift ;;
    --project-setup)    PROJECT_SETUP="yes"; shift ;;
    --no-project-setup) PROJECT_SETUP="no"; shift ;;
    --no-preflight)     PREFLIGHT=0; shift ;;
    --mode)        [ $# -ge 2 ] || ga_die "--mode needs existing or new" "$GA_EX_USAGE"
                   ga_die "--mode is gone: this base installs into a repo that already has its own
  structure, and there is nothing else to be. A repo with no shape yet gets its package layout from
  GenericXCodeSetup instead: https://github.com/kalpesh-jetani/GenericXCodeSetup" "$GA_EX_USAGE"
                   shift 2 ;;
    --target)      [ $# -ge 2 ] || ga_die "--target needs a directory" "$GA_EX_USAGE"
                   TARGET="$2"; shift 2 ;;
    -h|--help)     usage; exit "$GA_EX_OK" ;;
    '#')           ga_die "a '#' comment reached this script as an argument — your shell did not
  strip it (zsh does not, by default). Paste the command without its trailing comment, or run:
      setopt interactive_comments" "$GA_EX_USAGE" ;;
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
# ga_footprint_at lives in ga-lifecycle.sh: uninstall.sh needs the same test, so that it never
# reports "back to its pre-install state" while a second copy is still live in the checkout.
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
# Tolerate a manifest this version cannot parse. The value is display-only, and under `set -e` a
# failing command substitution here killed the installer with no output at all — the one message
# the operator needed was the one that could not be printed.
OTHER_VERSION=""
if [ -n "$OTHER_ROOT" ]; then
  OTHER_VERSION="unknown"
  # shellcheck disable=SC2046  # one path per line, none of them contain spaces
  for m in $(ga_manifest_find "$OTHER_ROOT"); do
    OTHER_VERSION="$(ga_manifest_version "$m" 2>/dev/null || true)"
    [ -n "$OTHER_VERSION" ] || OTHER_VERSION="unreadable manifest"
  done
fi
if [ -n "$OTHER_ROOT" ] && [ "$ROOT_OK" -eq 0 ]; then
  installed_ver="$OTHER_VERSION"
  # Name a command the caller can actually run. Via bootstrap.sh there is no local install.sh — the
  # clone it used is a temp dir — so advising `./install.sh` sent people to a file they do not have.
  if [ "${GA_VIA_BOOTSTRAP:-0}" = "1" ]; then
    # bootstrap.sh installs into $(pwd) without cd-ing, so PWD is the repo the operator downloaded
    # it into — but only name the file if it is really there, or the advice is wrong again.
    if [ -f "$PWD/bootstrap.sh" ]; then _bs="bash \"$PWD/bootstrap.sh\""; else _bs="bash bootstrap.sh"; fi
    _fix_there="cd \"$OTHER_ROOT\" && $_bs --apply"
    _fix_both="bash bootstrap.sh --apply --root-ok"
  else
    _fix_there="./install.sh \"$OTHER_ROOT\""
    _fix_both="./install.sh \"$TARGET\" --root-ok"
  fi
  ga_die "GenericArch is already installed at another root in this checkout:
    here:      $TARGET
    already:   $OTHER_ROOT  ($installed_ver)
  Two live copies duplicate every command and skill, and only one of them can be uninstalled.

  Install into that root instead, or upgrade it:
      $_fix_there
  If two products really do share this checkout:
      $_fix_both" "$GA_EX_ERR"
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

# ── One version at a time ──────────────────────────────────────────────────
# Re-running the installer over an OLDER install is not an upgrade, and the summary line is the
# only thing that says so. A file we installed, that the operator never touched, and that the base
# has since changed, is classified `keep` and printed as "left at older version". Only shared
# libraries move forward, and only because their callers break otherwise. So a v0.4.2 → v0.5.0
# run leaves most of v0.4.2 on disk under a v0.5.0 manifest.
#
# Uninstalling first rewrites the whole tree, and costs nothing: uninstall.sh removes a file only
# while its hash still proves the file is ours, so anything edited survives, and
# safetodelete-after-migration-note.md carries it into this install as an `orphan` row.
#
# Same version is NOT gated — that is the repair run PREV_MANIFEST was built for: re-assert
# ownership, fill in what is missing, rewrite nothing.
PREV_MANIFEST=""
# shellcheck disable=SC2046  # one path per line, none of them contain spaces
for m in $(ga_manifest_find "$TARGET"); do PREV_MANIFEST="$m"; done
PREV_VERSION=""
if [ -n "$PREV_MANIFEST" ]; then
  PREV_VERSION="$(ga_manifest_version "$PREV_MANIFEST" 2>/dev/null || true)"
  # A manifest whose version cannot be read is worse than an old one, not better: nothing can name
  # the uninstall that matches it. Say that instead of printing an uninstall command built from an
  # error string.
  if [ -z "$PREV_VERSION" ] && [ "$IN_PLACE" -eq 0 ]; then
    ga_die "$TARGET has a GenericArch manifest this version cannot read:
    ${PREV_MANIFEST#"$TARGET"/}

  Its recorded version is what names the uninstall that matches it, so nothing here can tell you
  which one to run. Read the file — \"genericarch_version\" is on the third line — and uninstall
  that version, or pass --in-place to install over it and leave whatever it installed behind.

  Nothing was written." "$GA_EX_UPGRADE"
  fi
fi
if [ -n "$PREV_VERSION" ] && [ "$PREV_VERSION" != "$GA_VERSION" ] && [ "$IN_PLACE" -eq 0 ]; then
  # Name a command the caller can actually run. uninstall.sh ships INTO the target, so the copy
  # that matches the recorded manifest is the one already there — not this checkout's.
  # `cd` rather than --target: the path is long, and naming it twice on one line is a command
  # nobody reads before pasting.
  if [ -f "$TARGET/uninstall.sh" ]; then
    if [ "$TARGET" = "$PWD" ]; then _un="./uninstall.sh $PREV_VERSION"
    else _un="(cd \"$TARGET\" && ./uninstall.sh $PREV_VERSION)"; fi
  else
    _un="# uninstall.sh is missing from $TARGET — fetch $PREV_VERSION and run its uninstall.sh there"
  fi
  if [ "${GA_VIA_BOOTSTRAP:-0}" = "1" ]; then
    if [ -f "$PWD/bootstrap.sh" ]; then _re="bash \"$PWD/bootstrap.sh\" --apply"; else _re="bash bootstrap.sh --apply"; fi
  else
    _re="./install.sh \"$TARGET\""
  fi
  ga_die "$TARGET already has GenericArch $PREV_VERSION installed, and this is $GA_VERSION.
    manifest:  ${PREV_MANIFEST#"$TARGET"/}

  Installing over it is not an upgrade. Every file we installed and you did not touch is left at
  the version it already had — the plan reports them as 'left at older version' and moves on. Only
  shared libraries are carried forward, because the scripts that source them break otherwise.

  Remove $PREV_VERSION first, then install this one:
      $_un
      $_re

  Nothing of yours is lost in between: a file is removed only while its hash still proves it is
  ours, so anything you edited stays exactly where it is. uninstall.sh lists those in
  safetodelete-after-migration-note.md, and this installer picks them up from there on the way
  back in.

  To upgrade in place anyway, with the older files left behind:
      $_re --in-place

  Nothing was written." "$GA_EX_UPGRADE"
fi

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
  # Reported, not welcomed: the refusal follows a few lines down. Saying "supported starting point"
  # here and then refusing would read as a bug in the gate.
  ga_warn "nothing identifies this repo yet — no project, no structure"
else
  printf '  %s✓%s Apple-platform Swift project —' "$GA_GRN" "$GA_OFF"
  # shellcheck disable=SC2086  # space-separated marker list, split on purpose
  for m in $GA_COMPAT_FOUND; do printf ' %s' "$m"; done
  printf '\n'
  [ -n "$GA_COMPAT_FOREIGN" ] && ga_warn "also found non-Swift build files:$GA_COMPAT_FOREIGN
  Proceeding because the Apple markers above decide it, but check this is the repo you meant."
fi
[ -d "$TARGET/.git" ] || ga_warn "target is not a git repository — you will not be able to diff or revert this"

# --root-ok means "two independent products genuinely share this checkout". The markers the gate
# just found can DISPROVE that: if every project marker resolves inside the other root, there is
# one product here and this target is a wrapper directory. The gate above cannot see this — it runs
# before compatibility, because it must refuse before anything is staged — so the finding is
# carried to the confirmation prompt instead, which is where consent is actually given.
# Not a refusal: --root-ok is the operator's override and stays one. It just stops being silent.
ONE_PRODUCT=""
case "$OTHER_ROOT" in
  "$TARGET"/*)
    _rel_other="${OTHER_ROOT#"$TARGET"/}"
    _markers=0; _outside=0
    # Only PATH-shaped markers can be located. The *.swift hit is recorded as the literal glob, not
    # as where it was found, so it says nothing about which directory the product lives in.
    # shellcheck disable=SC2086  # space-separated marker list, split on purpose
    for m in $GA_COMPAT_FOUND; do
      case "$m" in
        *.xcodeproj|*.xcworkspace|Package.swift|*.playground|*/*)
          _markers=$((_markers + 1))
          case "$m" in "$_rel_other"/*) ;; *) _outside=1 ;; esac ;;
      esac
    done
    [ "$_markers" -gt 0 ] && [ "$_outside" -eq 0 ] && ONE_PRODUCT="$_rel_other"
    ;;
esac

# ── Which of the two installs this is ──────────────────────────────────────
# They differ in exactly one thing: whether the target gets the predefined MODULE material.
#
#   existing — a repo that already has a shape. It gets rules, indexes and tooling and NOTHING
#              module-shaped: no Packages/, no docs/modules/, no scaffold. Imposing a layout on a
#              codebase that already has one is the adoption failure /project-init exists to avoid,
#              and a module doc for a package the repo does not have is a dead lookup forever.
#
# There is no second kind. A repo with no shape yet has nothing for these rules to reconcile
# against, and the package layout it needs is a different tool's job.
if [ "$GA_COMPAT_KIND" = "fresh" ]; then
  ga_die "$TARGET has no project and no structure yet — nothing here to install into.

  This base installs into a repo that ALREADY has its Xcode project: it reconciles rules against
  what is true there and records a manifest of every file it wrote, so the install is reversible.
  Neither means anything in an empty directory.

  Create the project and its package layout first:
      https://github.com/kalpesh-jetani/GenericXCodeSetup

  Then run this again. Nothing was written." "$GA_EX_COMPAT"
fi
if [ "$WITH_ARCH" -eq 1 ]; then
  ga_dim "  --with-architecture given: new-feature and /review come too. Take this only once the"
  ga_dim "  product has actually adopted §2/§3 — /project-init is where that is decided."
else
  ga_dim "  Tooling and lookup only. No Packages/, no docs/modules/, no scaffold — and no new-feature"
  ga_dim "  or /review, because both enforce an architecture this repo has not adopted: new-feature"
  ga_dim "  would scaffold a package the app cannot consume, /review would report rules you declined."
  ga_dim "  /project-init offers them once the rule-conflict table is settled."
fi

# ── 1a. The build the target already has ───────────────────────────────────
# A deployment floor above the installed SDK, or a language mode the compiler cannot provide, means
# that repo does not build as configured — and /project-init refuses to adopt docs onto it
# (Scripts/ga-init-scan.sh exits 3 on the same row). This install is not refused for it: rules,
# indexes and tooling are still correct in a repo whose floors need lowering, and blocking a
# docs-and-tooling adoption on an unrelated build problem would leave --force as the only way past.
# So it is said out loud, here, before the operator spends a session on the next step.
#
# Only for an existing repo: a fresh one has no project settings to mismatch yet, and
# ga-project-setup.sh below asks for its floors against the installed SDK anyway.
if [ "$DRY_RUN" -eq 0 ] && [ -x "$SRC/Scripts/detect-toolchain.sh" ]; then
  TC_BLOCKING="$(NO_COLOR=1 "$SRC/Scripts/detect-toolchain.sh" --mismatches --root "$TARGET" 2>/dev/null \
                 | grep '^BLOCKING' || true)"
  if [ -n "$TC_BLOCKING" ]; then
    echo
    ga_warn "this repo does not build as configured — the install continues, /project-init will not:"
    printf '%s\n' "$TC_BLOCKING" | while IFS='|' read -r _sev _id _what _cur _avail _fix; do
      printf '    %s%s%s — %s, available %s\n' "$GA_BLD" "$_what" "$GA_OFF" "$_cur" "$_avail"
      printf '      fix: %s\n' "$_fix"
    done
    ga_dim "  /upgrade-stack applies a fix like these, and asks twice before changing any setting."
  fi
fi

# ── 1b. Project setup — the one thing this installer cannot generate ───────
# GenericArch installs rules, skills, tooling and packages. It has never produced the .xcodeproj,
# and CLAUDE.md §1 is the reason: SPM stays the source of truth, and docs/REPO.md rejects both
# generators that would do it properly. What IS mechanical — the Xcode toolchain gate, the four
# committed .xcconfig files, the checklist — is ga-project-setup.sh, and this is where it belongs:
# after the mode is known, before a single file is written, so a missing toolchain costs nothing.
#
# One situation reaches it: a project whose build settings have never been written down. An
# .xcodeproj is an Apple marker, so nothing else here would notice. Offered, never assumed.
PROJECT_SETUP_DONE=0
if [ "$PROJECT_SETUP" != "no" ] && [ -x "$SRC/Scripts/ga-project-setup.sh" ]; then
  # A project with no Packages/ yet: the .xcconfig files are worth offering, because nothing else
  # in the repo has written its build settings down.
  BARE_XCODE=0
  ga_is_xcode_first "$TARGET" && BARE_XCODE=1

  if [ "$BARE_XCODE" -eq 1 ] || [ "$PROJECT_SETUP" = "yes" ]; then
    ga_hdr "── Xcode project ──────────────────────────────────────"
    if [ "$BARE_XCODE" -eq 1 ]; then
      ga_warn "an .xcodeproj is here but no Packages/ yet. This writes the .xcconfig files your
  project should reference and never opens the project itself. The package layout is a separate
  tool: https://github.com/kalpesh-jetani/GenericXCodeSetup"
    else
      ga_dim "  Nothing here generates an .xcodeproj — SPM stays the source of truth (CLAUDE.md §1)."
      ga_dim "  This checks the Xcode toolchain, asks what the project needs, and writes the four"
      ga_dim "  .xcconfig files plus a checklist. The project itself you create in Xcode."
    fi
    echo

    # A bundle ID, a Team ID and a deployment floor are answers only a person has, so with no
    # terminal this step cannot run — and letting it fail would abort an install that was otherwise
    # fine. Skip it instead, unless the operator asked for it explicitly and can see the error.
    PS_HAS_TTY=1
    { exec 3<>/dev/tty; } 2>/dev/null && exec 3>&- || PS_HAS_TTY=0

    if [ "$DRY_RUN" -eq 1 ]; then
      ga_dim "  dry run — skipped. It would run:"
      ga_dim "    ./Scripts/ga-project-setup.sh \"$TARGET\" --apply"
    elif [ "$PS_HAS_TTY" -eq 0 ] && [ "$PROJECT_SETUP" != "yes" ]; then
      ga_warn "no terminal to ask on — project setup skipped, the install continues.
  It needs a bundle ID, a Team ID and a deployment floor, none of which may be defaulted
  (CLAUDE.md §0). Run it yourself, or pass every answer as a flag:
    ./Scripts/ga-project-setup.sh . --product NAME --bundle-id com.you.app \\
        --targets ios,macos --ios 17 --macos 26.5 --apply --yes"
    elif [ "$PROJECT_SETUP" = "yes" ] || ga_confirm "Set up the Xcode project inputs first?"; then
      # Run it directly rather than reimplementing the gate: one source of truth for what a usable
      # Apple toolchain is, and it prompts for its own answers.
      "$SRC/Scripts/ga-project-setup.sh" "$TARGET" --apply
      _ps=$?
      case "$_ps" in
        0) PROJECT_SETUP_DONE=1 ;;
        # 3 is the toolchain gate. Installing on top of a machine that cannot open the project it
        # just described is how a session gets spent on a repo nobody can build — so this stops,
        # and nothing has been written yet.
        3) ga_die "Xcode toolchain check failed above — nothing was installed.
  Fix the toolchain and re-run, or skip this step with --no-project-setup." "$GA_EX_COMPAT" ;;
        4) ga_warn "project setup declined — continuing with the install only" ;;
        *) ga_die "project setup failed (exit $_ps) — nothing was installed." "$GA_EX_ERR" ;;
      esac
    else
      ga_dim "  skipped — run it later with ./Scripts/ga-project-setup.sh . --apply"
    fi
  fi
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
cleanup_temp() { rm -rf "$STAGE" "$PLAN" "$ADOPT_LOG" "$WROTE" "$MANIFEST_TMP" "$STAGE.orphans"; }

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
[ "$WITH_ARCH" -eq 1 ] && ADOPT_ARGS="$ADOPT_ARGS --with-architecture"
[ "$WITH_CLAUDE" -eq 1 ] && ADOPT_ARGS="$ADOPT_ARGS --with-claude-md"
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
# Resolved by the one-version-at-a-time gate above, which needs it before anything is staged; by
# here it can only be the SAME version, or a different one the operator kept with --in-place.
if [ -n "$PREV_MANIFEST" ]; then
  ga_dim "  found a previous install: ${PREV_MANIFEST#"$TARGET"/} ($PREV_VERSION)"
  [ "$PREV_VERSION" != "$GA_VERSION" ] && ga_warn "--in-place given — files installed by $PREV_VERSION and untouched since stay at
  $PREV_VERSION. They are listed below as 'left at older version'."
fi

# A CLAUDE-BK.md nobody recorded is the only surviving copy of somebody's rules. Writing over it
# is unrecoverable, so this refuses rather than asking — the same reasoning as the orphaned
# .gitignore backup recovery further down, which exists because that case DID happen.
# "Ours" means a previous run's `replaced` record names it as CLAUDE.md's backup. There is no
# record for the backup itself, by design — the backup field is what owns it.
ga_prev_claude_backup() {
  [ -n "$PREV_MANIFEST" ] || return 1
  _pc="$(ga_manifest_record_for "$PREV_MANIFEST" "CLAUDE.md")"
  [ -n "$_pc" ] || return 1
  [ "$(ga_json_field "$_pc" action)" = "replaced" ] || return 1
  [ "$(ga_json_field "$_pc" backup)" = "CLAUDE-BK.md" ]
}
if [ "$WITH_CLAUDE" -eq 1 ] && [ -e "$TARGET/CLAUDE-BK.md" ] && ! ga_prev_claude_backup; then
  ga_die "--with-claude-md would back your CLAUDE.md up to CLAUDE-BK.md, but that file already
  exists and no manifest records it — so it is not ours, and overwriting it would destroy the only
  copy of whatever it holds.

  Move or delete $TARGET/CLAUDE-BK.md, then re-run. Nothing was written." "$GA_EX_ERR"
fi

# ── What the previous uninstall left behind ────────────────────────────────
# uninstall.sh removes a file only while its hash still proves the file is ours, so anything the
# operator edited survives — and used to survive UNOWNED: the report naming it was written inside
# $GA_STATE_DIR, which the same uninstall then retired. Nothing ever read it.
#
# safetodelete-after-migration-note.md is that report, moved to the repo root so it outlives the
# thing it describes.
# Read here, before the plan, so those paths are classified as `orphan` rather than falling into
# `skip` — the difference being that `skip` says "this was never ours" and `orphan` says "this was,
# you changed it, and GenericArch is keeping track without touching it."
NOTE="$TARGET/safetodelete-after-migration-note.md"
ORPHAN_ROWS="$STAGE.orphans"
: > "$ORPHAN_ROWS"
if [ -f "$NOTE" ]; then
  awk -F'|' '/^\| `/ {
      p=$2; r=$3
      gsub(/`/, "", p); gsub(/^[ \t]+|[ \t]+$/, "", p); gsub(/^[ \t]+|[ \t]+$/, "", r)
      if (p != "") print p "\t" r
    }' "$NOTE" > "$ORPHAN_ROWS" 2>/dev/null || : > "$ORPHAN_ROWS"
  if [ -s "$ORPHAN_ROWS" ]; then
    ga_dim "  found safetodelete-after-migration-note.md: $(wc -l < "$ORPHAN_ROWS" | tr -d ' ') \
path(s) a previous uninstall kept"
  fi
fi
ga_is_orphan() { [ -s "$ORPHAN_ROWS" ] && awk -F'\t' -v p="$1" '$1==p {found=1} END {exit !found}' "$ORPHAN_ROWS"; }

n_create=0; n_adopt=0; n_keep=0; n_skip=0; n_declined=0; n_upgrade=0; n_replace=0; n_orphan=0
# Shared libraries the target has edited: kept (theirs always wins) but reported, because a
# drifted library breaks its callers instead of merely being out of date.
LIB_DRIFT=""

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
  # On the note and still on disk: theirs, and known to be theirs. Recorded before every other
  # classification below, because each of those would describe it wrongly — `skip` most of all.
  if ga_is_orphan "$rel"; then
    printf 'orphan\t%s\t%s\t0\n' "$rel" "$tsha" >> "$PLAN"; n_orphan=$((n_orphan + 1)); continue
  fi
  # CLAUDE.md is the one path GenericArch REPLACES rather than skips, and only under
  # --with-claude-md — adopt.sh does not stage it otherwise. Their rules are not discarded: the
  # original goes to CLAUDE-BK.md and the manifest records the swap, which is the only thing that
  # lets uninstall.sh put it back.
  #
  # Except on a re-run over our own migration. A CLAUDE.md that differs from the staged one while a
  # record already points at CLAUDE-BK.md means the operator edited OUR copy — that is their file
  # now, the rule that their file always wins applies, and their backup must not be overwritten.
  if [ "$rel" = "CLAUDE.md" ]; then
    if ga_prev_claude_backup; then
      printf 'skip\t%s\t%s\t0\n' "$rel" "$tsha" >> "$PLAN"; n_skip=$((n_skip + 1)); continue
    fi
    printf 'replace\t%s\t%s\t1\n' "$rel" "$ssha" >> "$PLAN"; n_replace=$((n_replace + 1)); continue
  fi
  prev=""
  if [ -n "$PREV_MANIFEST" ]; then prev="$(ga_manifest_record_for "$PREV_MANIFEST" "$rel")"; fi
  if [ -n "$prev" ] && [ "$(ga_json_field "$prev" action)" = "created" ] \
     && [ "$(ga_json_field "$prev" sha256)" = "$tsha" ]; then
    # A shared library is a special case of "the base has moved on", and the conservative-looking
    # answer is the broken one. The scripts shipped beside it SOURCE it, so keeping an old copy
    # produces callers whose functions do not exist. v0.4.2 installed 7 new scripts over a v0.2.0
    # ga-lifecycle.sh and every one failed with `command not found` — while still exiting 0, so
    # nothing reported it. The record above proves this copy is ours and untouched, so moving it
    # forward with its callers discards nothing of theirs.
    if [ "$(ga_staged_kind "$staged")" = "lib" ]; then
      printf 'upgrade\t%s\t%s\t1\n' "$rel" "$ssha" >> "$PLAN"; n_upgrade=$((n_upgrade + 1)); continue
    fi
    # We installed it, it is untouched since, and the base has moved on. Not ours to overwrite —
    # Scripts/adopt-review.sh is the tool for taking an update.
    printf 'keep\t%s\t%s\t0\n' "$rel" "$tsha" >> "$PLAN"; n_keep=$((n_keep + 1)); continue
  fi
  # Their file wins, as always. But an edited library is not just stale — it silently breaks every
  # script that sources it, so it is named rather than buried in the skip list.
  if [ "$(ga_staged_kind "$staged")" = "lib" ]; then
    LIB_DRIFT="${LIB_DRIFT}${rel}
"
  fi
  printf 'skip\t%s\t%s\t0\n' "$rel" "$tsha" >> "$PLAN"; n_skip=$((n_skip + 1))
done <<EOF
$(cd "$STAGE" && find . -type f -print | sed 's|^\./||' | LC_ALL=C sort)
EOF

# A note row for a path this release no longer ships never reaches the loop above, because the loop
# walks the staged tree. It still has to be tracked: the file is on disk, the operator edited it,
# and no later run should treat it as arriving from nowhere.
if [ -s "$ORPHAN_ROWS" ]; then
  while IFS="$(printf '\t')" read -r orel _oreason; do
    [ -n "$orel" ] || continue
    # Gone means resolved — they reverted or deleted it, and the row retires with it.
    [ -e "$TARGET/$orel" ] || continue
    grep -qF "orphan$(printf '\t')$orel$(printf '\t')" "$PLAN" && continue
    [ -e "$STAGE/$orel" ] && continue
    printf 'orphan\t%s\t%s\t0\n' "$orel" "$(ga_sha256 "$TARGET/$orel")" >> "$PLAN"
    n_orphan=$((n_orphan + 1))
  done < "$ORPHAN_ROWS"
fi

# The one file GenericArch edits rather than creates: .gitignore gains the paths its own tooling
# generates. Delimited, idempotent, backed up, and removed again by uninstall.sh.
GITIGNORE_ACTION="none"
# Read from GA_GITIGNORE_BLOCK so the plan can never again describe a different set of lines than
# the one ga_block_append writes. It did: the plan named two entries where three were appended.
GITIGNORE_PROSE="$(printf '%s' "$GA_GITIGNORE_BLOCK" | sed 's/ /, /g')"
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
if [ "$n_upgrade" -gt 0 ]; then
  printf '\n%s  shared library — upgraded in lockstep%s with the scripts that source it\n' "$GA_BLD" "$GA_OFF"
  awk -F'\t' '$1=="upgrade" {print "    ↑ " $2}' "$PLAN"
  ga_dim "    Proven ours and unedited; the previous copy is backed up under $GA_STATE_DIR/backups/."
fi
if [ "$n_orphan" -gt 0 ]; then
  printf '\n%s  orphaned by a previous uninstall%s — tracked, never rewritten\n' "$GA_BLD" "$GA_OFF"
  awk -F'\t' '$1=="orphan" {print "    ⊙ " $2}' "$PLAN"
  ga_dim "    Yours: you edited them, so the uninstall kept them. Recorded in the manifest so the"
  ga_dim "    next uninstall reports them again instead of deleting your changes."
fi
if [ "$n_replace" -gt 0 ]; then
  printf '\n%s  replaced — yours is kept, moved aside%s\n' "$GA_BLD" "$GA_OFF"
  awk -F'\t' '$1=="replace" {print "    ⇄ " $2 "  →  your original becomes CLAUDE-BK.md"}' "$PLAN"
  ga_dim "    Recorded in the manifest, so ./uninstall.sh puts your file back byte-for-byte."
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
          printf '    ~ .gitignore  %s%s%s\n' "$GA_DIM" "$GITIGNORE_PROSE" "$GA_OFF" ;;
  create) printf '\n%s  create%s — .gitignore\n' "$GA_BLD" "$GA_OFF"
          printf '    + .gitignore  %s%s%s\n' "$GA_DIM" "$GITIGNORE_PROSE" "$GA_OFF" ;;
  none)   [ -f "$TARGET/.gitignore" ] && printf '\n%s  .gitignore already carries the managed block — unchanged%s\n' "$GA_DIM" "$GA_OFF" ;;
esac
printf '\n%s  manifest%s\n' "$GA_BLD" "$GA_OFF"
printf '    + %s/manifest-%s.json  %swritten last, on full success only%s\n' \
  "$GA_STATE_DIR" "$GA_VERSION" "$GA_DIM" "$GA_OFF"

echo
printf '%s───────────────────────────────────────────────────────%s\n' "$GA_BLD" "$GA_OFF"
printf '%d create · %d already ours · %d lib upgraded · %d left at older version · %d yours (skipped) · %d declined' \
  "$n_create" "$n_adopt" "$n_upgrade" "$n_keep" "$n_skip" "$n_declined"
[ "$n_replace" -gt 0 ] && printf ' · %d replaced' "$n_replace"
[ "$n_orphan" -gt 0 ] && printf ' · %d orphaned' "$n_orphan"
printf '\n'
[ "$n_skip" -gt 0 ] && ga_dim "Nothing in the skipped list is read, moved or rewritten."
if [ -n "$LIB_DRIFT" ]; then
  echo
  ga_warn "a shared library here has local edits, so it cannot be moved forward:"
  printf '%s' "$LIB_DRIFT" | while IFS= read -r l; do [ -n "$l" ] && printf '    %s\n' "$l"; done
  ga_dim "  Scripts shipped in this install source it. If they call something your copy does not
  define, they fail with \`command not found\` and still exit 0. Diff it against the base:
      ./Scripts/adopt-review.sh <target> --diff 3"
fi

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
# The --root-ok warning prints before the plan, which is sixty lines of scrollback earlier by the
# time consent is given — so the prompt restates it. An operator re-running a command from shell
# history should not be able to create a second footprint by answering a question about the first.
CONFIRM_Q="Install into $TARGET?"
if [ -n "$OTHER_ROOT" ]; then
  ga_warn "this would be the SECOND GenericArch footprint in this checkout"
  printf '    here:      %s\n' "$TARGET"
  printf '    already:   %s  (%s)\n' "$OTHER_ROOT" "$OTHER_VERSION"
  if [ -n "$ONE_PRODUCT" ]; then
    printf '  %sEvery project marker found above is inside %s%s%s — so this is one product,\n' \
      "$GA_YEL" "$GA_BLD" "$ONE_PRODUCT" "$GA_OFF$GA_YEL"
    printf '  not the two sharing a checkout that --root-ok is for. Installing into that directory\n'
    printf '  instead is almost certainly what you meant:%s\n' "$GA_OFF"
    printf '      cd "%s" && %s\n' "$OTHER_ROOT" \
      "$([ "${GA_VIA_BOOTSTRAP:-0}" = "1" ] && printf 'bash "%s/bootstrap.sh" --apply' "$PWD" || printf './install.sh .')"
  fi
  CONFIRM_Q="Install a second footprint into $TARGET anyway?"
fi
if ! ga_confirm "$CONFIRM_Q"; then
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
    # An upgrade is the one case where a file already on disk is overwritten. It is provably ours
    # and unedited, so nothing of theirs is at stake — but keep the bytes anyway, so a bad release
    # can be undone by hand without the network.
    if [ "$act" = "upgrade" ] && [ -f "$TARGET/$rel" ]; then
      mkdir -p "$BACKUP_DIR"
      cp -p "$TARGET/$rel" "$BACKUP_DIR/$(basename "$rel").$GA_VERSION.bak"
    fi
    # A replace keeps the original where the operator can READ it — .genericarch/backups/ is for
    # bytes nobody is expected to open, and these are their rules. Hashed before the copy so the
    # manifest can verify the restore instead of asserting it.
    REPLACED_ORIG=""
    if [ "$act" = "replace" ] && [ -f "$TARGET/$rel" ]; then
      REPLACED_ORIG="$(ga_sha256 "$TARGET/$rel")"
      cp -p "$TARGET/$rel" "$TARGET/CLAUDE-BK.md"
      # Ordered so the reverse-replay in rollback() restores BEFORE it deletes the backup.
      printf 'file\t%s\t\n' "CLAUDE-BK.md" >> "$WROTE"
      printf 'backup\t%s\t%s\n' "$rel" "$TARGET/CLAUDE-BK.md" >> "$WROTE"
    fi
    cp -p "$STAGE/$rel" "$TARGET/$rel"
    printf 'file\t%s\t\n' "$rel" >> "$WROTE"
    sha="$(ga_sha256 "$TARGET/$rel")"
  fi
  case "$act" in
    # Recorded so the manifest is a complete statement of what GenericArch would own here, and so
    # `declined` survives a re-install rather than being re-derived from the tombstone file alone.
    declined) ga_manifest_add "$rel" declined "$sha" "$(ga_now_iso)" "" "$GA_VERSION" ;;
    skip)     ga_manifest_add "$rel" skipped  "$sha" "$(ga_mtime_iso "$TARGET/$rel")" "" "$GA_VERSION" ;;
    # The hash recorded is THEIR content, which is what stops any later run mistaking it for ours.
    orphan)   ga_manifest_add "$rel" orphan   "$sha" "$(ga_mtime_iso "$TARGET/$rel")" "" "$GA_VERSION" ;;
    # No separate record for CLAUDE-BK.md, exactly as .gitignore's backup has none: the `backup`
    # field owns it, and uninstall.sh's restore loop deletes it after reading it. A `created` record
    # would queue a second deletion of a file already gone, and count it as removed.
    replace)  ga_manifest_add "$rel" replaced "$sha" "$(ga_mtime_iso "$TARGET/$rel")" \
                "CLAUDE-BK.md" "$GA_VERSION" "$REPLACED_ORIG" ;;
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
    # rollback() replays $WROTE in REVERSE, so the row that deletes the backup must be written
    # BEFORE the row that restores from it. The other order deleted the .bak first and the restore
    # then found nothing — leaving the managed block in the operator's .gitignore after a rollback
    # that reported success.
    printf 'file\t%s\t\n' "$backup_rel" >> "$WROTE"
    printf 'backup\t%s\t%s\n' ".gitignore" "$TARGET/$backup_rel" >> "$WROTE"
    # shellcheck disable=SC2086  # deliberate word splitting: one path per line, no spaces in any
    ga_block_append "$TARGET/.gitignore" $GA_GITIGNORE_BLOCK
    ga_manifest_add ".gitignore" modified "$(ga_sha256 "$TARGET/.gitignore")" \
      "$(ga_mtime_iso "$TARGET/.gitignore")" "$backup_rel" "$GA_VERSION" "$orig_sha"
    ga_ok "appended the managed block to .gitignore (original at $backup_rel)"
    ;;
  create)
    # shellcheck disable=SC2086  # deliberate word splitting: one path per line, no spaces in any
    ga_block_append "$TARGET/.gitignore" $GA_GITIGNORE_BLOCK
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
ga_manifest_commit "$MANIFEST" "$GA_VERSION" "$TARGET" "$SOURCE_REF" "$INSTALLED_AT" "$OTHER_ROOT"
printf 'file\t%s\t\n' "${MANIFEST#"$TARGET"/}" >> "$WROTE"
ga_ok "manifest written: ${MANIFEST#"$TARGET"/}"

# The note is a hand-off, not an archive. A row whose file is gone was resolved — reverted or
# deleted — and keeping it would report the same path forever. When none are left the note itself
# has nothing to say, so it goes rather than sitting at the repo root looking unfinished.
if [ -f "$NOTE" ] && [ -s "$ORPHAN_ROWS" ]; then
  if [ "$n_orphan" -eq 0 ]; then
    rm -f "$NOTE"
    ga_ok "safetodelete-after-migration-note.md retired — every path it listed is resolved"
  else
    _gone=0
    while IFS="$(printf '\t')" read -r orel _r; do
      [ -n "$orel" ] || continue
      [ -e "$TARGET/$orel" ] || _gone=$((_gone + 1))
    done < "$ORPHAN_ROWS"
    if [ "$_gone" -gt 0 ]; then
      _note_tmp="$NOTE.ga-prune.$$"
      awk -F'|' -v tgt="$TARGET" '
        /^\| `/ {
          p=$2; gsub(/`/, "", p); gsub(/^[ \t]+|[ \t]+$/, "", p)
          if (p != "" && system("test -e \"" tgt "/" p "\"") != 0) next
        }
        { print }
      ' "$NOTE" > "$_note_tmp" && mv "$_note_tmp" "$NOTE"
      ga_ok "safetodelete-after-migration-note.md pruned — $_gone resolved, $n_orphan still tracked"
    fi
  fi
fi

COMMITTED=0   # past the point of rollback — the install is complete
trap - INT TERM
trap 'cleanup_temp' EXIT

# The first step in the ledger. Every command gates on this, so an install that did not record it
# would block the whole sequence it just enabled.
ga_step_record "$TARGET" install "$GA_VERSION from $SOURCE_REF"

# ── 6. The /project-init preflight ─────────────────────────────────────────
# About half of /project-init is a deterministic scan of files on disk — the mode, the conflict
# evidence for docs/ADOPTION.md §A2, the name collisions, the routable-path validator, the orphan
# module docs. Running it here means the next session reads one bounded artifact instead of paying
# for four rounds of grep, exactly as sync-notes.sh --evidence does for /sync-app-notes.
#
# It has to be HERE and not earlier: §routes checks .claude/MAP.tsv against the disk, so the map
# must already be installed. And it is past the rollback point on purpose — the files have landed,
# so a scan that fails costs a session, not an install. Never fatal.
PREFLIGHT_NOTE="Gather the evidence offline first:  ./Scripts/ga-init-scan.sh . --write"
if [ "$PREFLIGHT" -eq 1 ] && [ "$DRY_RUN" -eq 0 ] && [ -x "$SRC/Scripts/ga-init-scan.sh" ]; then
  ga_hdr "── Preflight ──────────────────────────────────────────"
  ga_dim "  Gathering what /project-init can establish without asking. Read-only; nothing is decided."
  if "$SRC/Scripts/ga-init-scan.sh" "$TARGET" --write --quiet; then
    PREFLIGHT_NOTE="Evidence is already gathered: .claude/notes/.evidence/INIT-SCAN.md"
  else
    _pf=$?
    case "$_pf" in
      # 3 is a BLOCKING toolchain row, already reported above and by the scan itself. The evidence
      # file is still written, so the note stands.
      3) PREFLIGHT_NOTE="Evidence gathered, with a BLOCKING toolchain row: .claude/notes/.evidence/INIT-SCAN.md" ;;
      *) ga_warn "the preflight scan did not complete (exit $_pf) — the install is unaffected.
  /project-init will run its own scans instead. A failure report, if one was written, is in
  $GA_STATE_DIR/failures/." ;;
    esac
  fi
fi

ga_hdr "Installed $GA_VERSION$([ "$WITH_ARCH" -eq 1 ] && printf ' (with architecture)')"
cat <<NEXT

  The commands run ${GA_BLD}in this order${GA_OFF} — each one leaves the repo in the state the next assumes.
  ${GA_DIM}./Scripts/ga-step.sh show${GA_OFF} at any point says where you are and what is next.

  1. ${GA_BLD}/project-init${GA_OFF}
       Reads your CLAUDE.md in full, builds the rule-conflict table, and asks per conflict.
       Your rules win by default; nothing is overwritten without an explicit yes.
       ${GA_DIM}${PREFLIGHT_NOTE}${GA_OFF}
  2. ${GA_BLD}/gaps${GA_OFF}
       Derives each gap's status from your code instead of asking.
  3. ${GA_BLD}/sync-app-notes${GA_OFF}
       Builds the nine inventories every later lookup reads instead of searching.

  Then the repo is ${GA_BLD}ready${GA_OFF}: skills, /find, /decide, /learn, /review, /verify, /build.

${GA_DIM}Also: ./Scripts/detect-toolchain.sh — your project defines the baseline, not GenericArch's numbers.
To decline a file so no later install re-creates it:  ./Scripts/ga-remove.sh <path> --reason "..."
To remove everything again:  ./uninstall.sh $GA_VERSION${GA_OFF}
NEXT

if [ "$n_replace" -gt 0 ]; then
  ga_warn "your previous CLAUDE.md is at CLAUDE-BK.md — read it before the rule-conflict table.
  ./uninstall.sh $GA_VERSION puts it back byte-for-byte, verified against its recorded hash."
elif [ "$WITH_CLAUDE" -eq 0 ]; then
  ga_dim "No CLAUDE.md was written. Your rules stay yours until you decide otherwise."
fi
if [ "$n_orphan" -gt 0 ]; then
  ga_warn "$n_orphan file(s) you had edited before an earlier uninstall are tracked as orphans.
  Yours, untouched, listed in safetodelete-after-migration-note.md. The next uninstall reports
  them again rather than deleting your changes."
fi
exit "$GA_EX_OK"
