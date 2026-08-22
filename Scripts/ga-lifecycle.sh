#!/usr/bin/env bash
#@kind      lib
#@platform  macos
#@claude    call
#@purpose   Shared library for install.sh and uninstall.sh: exit codes, logging, sha256, manifest read/write, managed config blocks, the macOS/Swift compatibility gate. Sourced, never executed.
#@usage     . Scripts/ga-lifecycle.sh
#@in        n/a (sourced). Honours GA_ASSUME_YES=1, GA_DRY_RUN=1, NO_COLOR
#@out       functions: ga_die ga_warn ga_ok ga_info ga_dim ga_hdr ga_confirm ga_sha256 ga_mtime_iso ga_now_iso ga_json_escape ga_json_field ga_manifest_path ga_manifest_find ga_manifest_version ga_manifest_records ga_manifest_record_for ga_manifest_begin ga_manifest_add ga_manifest_commit ga_block_present ga_block_append ga_block_strip ga_check_compatible ga_footprint_at ga_known_paths ga_prune_empty_dirs ga_is_supported_version ga_require_macos ga_has_base_markers ga_is_source_checkout ga_is_template_copy ga_staged_kind ga_tombstone_add ga_tombstoned ga_tombstone_reason ga_tombstone_drop ga_step_record ga_step_done ga_step_next ga_step_missing ga_grave_path
#@exit      0=sourced ok 2=executed directly instead of sourced
#@effects   none on its own; every write is performed by the caller through these helpers
#@when      installer helper|manifest format|install exit codes|hashing a manifest|uninstall helper
#
# Shared logic for the GenericArch install → uninstall lifecycle.
#
# Both install.sh and uninstall.sh source this and nothing else. The reason it exists is that the
# two scripts must agree on three things exactly, forever: how a file is hashed, how the manifest
# is spelled, and what a managed config block looks like. Any of those diverging turns "restore the
# repo to its pre-install state" into a guess.
#
# macOS-native tooling only: shasum, stat -f, date -r, BSD sed/awk. No jq, no GNU flags, no
# network, no new dependencies.

# Sourced, not executed. Running it directly would define functions into a shell that exits
# immediately afterwards, which reads as "the tool did nothing" rather than as a mistake.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "ga-lifecycle.sh is a library — source it, don't run it:" >&2
  echo "    . \"\$(dirname \"\$0\")/Scripts/ga-lifecycle.sh\"" >&2
  exit 2
fi

# ── Exit codes ─────────────────────────────────────────────────────────────
# Distinct on purpose: a caller in CI must be able to tell "this repo is not a Swift project"
# (3, expected, not a failure) from "the install broke" (1) without parsing stdout.
GA_EX_OK=0        # success
GA_EX_ERR=1       # generic error — something went wrong
GA_EX_USAGE=2     # bad or missing arguments
GA_EX_COMPAT=3    # compatibility gate rejected the target; nothing was written
GA_EX_ABORT=4     # the operator declined at the confirmation prompt
GA_EX_SEQ=5       # a step ran out of order — nothing was written
GA_EX_UPGRADE=6   # a different version is already installed; uninstall it first. Nothing written
GA_EX_PLATFORM=78 # not macOS — EX_CONFIG, the same code Scripts/claude-utils/_common.sh uses

# The manifest format version. Bump only when the SHAPE changes, never for a GenericArch release —
# uninstall.sh keys its parser off this, not off the product version.
#
#   1 → 2: added the `orphan` and `replaced` actions, and the top-level `sibling_root` field.
#          A schema-1 reader handed a schema-2 manifest would fall through its action `case` and
#          try to DELETE an orphan — the operator's own edited file. That is why uninstall.sh
#          refuses a schema it does not know rather than doing its best with it.
GA_MANIFEST_SCHEMA=2

# Everything GenericArch owns lives under this one directory, so a reader can see the whole
# footprint of the install state in one place.
GA_STATE_DIR=".genericarch"

# ── Colour ─────────────────────────────────────────────────────────────────
# Suppressed when stdout is not a terminal so the plan stays diffable and greppable in CI logs.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  GA_RED=$'\033[31m'; GA_YEL=$'\033[33m'; GA_GRN=$'\033[32m'
  GA_DIM=$'\033[2m';  GA_BLD=$'\033[1m';  GA_OFF=$'\033[0m'
else
  GA_RED=''; GA_YEL=''; GA_GRN=''; GA_DIM=''; GA_BLD=''; GA_OFF=''
fi

# ── Logging ────────────────────────────────────────────────────────────────
ga_hdr()  { printf '\n%s%s%s\n' "$GA_BLD" "$1" "$GA_OFF"; }
ga_info() { printf '%s\n' "$1"; }
ga_dim()  { printf '%s%s%s\n' "$GA_DIM" "$1" "$GA_OFF"; }
ga_ok()   { printf '%s✓%s %s\n' "$GA_GRN" "$GA_OFF" "$1"; }
ga_warn() { printf '%s⚠%s %s\n' "$GA_YEL" "$GA_OFF" "$1" >&2; }

# Exit code is the SECOND argument so the message reads first at the call site. A non-numeric or
# zero code is coerced to GA_EX_ERR: `ga_die "..." "$?"` where $? happens to be 0 must not
# report success.
ga_die() {
  printf '%s✗%s %s\n' "$GA_RED" "$GA_OFF" "$1" >&2
  _gc="${2:-$GA_EX_ERR}"
  case "$_gc" in ''|*[!0-9]*|0) _gc="$GA_EX_ERR" ;; esac
  exit "$_gc"
}

# ── Confirmation ───────────────────────────────────────────────────────────
# Returns 0 to proceed, non-zero to abort. --yes sets GA_ASSUME_YES=1.
# Reads from /dev/tty rather than stdin: both scripts may be driven from a pipe, and a prompt that
# silently consumed piped stdin would answer itself.
# Only install.sh and uninstall.sh implement a --yes flag; every other caller reaches this through
# GA_ASSUME_YES=1. So both messages below name the environment variable, which works everywhere —
# advising --yes sent non-interactive callers of ga-remove/ga-reseal/adopt.sh into an
# "unknown flag" exit, with the script's own remediation as the cause.
ga_confirm() {
  if [ "${GA_ASSUME_YES:-0}" = "1" ]; then
    ga_dim "  (assuming yes — proceeding without asking)"
    return 0
  fi
  # `[ -r /dev/tty ]` is not enough: in a sandbox or under a detached process the node exists and
  # tests readable, then fails on open with "Device not configured". Probe by actually opening it,
  # with the failure suppressed, so a declined install reports "aborted" and not a shell error.
  if ! { exec 3<>/dev/tty; } 2>/dev/null; then
    ga_warn "no terminal to ask on — re-run with GA_ASSUME_YES=1 to confirm, or --dry-run to preview"
    return 1
  fi
  printf '%s%s%s [y/N] ' "$GA_BLD" "$1" "$GA_OFF" >&3
  if ! read -r _ga_reply <&3; then exec 3>&-; return 1; fi
  exec 3>&-
  case "$_ga_reply" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# ── Hashing and timestamps ─────────────────────────────────────────────────
# shasum -a 256 ships with macOS; sha256sum does not. Bare hex, no filename, so the value can be
# compared with `=` and embedded in JSON without trimming.
ga_sha256() {
  [ -f "$1" ] || return 1
  shasum -a 256 "$1" | awk '{print $1}'
}

# BSD stat gives the mtime as an epoch; BSD date turns an epoch into UTC ISO-8601 with -r.
# `stat -f %Sm -t` would honour the local timezone, which makes two machines disagree about the
# same install.
ga_mtime_iso() {
  [ -e "$1" ] || return 1
  _ga_epoch=$(stat -f '%m' "$1") || return 1
  date -u -r "$_ga_epoch" '+%Y-%m-%dT%H:%M:%SZ'
}

ga_now_iso() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

# ── JSON, hand-rolled ──────────────────────────────────────────────────────
# No jq on a stock macOS box, and adding a dependency to an installer is how an installer stops
# being runnable. We are the only writer of this file, so the format is chosen to be BOTH valid
# JSON and parseable with one awk: every file record is exactly one line.
ga_json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# Pull one "key": "value" out of a single-line JSON record. Values are escaped on write, so the
# first unescaped quote after the key is always the terminator.
ga_json_field() {
  printf '%s\n' "$1" | awk -v k="\"$2\":" '
    {
      i = index($0, k)
      if (i == 0) exit 1
      rest = substr($0, i + length(k))
      sub(/^[ \t]+/, "", rest)
      # A JSON null is an ABSENT value, not a string. Without this, the scan below runs on to the
      # next key and returns ITS NAME as the value — `backup` on a created record came back as the
      # literal "original_sha256".
      if (substr(rest, 1, 4) == "null") exit 0
      j = index(rest, "\"")
      if (j == 0) exit 1
      rest = substr(rest, j + 1)
      out = ""
      for (n = 1; n <= length(rest); n++) {
        c = substr(rest, n, 1)
        if (c == "\\") { n++; out = out substr(rest, n, 1); continue }
        if (c == "\"") break
        out = out c
      }
      print out
    }'
}

# ── Manifest ───────────────────────────────────────────────────────────────
# Path for a given version, e.g. .genericarch/manifest-v0.2.0.json
ga_manifest_path() { printf '%s/%s/manifest-%s.json' "$1" "$GA_STATE_DIR" "$2"; }

# Any manifest actually present in the target, newest name last. Used to detect "installed, but
# not the version you asked me to remove".
ga_manifest_find() {
  for _ga_m in "$1/$GA_STATE_DIR"/manifest-*.json; do
    [ -f "$_ga_m" ] && printf '%s\n' "$_ga_m"
  done
}

ga_manifest_version() {
  [ -f "$1" ] || return 1
  ga_json_field "$(grep -m1 '"genericarch_version"' "$1")" genericarch_version
}

# Every file record, one per line. The `"path":` guard is what distinguishes a file record from
# the header fields above it.
ga_manifest_records() {
  [ -f "$1" ] || return 1
  grep '"path":' "$1"
}

ga_manifest_record_for() {
  [ -f "$1" ] || return 1
  _ga_want="$2"
  ga_manifest_records "$1" | while IFS= read -r _ga_rec; do
    if [ "$(ga_json_field "$_ga_rec" path)" = "$_ga_want" ]; then
      printf '%s\n' "$_ga_rec"
      break
    fi
  done
}

# Writing is staged: ga_manifest_begin opens a scratch file, ga_manifest_add appends one record
# per installed file, ga_manifest_commit assembles the real thing in one move. The manifest is
# written LAST and only on full success, so its presence is itself the proof the install completed.
ga_manifest_begin() {
  GA_MANIFEST_TMP="$1"
  : > "$GA_MANIFEST_TMP"
}

# ga_manifest_add <relpath> <action> <sha256> <mtime-iso> <backup-or-empty> <version> [original-sha]
#
# sha256 is the hash of the content AS INSTALLED. For a `modified` file that means after the
# managed block was appended, and original_sha256 carries the hash of what was there before — the
# value uninstall.sh checks a restored backup against, so "restored byte-for-byte" is verified
# rather than asserted.
ga_manifest_add() {
  _ga_backup="$5"
  if [ -n "$_ga_backup" ]; then
    _ga_backup="\"$(ga_json_escape "$_ga_backup")\""
  else
    _ga_backup="null"
  fi
  _ga_orig="${7:-}"
  if [ -n "$_ga_orig" ]; then
    _ga_orig="\"$_ga_orig\""
  else
    _ga_orig="null"
  fi
  printf '    {"path": "%s", "action": "%s", "sha256": "%s", "installed_at": "%s", "backup": %s, "original_sha256": %s, "version": "%s"}\n' \
    "$(ga_json_escape "$1")" "$2" "$3" "$4" "$_ga_backup" "$_ga_orig" "$(ga_json_escape "$6")" \
    >> "$GA_MANIFEST_TMP"
}

# ga_manifest_commit <manifest-path> <version> <target> <source_ref> <installed_at> [sibling_root]
#
# sibling_root records that this install is one of TWO in the same checkout — the --root-ok case.
# Terminal warnings do not survive the session that printed them, and the next reader of this repo
# has no other way to learn that every command and skill resolves ambiguously here.
ga_manifest_commit() {
  _ga_out="$1"
  _ga_sibling="${6:-}"
  if [ -n "$_ga_sibling" ]; then
    _ga_sibling="\"$(ga_json_escape "$_ga_sibling")\""
  else
    _ga_sibling="null"
  fi
  mkdir -p "$(dirname "$_ga_out")"
  {
    printf '{\n'
    printf '  "schema": %s,\n' "$GA_MANIFEST_SCHEMA"
    printf '  "genericarch_version": "%s",\n' "$(ga_json_escape "$2")"
    printf '  "target": "%s",\n' "$(ga_json_escape "$3")"
    printf '  "source_ref": "%s",\n' "$(ga_json_escape "$4")"
    printf '  "installed_at": "%s",\n' "$5"
    printf '  "installer": "install.sh",\n'
    printf '  "state_dir": "%s",\n' "$GA_STATE_DIR"
    printf '  "sibling_root": %s,\n' "$_ga_sibling"
    printf '  "files": [\n'
    # Trailing comma on every line but the last — the one thing hand-rolled JSON always gets wrong.
    awk 'NR>1 {print prev ","} {prev=$0} END {if (NR) print prev}' "$GA_MANIFEST_TMP"
    printf '  ]\n'
    printf '}\n'
  } > "$_ga_out"
}

# ── Managed config blocks ──────────────────────────────────────────────────
# When GenericArch must add a line to a file the repo already owns, it goes inside these markers
# and nowhere else. That is what makes the addition removable without a diff: uninstall deletes
# the marked span and leaves every surrounding line byte-identical.
GA_BLOCK_OPEN="# >>> GenericArch managed block — do not edit; removed by uninstall.sh >>>"
GA_BLOCK_CLOSE="# <<< GenericArch managed block <<<"

# What GenericArch's own tooling generates inside a consumer repo, and therefore what its managed
# .gitignore block lists. Defined ONCE because it was twice: the plan line announced two entries
# where the block wrote three, so the plan under-reported what landed in the operator's file. Any
# printer that describes this block reads it from here.
GA_GITIGNORE_BLOCK=".claude/claude-tasks/ .claude/notes/.evidence/ dist/"

ga_block_present() {
  [ -f "$1" ] || return 1
  grep -qF "$GA_BLOCK_OPEN" "$1"
}

# Append the block to <file>, creating it if absent. Idempotent: a file that already carries the
# block is left exactly as it is, which is what makes re-running install.sh safe.
ga_block_append() {
  _ga_file="$1"; shift
  if ga_block_present "$_ga_file"; then return 0; fi
  # Guarantee the marker starts on its own line even if the file lacks a trailing newline.
  if [ -s "$_ga_file" ] && [ -n "$(tail -c 1 "$_ga_file" 2>/dev/null)" ]; then
    printf '\n' >> "$_ga_file"
  fi
  # And a blank line ahead of it. In a .gitignore that is tidiness; in a Markdown file the marker
  # is a `#` heading, and one jammed against the previous paragraph renders as part of it.
  # ga_block_strip removes a single blank line ahead of the block, so this still round-trips.
  [ -s "$_ga_file" ] && printf '\n' >> "$_ga_file"
  {
    printf '%s\n' "$GA_BLOCK_OPEN"
    for _ga_line in "$@"; do printf '%s\n' "$_ga_line"; done
    printf '%s\n' "$GA_BLOCK_CLOSE"
  } >> "$_ga_file"
}

# Remove the block and the single blank line ga_block_append may have introduced ahead of it.
# Writes through a temp file so a failure mid-edit cannot truncate the operator's config.
#
# This is the FALLBACK restore path, not the primary one. uninstall.sh restores a `modified` file
# by copying its backup back and verifying the result against original_sha256, which is byte-exact
# by construction. Stripping is only reached when that backup is gone, and it carries one known
# limitation: awk emits newline-terminated lines, so a file that had NO trailing newline before
# install gains one. uninstall.sh warns when it takes this path.
ga_block_strip() {
  _ga_file="$1"
  ga_block_present "$_ga_file" || return 0
  _ga_tmp="$_ga_file.ga-strip.$$"
  awk -v bopen="$GA_BLOCK_OPEN" -v bclose="$GA_BLOCK_CLOSE" '
    # A blank line is held back one iteration. If the open marker turns out to follow it, that
    # blank was the separator ga_block_append inserted and goes with the block; anything else
    # releases it untouched. Every line outside the span stays byte-identical.
    $0 == bopen  { inblock = 1; held = 0; next }
    $0 == bclose { inblock = 0; next }
    inblock     { next }
    {
      if (held) { print heldline; held = 0 }
      if ($0 == "") { heldline = $0; held = 1; next }
      print
    }
    END { if (held) print heldline }
  ' "$_ga_file" > "$_ga_tmp" && mv "$_ga_tmp" "$_ga_file"
}

# ── Platform gate ──────────────────────────────────────────────────────────
# Runs before anything else, including the fetch. Every script this installs declares
# `#@platform macos` and Scripts/claude-utils/_common.sh already exits 78 on anything else — but
# that check fires only once a script is RUN, which is long after the install wrote it. Refusing
# here means a Linux or WSL machine never receives a toolchain layer it cannot execute: shasum,
# xcrun, xed, xcodebuild and BSD sed/awk semantics are all assumed, and a GNU box fails in ways
# that read as corrupt data rather than the wrong platform.
#
# There is deliberately no override. macOS is a fixed choice, not a default (CLAUDE.md §1).
ga_require_macos() {
  _ga_os="$(uname -s 2>/dev/null || echo unknown)"
  [ "$_ga_os" = Darwin ] && return 0
  printf '%s✗ GenericArch is macOS-only (found: %s).%s\n' "${GA_RED:-}" "$_ga_os" "${GA_OFF:-}" >&2
  printf '  It installs Apple-platform rules and scripts that assume shasum, xcrun and BSD\n' >&2
  printf '  sed/awk. Nothing was written.\n' >&2
  exit "$GA_EX_PLATFORM"
}

# ── Compatibility gate ─────────────────────────────────────────────────────
# Runs BEFORE the first write, never alongside it. GenericArch is a rules-and-tooling layer for
# Apple-platform Swift repos; in a Gradle or Node repo every skill it installs is wrong, every
# script it installs targets a toolchain that is not there, and the operator finds out days later.
#
# A repo with NO markers at all passes: installing into an empty repo before the Xcode project
# exists is a supported path (install.sh calls it "fresh", /project-init scaffolds from there).
# What is rejected is a repo that positively identifies as something else.
GA_COMPAT_FOUND=""
GA_COMPAT_FOREIGN=""
GA_COMPAT_KIND=""

# ── Where GenericArch already lives ────────────────────────────────────────
# True when <dir> carries an install. Deliberately looser than "has a manifest": a run that was
# interrupted, or one whose manifest was deleted, still leaves a footprint that duplicates every
# command and skill. install.sh refuses to create a second one; uninstall.sh reports one it did
# not remove, so "back to its pre-install state" is never claimed while another copy is live.
ga_footprint_at() {
  [ -d "$1/$GA_STATE_DIR" ] || [ -d "$1/.claude/commands" ]
}

ga_check_compatible() {
  _ga_dir="$1"
  GA_COMPAT_FOUND=""; GA_COMPAT_FOREIGN=""; GA_COMPAT_KIND=""

  # -maxdepth 2 keeps this from walking a whole monorepo, and every marker below is a
  # repo-root-or-near-root artifact by convention.
  for _ga_m in "*.xcodeproj" "*.xcworkspace" "Package.swift" "*.playground"; do
    _ga_hit=$(find "$_ga_dir" -maxdepth 2 -name "$_ga_m" -not -path '*/.git/*' -print -quit 2>/dev/null)
    [ -n "$_ga_hit" ] && GA_COMPAT_FOUND="$GA_COMPAT_FOUND ${_ga_hit#"$_ga_dir"/}"
  done
  # The state dir is GenericArch's own footprint, not the target's. Counting anything under it as
  # the target's Swift code would make a re-install read as an
  # existing one, and silently stop staging the material that repo was installed with.
  _ga_hit=$(find "$_ga_dir" -name '*.swift' -not -path '*/.git/*' \
              -not -path "*/$GA_STATE_DIR/*" -print -quit 2>/dev/null)
  [ -n "$_ga_hit" ] && GA_COMPAT_FOUND="$GA_COMPAT_FOUND *.swift"

  for _ga_m in build.gradle build.gradle.kts settings.gradle settings.gradle.kts \
               AndroidManifest.xml pom.xml build.xml Cargo.toml go.mod \
               pubspec.yaml composer.json Gemfile requirements.txt pyproject.toml CMakeLists.txt \
               build.sbt mix.exs deno.json deno.jsonc setup.py Rakefile \
               Makefile GNUmakefile; do
    [ -e "$_ga_dir/$_ga_m" ] && GA_COMPAT_FOREIGN="$GA_COMPAT_FOREIGN $_ga_m"
  done
  # Build files that only exist under a glob, found the same bounded way as the Apple markers.
  for _ga_m in "*.sln" "*.csproj" "*.vcxproj" "*.cabal"; do
    _ga_hit=$(find "$_ga_dir" -maxdepth 2 -name "$_ga_m" -not -path '*/.git/*' -print -quit 2>/dev/null)
    [ -n "$_ga_hit" ] && GA_COMPAT_FOREIGN="$GA_COMPAT_FOREIGN ${_ga_hit#"$_ga_dir"/}"
  done
  # package.json alone is Node; beside an Xcode project it is React Native tooling and the Apple
  # markers already found decide the outcome.
  if [ -e "$_ga_dir/package.json" ] && [ -z "$GA_COMPAT_FOUND" ]; then
    GA_COMPAT_FOREIGN="$GA_COMPAT_FOREIGN package.json"
  fi
  # An android/ or app/src/main tree is Gradle even when the build file sits deeper.
  [ -d "$_ga_dir/app/src/main/java" ] && GA_COMPAT_FOREIGN="$GA_COMPAT_FOREIGN app/src/main/java"

  # A repo can hold a whole codebase and no build file at its root — a Java or C# tree with the
  # build one level up, a PHP site, a plain Makefile-less C project. Source files decide those,
  # but ONLY when no Apple marker was found: a Swift repo with a helper script in another language
  # is still a Swift repo, which the ordering below already guarantees.
  #
  # Scripts/ and .claude/ are skipped because GenericArch installs its own .py helpers there — on
  # a re-install into a repo that has not scaffolded its Xcode project yet, scanning them would
  # make the previous install look like a Python project and refuse the upgrade.
  #
  # .py/.js/.ts are deliberately absent: they are too often incidental tooling in an otherwise
  # Apple repo, and their real projects are already caught by the manifests above.
  if [ -z "$GA_COMPAT_FOUND" ]; then
    for _ga_x in java kt cs go rs rb php scala dart ex; do
      _ga_hit=$(find "$_ga_dir" -name "*.$_ga_x" \
                  -not -path '*/.git/*' -not -path '*/Scripts/*' -not -path '*/.claude/*' \
                  -print -quit 2>/dev/null)
      [ -n "$_ga_hit" ] && GA_COMPAT_FOREIGN="$GA_COMPAT_FOREIGN *.$_ga_x"
    done
  fi

  if [ -n "$GA_COMPAT_FOUND" ]; then
    GA_COMPAT_KIND="swift"
    return 0
  fi
  if [ -n "$GA_COMPAT_FOREIGN" ]; then
    GA_COMPAT_KIND="foreign"
    return 1
  fi
  GA_COMPAT_KIND="fresh"
  return 0
}

# ── The pre-manifest version stamp ─────────────────────────────────────────
# Installers up to v0.2.0 recorded the install as a plain `.genericarch-version` text file instead
# of a manifest. It is GENERATED, so there is no shipped blob to hash it against — but its shape is
# something only that installer writes: a version line, then `repo=` and `ref=`. That format is the
# proof of ownership, exactly as the managed block's markers are. Anything else keeps the file.
ga_is_version_stamp() {
  [ -f "$1" ] || return 1
  [ "$(wc -l < "$1" | tr -d ' ')" -le 5 ] || return 1
  grep -q '^repo=' "$1" || return 1
  grep -q '^ref=' "$1" || return 1
  head -1 "$1" | grep -qE '^v?[0-9]+\.[0-9]+\.[0-9]+' || return 1
  return 0
}

# ── Versions ───────────────────────────────────────────────────────────────
# The releases whose footprint uninstall.sh knows how to clean without a manifest. A version
# absent here is refused rather than guessed at: removing files by a list invented at runtime is
# exactly the failure mode the manifest exists to prevent.
GA_SUPPORTED_VERSIONS="v0.1.0 v0.2.0 v0.3.0 v0.4.0 v0.4.1 v0.4.2 v0.5.0 v0.6.0 v0.6.1"
GA_LATEST_VERSION="v0.6.1"

ga_is_supported_version() {
  case " $GA_SUPPORTED_VERSIONS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# Top-level paths a given release is known to install. This is the FALLBACK ONLY — used when the
# manifest is missing because install.sh was killed mid-run or blocked by the gate. Every path it
# yields is still verified by content hash against a reference source tree before anything is
# deleted; the list narrows the search, it never authorises a removal.
ga_known_paths() {
  case "$1" in
    v0.1.0)
      printf '%s\n' \
        .claude/skills .claude/commands \
        docs/modules docs/STRUCTURE.md docs/CONVENTIONS.md docs/DONE.md docs/REPO.md \
        docs/DELIVERY.md docs/PERFORMANCE.md \
        .swiftlint.yml .swiftformat \
        Scripts/check.sh Scripts/check-skill-triggers.py Scripts/detect-toolchain.sh \
        .genericarch-version
      ;;
    v0.2.0)
      # What v0.2.0 ACTUALLY shipped. Editing this list to match a later release is how a v0.2.0
      # uninstall starts hunting for files that release never wrote — the fallback narrows the
      # search, so a wrong entry is a wrong search.
      printf '%s\n' \
        .claude/skills .claude/commands .claude/INDEX.md .claude/MAP.tsv .claude/SCRIPTS.tsv \
        .claude/CANDIDATES.tsv .claude/notes .claude/memory \
        .swiftlint.yml .swiftformat \
        Scripts/check.sh Scripts/check-skill-triggers.py Scripts/detect-toolchain.sh \
        Scripts/adopt.sh Scripts/adopt-review.sh Scripts/build-plugin.sh Scripts/find.sh \
        Scripts/notes-staleness.sh Scripts/scan-colors.py Scripts/scan-fonts.py \
        Scripts/scan-unused-assets.py Scripts/scan-api-map.py Scripts/check-note-links.py \
        Scripts/detect-capabilities.sh Scripts/claude-workflows Scripts/claude-utils \
        Scripts/memory-add.py Scripts/verify-memory.sh Scripts/find-script.sh \
        Scripts/session-script.sh Scripts/ga-lifecycle.sh \
        docs/DECISIONS.md docs/GAPS.md docs/resources \
        install.sh uninstall.sh bootstrap.sh genericarch.installation.md \
        .genericarch-version
      ;;
    v0.3.0)
      # Adds the lifecycle tools, the offline note pass, the new-repo scaffold and the scoped package
      # rules. Drops install.sh and bootstrap.sh — v0.3.0 does not copy the installer into a target.
      printf '%s\n' \
        .claude/skills .claude/commands .claude/INDEX.md .claude/MAP.tsv .claude/SCRIPTS.tsv \
        .claude/CANDIDATES.tsv .claude/notes .claude/memory \
        .swiftlint.yml .swiftformat \
        Scripts/check.sh Scripts/check-skill-triggers.py Scripts/detect-toolchain.sh \
        Scripts/adopt.sh Scripts/adopt-review.sh Scripts/build-plugin.sh Scripts/find.sh \
        Scripts/notes-staleness.sh Scripts/scan-colors.py Scripts/scan-fonts.py \
        Scripts/scan-unused-assets.py Scripts/scan-api-map.py Scripts/check-note-links.py \
        Scripts/detect-capabilities.sh Scripts/claude-workflows Scripts/claude-utils \
        Scripts/memory-add.py Scripts/verify-memory.sh Scripts/find-script.sh \
        Scripts/session-script.sh Scripts/ga-lifecycle.sh \
        Scripts/ga-step.sh Scripts/ga-remove.sh Scripts/ga-reseal.sh Scripts/ga-scaffold.sh \
        Scripts/sync-notes.sh Scripts/ga-handoff.sh \
        Scaffold \
        docs/DECISIONS.md docs/GAPS.md docs/resources \
        uninstall.sh genericarch.installation.md \
        .genericarch-version
      ;;
    v0.4.0|v0.4.1)
      # v0.3.0 plus the two tools the empty-directory path needs: ga-project-setup.sh (the Xcode
      # toolchain gate and the four .xcconfig files) and ga-init-scan.sh (the offline half of
      # /project-init, which install.sh now runs itself). Both are copied, so both are removable.
      #
      # NOT listed, on purpose: .claude/notes/.evidence/. install.sh generates it rather than
      # copying it, so no hash can prove ownership — uninstall.sh removes it by name instead, in the
      # one place that knows it is generated.
      printf '%s\n' \
        .claude/skills .claude/commands .claude/INDEX.md .claude/MAP.tsv .claude/SCRIPTS.tsv \
        .claude/CANDIDATES.tsv .claude/notes .claude/memory \
        .swiftlint.yml .swiftformat \
        Scripts/check.sh Scripts/check-skill-triggers.py Scripts/detect-toolchain.sh \
        Scripts/adopt.sh Scripts/adopt-review.sh Scripts/build-plugin.sh Scripts/find.sh \
        Scripts/notes-staleness.sh Scripts/scan-colors.py Scripts/scan-fonts.py \
        Scripts/scan-unused-assets.py Scripts/scan-api-map.py Scripts/check-note-links.py \
        Scripts/detect-capabilities.sh Scripts/claude-workflows Scripts/claude-utils \
        Scripts/memory-add.py Scripts/verify-memory.sh Scripts/find-script.sh \
        Scripts/session-script.sh Scripts/ga-lifecycle.sh \
        Scripts/ga-step.sh Scripts/ga-remove.sh Scripts/ga-reseal.sh Scripts/ga-scaffold.sh \
        Scripts/ga-project-setup.sh Scripts/ga-init-scan.sh \
        Scripts/sync-notes.sh Scripts/ga-handoff.sh \
        Scaffold \
        docs/DECISIONS.md docs/GAPS.md docs/resources \
        uninstall.sh genericarch.installation.md \
        .genericarch-version
      ;;
    v0.6.1|v0.6.0|v0.5.0)
      # v0.6.1 and v0.6.0 ship the same set as v0.5.0: v0.6.0 changed install/uninstall BEHAVIOUR
      # and v0.6.1 what the scanners report, neither the file list — so the three share one arm
      # rather than duplicating twenty paths three times.
      #
      # NOT listed, for the same reason as .evidence/ below: CLAUDE-BK.md, migration-note.md and
      # GENERICARCH-ORPHANS.md. All three are generated in the target, never copied from the base,
      # so no hash can prove ownership — uninstall.sh handles each by name.
      #
      # v0.4.2 plus the two scanners that back the new commands: ga-cleanup-scan.sh (the candidate
      # sweep /clean-up-genericarch-extra-memory reads) and ga-sync-scan.sh (the drift and pattern
      # report /sync-with-genericarch reads). Both are read-only and offline; they are listed here
      # because they are COPIED, so a hash can prove ownership.
      #
      # .claude/commands is already a directory entry, so the two new command files need no row of
      # their own — that is why adding a command does not change this list, and adding a script does.
      #
      # NOT listed, on purpose: .claude/notes/.evidence/. install.sh generates it rather than
      # copying it, so no hash can prove ownership — uninstall.sh removes it by name instead.
      printf '%s\n' \
        .claude/skills .claude/commands .claude/INDEX.md .claude/MAP.tsv .claude/SCRIPTS.tsv \
        .claude/CANDIDATES.tsv .claude/notes .claude/memory \
        .swiftlint.yml .swiftformat \
        Scripts/check.sh Scripts/check-skill-triggers.py Scripts/detect-toolchain.sh \
        Scripts/adopt.sh Scripts/adopt-review.sh Scripts/build-plugin.sh Scripts/find.sh \
        Scripts/notes-staleness.sh Scripts/scan-colors.py Scripts/scan-fonts.py \
        Scripts/scan-unused-assets.py Scripts/scan-api-map.py Scripts/check-note-links.py \
        Scripts/detect-capabilities.sh Scripts/claude-workflows Scripts/claude-utils \
        Scripts/memory-add.py Scripts/verify-memory.sh Scripts/find-script.sh \
        Scripts/session-script.sh Scripts/ga-lifecycle.sh \
        Scripts/ga-step.sh Scripts/ga-remove.sh Scripts/ga-reseal.sh \
        Scripts/ga-project-setup.sh Scripts/ga-init-scan.sh \
        Scripts/ga-cleanup-scan.sh Scripts/ga-sync-scan.sh \
        Scripts/sync-notes.sh Scripts/ga-handoff.sh \
        docs/DECISIONS.md docs/GAPS.md docs/resources \
        uninstall.sh genericarch.installation.md \
        .genericarch-version
      ;;
    v0.4.2)
      # v0.4.1 minus what left for GenericXCodeSetup — Scaffold/ and ga-scaffold.sh — because this
      # base no longer writes a package layout. ga-project-setup.sh stays: it writes the .xcconfig
      # files an existing project should reference, so it is now part of every install rather than
      # of a new-repo one.
      #
      # NOT listed, on purpose: .claude/notes/.evidence/. install.sh generates it rather than
      # copying it, so no hash can prove ownership — uninstall.sh removes it by name instead.
      printf '%s\n' \
        .claude/skills .claude/commands .claude/INDEX.md .claude/MAP.tsv .claude/SCRIPTS.tsv \
        .claude/CANDIDATES.tsv .claude/notes .claude/memory \
        .swiftlint.yml .swiftformat \
        Scripts/check.sh Scripts/check-skill-triggers.py Scripts/detect-toolchain.sh \
        Scripts/adopt.sh Scripts/adopt-review.sh Scripts/build-plugin.sh Scripts/find.sh \
        Scripts/notes-staleness.sh Scripts/scan-colors.py Scripts/scan-fonts.py \
        Scripts/scan-unused-assets.py Scripts/scan-api-map.py Scripts/check-note-links.py \
        Scripts/detect-capabilities.sh Scripts/claude-workflows Scripts/claude-utils \
        Scripts/memory-add.py Scripts/verify-memory.sh Scripts/find-script.sh \
        Scripts/session-script.sh Scripts/ga-lifecycle.sh \
        Scripts/ga-step.sh Scripts/ga-remove.sh Scripts/ga-reseal.sh \
        Scripts/ga-project-setup.sh Scripts/ga-init-scan.sh \
        Scripts/sync-notes.sh Scripts/ga-handoff.sh \
        docs/DECISIONS.md docs/GAPS.md docs/resources \
        uninstall.sh genericarch.installation.md \
        .genericarch-version
      ;;
    *) return 1 ;;
  esac
}

# ── Directory hygiene ──────────────────────────────────────────────────────
# Remove directories that are empty AFTER the file removals, deepest first. A directory still
# holding a preserved user-edited file has a non-empty listing and survives untouched — which is
# the behaviour the "unless they still hold user-edited files" rule asks for, achieved by not
# special-casing it.
ga_prune_empty_dirs() {
  _ga_root="$1"; shift
  for _ga_d in "$@"; do
    _ga_p="$_ga_root/$_ga_d"
    while [ -d "$_ga_p" ] && [ "$_ga_p" != "$_ga_root" ]; do
      rmdir "$_ga_p" 2>/dev/null || break
      _ga_p="$(dirname "$_ga_p")"
    done
  done
}

# ── Tombstones ─────────────────────────────────────────────────────────────
# A file GenericArch installed and the product then DECLINED. Without this record a deletion is
# indistinguishable from "never installed", so the next install re-creates it — the add/delete/add
# flip that cost this project four commits. One row per declined path, append-only.
#
#   path <TAB> sha256-when-removed <TAB> removed-at <TAB> version <TAB> reason
GA_TOMBSTONES="TOMBSTONES.tsv"

# Where a declined file goes instead of being destroyed. Named for what a reader needs to know about
# it: everything in here is out of use, and deleting the whole directory loses nothing but the
# ability to `--revive`. Relative paths are preserved inside it.
GA_GRAVEYARD="safetodelete"

ga_tombstone_path() { printf '%s/%s/%s' "$1" "$GA_STATE_DIR" "$GA_TOMBSTONES"; }

# ga_grave_path <target> [relpath]
ga_grave_path() { printf '%s/%s/%s%s' "$1" "$GA_STATE_DIR" "$GA_GRAVEYARD" "${2:+/$2}"; }

ga_tombstone_init() {
  _ga_tf="$(ga_tombstone_path "$1")"
  [ -f "$_ga_tf" ] && return 0
  mkdir -p "$(dirname "$_ga_tf")"
  {
    printf '#\tGenericArch tombstones — paths this product declined. Append-only; never edit a row.\n'
    printf '#\tinstall.sh reads this BEFORE creating a file: a tombstoned path is reported, not written.\n'
    printf '#\tWritten by Scripts/ga-remove.sh. Undo with: ga-remove.sh --revive <path>\n'
    printf '#\tpath\tsha256\tremoved_at\tversion\treason\n'
  } > "$_ga_tf"
}

# ga_tombstoned <target> <relpath> → 0 when declined
ga_tombstoned() {
  _ga_tf="$(ga_tombstone_path "$1")"
  [ -f "$_ga_tf" ] || return 1
  awk -F'\t' -v p="$2" '$1!~/^#/ && $1==p {found=1; exit} END {exit !found}' "$_ga_tf"
}

ga_tombstone_reason() {
  _ga_tf="$(ga_tombstone_path "$1")"
  [ -f "$_ga_tf" ] || return 1
  awk -F'\t' -v p="$2" '$1!~/^#/ && $1==p {print $5; exit}' "$_ga_tf"
}

# ga_tombstone_add <target> <relpath> <sha> <version> <reason>
ga_tombstone_add() {
  ga_tombstone_init "$1"
  printf '%s\t%s\t%s\t%s\t%s\n' "$2" "$3" "$(ga_now_iso)" "$4" "$5" >> "$(ga_tombstone_path "$1")"
}

# ga_tombstone_drop <target> <relpath> — the only mutation allowed, and only via --revive
ga_tombstone_drop() {
  _ga_tf="$(ga_tombstone_path "$1")"
  [ -f "$_ga_tf" ] || return 1
  _ga_tmp="$_ga_tf.tmp"
  awk -F'\t' -v p="$2" '$1~/^#/ || $1!=p' "$_ga_tf" > "$_ga_tmp" && mv "$_ga_tmp" "$_ga_tf"
}

# ── Which kind of base tree is this? ───────────────────────────────────────
# Three different directories can hold the whole base, and only one of them is off-limits to the
# product lifecycle:
#
#   authoring checkout   a clone or fork of GenericArch — the repo where this file is edited
#   copy                 a PRODUCT repo that merely starts as a byte-for-byte copy of the base: the
#                        GitHub template path (WITHDRAWN — the repo's template flag is off, because a
#                        copy no installer wrote has no manifest, so uninstall.sh cannot prove
#                        ownership of anything), or the same thing done by hand. The detection stays
#                        regardless: copies made while that flag was on exist, and a hand fork is
#                        indistinguishable from one
#   consumer repo        install.sh wrote the base into it; `.claude-plugin/` never travels there
#
# The files cannot tell the first two apart. A GitHub template copies every TRACKED file, so
# `.claude-plugin/`, `Scripts/adopt.sh` and `README.md` are all present in MyApp too —
# "never travels" (docs/SHARING.md) is a statement about install.sh, not about a template. So no
# marker file can stand in for identity here, however specific it looks.
#
# What does differ is the HISTORY. A template copy starts at one fresh commit with no tags; a clone
# or a fork carries the base's release tags. With no git at all — an unpacked tarball — the
# directory name is all that is left, and the PRODUCT reading is the safe default there: a product
# mistaken for the base is silently blocked, while the base mistaken for a product changes nothing
# on its own — every write here asks first.
ga_has_base_markers() {
  [ -f "$1/.claude-plugin/plugin.json" ] && [ -f "$1/Scripts/adopt.sh" ]
}

# ga_is_source_checkout <dir> — the repo that AUTHORS the base, not a copy of it
# The #@kind line of a script, or empty. `lib` is the one value the installer must act on: a
# library is SOURCED by the scripts shipped beside it, so leaving an old copy in place does not
# preserve anything — it produces callers whose functions do not exist.
ga_staged_kind() {
  [ -f "$1" ] || return 0
  sed -n '1,25{s/^#@kind[[:space:]][[:space:]]*//p;}' "$1" | head -1 | tr -d '[:space:]'
}

ga_is_source_checkout() {
  ga_has_base_markers "$1" || return 1
  # Its own repository, not a directory sitting inside someone else's: compare physical paths, as
  # install.sh does, because git resolves symlinks and `cd`+`pwd` does not.
  _ga_top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$_ga_top" ] && [ "$_ga_top" = "$(cd "$1" && pwd -P)" ]; then
    git -C "$1" tag --merged HEAD 2>/dev/null | grep -Eq '^v?[0-9]+\.[0-9]+\.[0-9]+$'
  else
    [ "$(basename "$1" | tr '[:upper:]' '[:lower:]')" = genericarch ]
  fi
}

# ga_is_template_copy <dir> — the base's whole tree, but as the starting point of a PRODUCT
ga_is_template_copy() {
  ga_has_base_markers "$1" && ! ga_is_source_checkout "$1"
}

# ── Xcode-first: the project exists, the packages do not ───────────────────
# The user creates the .xcodeproj in Xcode — the one artifact nothing here generates (docs/REPO.md
# rejected Tuist and XcodeGen) — and only then installs. An .xcodeproj is an Apple marker, so every
# gate reads that directory as an EXISTING repo and skips the package layer that has not been
# written down anywhere. install.sh uses this to decide whether to offer the .xcconfig files, which
# is worth asking about rather than assuming either way.
#
# Judged on the PACKAGES, never on Swift files: a project created in Xcode ships MyApp/MyAppApp.swift
# and ContentView.swift, so "no .swift anywhere" would never match the case it is meant to catch.
ga_is_xcode_first() {
  [ -d "$1/Packages" ] && return 1
  [ -f "$1/Package.swift" ] && return 1
  for _ga_m in "$1"/*.xcodeproj "$1"/*.xcworkspace; do
    [ -e "$_ga_m" ] && return 0
  done
  return 1
}

# ── Step ledger ────────────────────────────────────────────────────────────
# The order commands must run in, and the record of which have run. A command that reorders itself
# reads a repo that is not yet in the state it assumes — /gaps before /project-init triages items
# nobody has decided, /sync-app-notes before either one writes nine notes off an unsurveyed tree.
#
# Canonical order. Position is the gate: a step requires every LOWER step to be recorded. There is
# no scaffold step: this base installs into a repo that already has an Xcode project, and the
# package layout for a repo that has none lives in GenericXCodeSetup.
GA_STEPS="install project-init gaps sync-app-notes ready"
GA_STEP_LEDGER="STEPS.tsv"

ga_step_path() { printf '%s/%s/%s' "$1" "$GA_STATE_DIR" "$GA_STEP_LEDGER"; }

ga_step_pos() {
  _ga_i=0
  for _ga_s in $GA_STEPS; do
    _ga_i=$((_ga_i + 1))
    [ "$_ga_s" = "$1" ] && { printf '%s' "$_ga_i"; return 0; }
  done
  return 1
}

ga_step_done() {
  _ga_lf="$(ga_step_path "$1")"
  [ -f "$_ga_lf" ] || return 1
  awk -F'\t' -v s="$2" '$1!~/^#/ && $1==s {found=1; exit} END {exit !found}' "$_ga_lf"
}

# ga_step_record <target> <step> [note]
ga_step_record() {
  _ga_lf="$(ga_step_path "$1")"
  if [ ! -f "$_ga_lf" ]; then
    mkdir -p "$(dirname "$_ga_lf")"
    {
      printf '#\tGenericArch step ledger — which lifecycle steps have run, in order.\n'
      printf '#\tWritten by Scripts/ga-step.sh record. Order: %s\n' "$GA_STEPS"
      printf '#\tstep\tat\tnote\n'
    } > "$_ga_lf"
  fi
  ga_step_done "$1" "$2" && return 0
  printf '%s\t%s\t%s\n' "$2" "$(ga_now_iso)" "${3:-}" >> "$_ga_lf"
}

# The first step in GA_STEPS that has not been recorded — what to run next.
ga_step_next() {
  for _ga_s in $GA_STEPS; do
    ga_step_done "$1" "$_ga_s" || { printf '%s' "$_ga_s"; return 0; }
  done
  printf 'ready'
}

# ga_step_missing <target> <step> → prints the unmet prerequisites, empty when clear
ga_step_missing() {
  _ga_want="$(ga_step_pos "$2")" || return 2
  _ga_i=0; _ga_out=""
  for _ga_s in $GA_STEPS; do
    _ga_i=$((_ga_i + 1))
    [ "$_ga_i" -ge "$_ga_want" ] && break
    ga_step_done "$1" "$_ga_s" || _ga_out="$_ga_out $_ga_s"
  done
  printf '%s' "${_ga_out# }"
}
