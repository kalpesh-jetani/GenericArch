#!/usr/bin/env bash
#@kind      util
#@platform  macos
#@claude    needs-approval
#@purpose   Remove the GenericArch v0.1.0 footprint from a repo, proving ownership by sha256 against the blobs at tag v0.1.0_Applied. Needs no manifest and no reference checkout.
#@usage     uninstallv0.1.0.sh [--target DIR] [--apply] [--yes] [--force] [--list]
#@in        --target:path(the repo to clean, default .) --apply:flag(delete) --yes:flag(skip prompt) --force:flag(allow GenericArch's own checkout) --list:flag(print the table and exit)
#@out       stdout:plan(action, path, reason) then a summary
#@exit      0=clean or plan printed 1=error or refused on the source repo 2=usage 3=nothing from this release is present 4=aborted at the prompt 78=not macOS
#@effects   dry run by default; with --apply deletes ONLY files whose sha256 matches the embedded table, then prunes directories left empty
#@when      remove a v0.1.0 install|uninstall genericarch v0.1.0|undo an install with no manifest
# Remove the GenericArch v0.1.0 footprint, and nothing else.
#
#   ./uninstallv0.1.0.sh                          # plan only — writes nothing
#   ./uninstallv0.1.0.sh --target /path/to/repo   # plan for another repo
#   ./uninstallv0.1.0.sh --apply                  # plan, ask, then delete
#   ./uninstallv0.1.0.sh --apply --yes            # no prompt (CI)
#   ./uninstallv0.1.0.sh --list                   # the embedded table, one path and hash per line
#
#   It refuses to run against a repo carrying GenericArch's own release tags — that is the source
#   repo, where these files are the originals rather than an install. --force overrides.
#
# Why this exists separately from ./uninstall.sh
#   uninstall.sh proves ownership from .genericarch/manifest-v<version>.json, and falls back to
#   hashing against a reference checkout (--base) when the manifest is missing. A v0.1.0 install
#   predates the manifest, so that fallback is the only path available — and it needs a GenericArch
#   checkout on the machine. This script carries the hashes inline instead, so it removes a v0.1.0
#   install on a machine with no checkout, no network and no manifest.
#
# What it will and will not delete
#   A file is removed only when its sha256 equals the hash this release shipped. A file whose hash
#   differs has been edited after install: it is kept, listed, and the reason given. A path absent
#   from the table below is never looked at, let alone removed. The table is therefore the complete
#   and only authority for what this script can touch.
#
# Scope — 35 files, the v0.1.0 footprint
#   Generated from tag v0.1.0_Applied (commit 5844d6c76f8b8e0f2cb27f4f2e50e223b0d5f01f), restricted
#   to the paths ga_known_paths() records for v0.1.0 in Scripts/ga-lifecycle.sh. That tag is a
#   main-line commit which also carries v0.2.0-era work: .claude/MAP.tsv, .claude/SCRIPTS.tsv,
#   .claude/memory/, Scripts/claude-workflows/, Scripts/claude-utils/, docs/DECISIONS.md,
#   docs/GAPS.md, install.sh. Those are deliberately not in this table — they are not part of
#   v0.1.0, and three of them hold the consumer's own content rather than GenericArch's.
#
#   Regenerate a row with:
#     git cat-file blob "v0.1.0_Applied^{commit}:<path>" | shasum -a 256
if [ "$(uname -s)" != Darwin ]; then
  printf 'This script is macOS-only (found: %s).\n' "$(uname -s)" >&2
  exit 78
fi

EX_OK=0; EX_ERR=1; EX_USAGE=2; EX_NOTHING=3; EX_ABORT=4

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED=$(printf '\033[31m'); GRN=$(printf '\033[32m'); YEL=$(printf '\033[33m')
  DIM=$(printf '\033[2m');  BLD=$(printf '\033[1m'); OFF=$(printf '\033[0m')
else
  RED=; GRN=; YEL=; DIM=; BLD=; OFF=
fi

die()  { printf '%s✗ %s%s\n' "$RED" "$1" "$OFF" >&2; exit "${2:-$EX_ERR}"; }
ok()   { printf '%s✓ %s%s\n' "$GRN" "$1" "$OFF"; }
warn() { printf '%s! %s%s\n' "$YEL" "$1" "$OFF"; }
dim()  { printf '%s%s%s\n' "$DIM" "$1" "$OFF"; }
hdr()  { printf '\n%s%s%s\n' "$BLD" "$1" "$OFF"; }

usage() {
  awk 'NR == 1 && /^#!/ { next } /^#@/ { next }
       /^#/ { sub(/^#[ ]?/, ""); print; next } { exit }' "$0"
  exit "${1:-$EX_USAGE}"
}

# path<TAB>sha256, exactly as tag v0.1.0_Applied shipped them. The single authority for what may be
# deleted; a path not listed here is never touched.
embedded_table() {
  cat <<'TABLE'
.claude/commands/build.md	89892b198bfed69ca849fed7ccf7f86b5d92b6aecbaa684964aaf755ad681874
.claude/commands/decide.md	d497ed3b98ff3ba04795ede87884de20535b1ce79bbd301ba5bc69ccf0fe1cc5
.claude/commands/find.md	366796d9e2ed8fac3bbf4fbaa67a5cde59b2c36564a8f1b58af9a776b8f466f1
.claude/commands/gaps.md	105e9c80af56cd2969b75f8781e17425a1034cf5c70ccd84c2c7c8a91d00f1bf
.claude/commands/learn.md	1df4b8fa61e7e66758e00dd59778e66c6c6f4235c16aa48e97592c65e67f308e
.claude/commands/project-init.md	9cd1f95c954742171f88c1d5d41fd929fd27af2fab03095a5de107bb11a18bbe
.claude/commands/review.md	6702d96f0a5f0dafb603be57c1ef905158758a9781de1d28e7b24a92e693987a
.claude/commands/sync-app-notes.md	e8f97d05a25d8551834f4e03828ec20e98f70675a6a9dce7b3cdec5792ac03f4
.claude/commands/upgrade-stack.md	87afa6eef87ca40b057a0d6597ad8f009d5a2b6cc7280fdb71dfcc549ddfcdf1
.claude/commands/verify.md	956bf21d66e029ca12fab57e0056ee00594db924997b17f0a0629a2f2b27183f
.claude/skills/debug/SKILL.md	ca6c82b4f227f4b486f9982f3e0f804f4de76cb23f16c4b4428538022b954ca1
.claude/skills/new-feature/SKILL.md	61c7bd3901474860616c3ad41a69a4317664505cba1608f9220fd44f3af83e91
.swiftformat	b29ba9c484935af26718d8be39cdda4547a250e6c3ea49924e8028ef33638832
.swiftlint.yml	2ef193c4918e40c91c3312a27eb6001e11dfe3099e05efe00e80d763a3af1f98
Scripts/check-skill-triggers.py	d162b54a7334ce20f63f10a4ee1287ad1db6ae8fc62a0011e0d654aee30506fe
Scripts/check.sh	e1a0c2fd59cf0a8059406e38efad0686007e1310e54adc5bdb99a1dcd0a6ad40
Scripts/detect-toolchain.sh	f431aab4f3f0b1a6a1f00e077a58cb6545ca40ff1591ccee979a465513263ca0
docs/CONVENTIONS.md	90bf7cc88a1d9b337ee8e0573161643018daa851b436e132d8f347d9d955840c
docs/DELIVERY.md	831e753985742dec8a1523f8925cd0c2f72af06b22c46c66deb4a3470f3f92a8
docs/DONE.md	4f344c80ccd328c425d160877d37a7365881768fac26cff33576b241f6a01f46
docs/PERFORMANCE.md	b72b99c64562f722e89bd812882e016ee754602b11d586928b4f05310af50981
docs/REPO.md	cdae13857158dba26611048fb8fe4c2d15d8b79329d04709e5fef72399234d23
docs/STRUCTURE.md	233234bf93b2f7599c85cab53fb152850ed572fa65c16b669e3b887edf660579
docs/modules/AppShell.md	a001173d2f5b8b20dd8afb56181bc442b6275066805be7112b15cb6f527a557e
docs/modules/Core.md	ba8ddef1fea4823fe2d43ffcb9372e4b21817a42adb69333019039cd898afff1
docs/modules/DIKit.md	1dc53a717bd6c3aea39e4df6efb0ad70cefccdd8000bd97ecfb5d5c23de691e2
docs/modules/DesignSystem.md	0bf39b39418e2c595e3d452a59b404bbc378f960a68ec1606ca5c27538392fe3
docs/modules/ImageCache.md	5a53dc9e1dedcfe0cbbad2099555e101f137eabb5a40fddb69ad0c85befc519b
docs/modules/LocalizationKit.md	50c6562f73b41e9ddb87e0481345a4bd8997bdbd080d08f9e7bdf4c32bff6ee4
docs/modules/LoggingKit.md	d0e727d09abb0161ac692f191bf7264984104d9d4c84a2db44a42dbca8a13b7c
docs/modules/Messaging.md	ae950e93b60bd359952266d6409227c00e76cf1344f445d32699166751337aba
docs/modules/Navigation.md	a04f5dd258de8b2a6157cb270e73df5da5b16f842939f6237ebee874786badef
docs/modules/NetworkKit.md	e59fbd5c3aa28cc39983faac3b0e58fa0d2ee0adcda5c965a4975055844efc8c
docs/modules/NotificationKit.md	d76e650aaf6a8c968698a99bfb828696f02001a8987e15c2ef300d799670ff6a
docs/modules/StorageKit.md	52e0410dfe53210203ff113c4d94cb9c99f33654883e8cada57f25bff0d6ce36
TABLE
}

TARGET="."; APPLY=0; ASSUME_YES=0; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --target)   [ -n "${2:-}" ] || die "--target needs a directory" "$EX_USAGE"
                TARGET="$2"; shift 2 ;;
    --apply)    APPLY=1; shift ;;
    --yes|-y)   ASSUME_YES=1; shift ;;
    --force|-f) FORCE=1; shift ;;
    --list)     embedded_table; exit "$EX_OK" ;;
    -h|--help)  usage "$EX_OK" ;;
    *)          die "unknown argument: $1" "$EX_USAGE" ;;
  esac
done

[ -d "$TARGET" ] || die "not a directory: $TARGET" "$EX_USAGE"
TARGET="$(cd "$TARGET" && pwd)" || die "cannot enter $TARGET" "$EX_ERR"

# Refuse to run against GenericArch itself. Ownership here is proven by hash alone, and most of
# v0.1.0's files are still byte-identical at HEAD — so in the source repo every one of them looks
# like an install to remove, and running --apply would delete the originals rather than a copy of
# them. A consumer repo has its own history and none of these tags; the base repo and its forks
# carry them, which is what separates the two.
if git -C "$TARGET" cat-file -e 'v0.1.0_Applied^{commit}' 2>/dev/null \
   || git -C "$TARGET" cat-file -e 'v0.1.0^{commit}' 2>/dev/null; then
  if [ "$FORCE" -eq 0 ]; then
    die "$TARGET carries GenericArch's own release tags — this is the source repo or a fork of it,
    not a repo that installed v0.1.0. Removing these files here deletes the originals.
    If you really mean it, re-run with --force." "$EX_ERR"
  fi
  warn "--force given — treating GenericArch's own checkout as an install target"
fi

TMP="${TMPDIR:-/tmp}/ga-uninstall-v010.$$"
mkdir -p "$TMP" || die "cannot create temp dir" "$EX_ERR"
trap 'rm -rf "$TMP"' EXIT INT TERM
: > "$TMP/remove"; : > "$TMP/keep"; : > "$TMP/absent"

TAB="$(printf '\t')"
while IFS="$TAB" read -r rel want; do
  [ -n "$rel" ] || continue
  abs="$TARGET/$rel"
  if [ ! -f "$abs" ]; then
    printf '%s\n' "$rel" >> "$TMP/absent"
    continue
  fi
  got="$(shasum -a 256 "$abs" 2>/dev/null | awk '{print $1}')"
  if [ -z "$got" ]; then
    printf '%s%scannot be hashed — left alone\n' "$rel" "$TAB" >> "$TMP/keep"
  elif [ "$got" = "$want" ]; then
    printf '%s\n' "$rel" >> "$TMP/remove"
  else
    printf '%s%syou edited it — content hash does not match v0.1.0\n' "$rel" "$TAB" >> "$TMP/keep"
  fi
done <<EOF
$(embedded_table)
EOF

n_remove=$(wc -l < "$TMP/remove" | tr -d ' ')
n_keep=$(wc -l < "$TMP/keep" | tr -d ' ')
n_absent=$(wc -l < "$TMP/absent" | tr -d ' ')
n_total=$(embedded_table | wc -l | tr -d ' ')

printf '\n%sGenericArch v0.1.0 uninstaller%s\n' "$BLD" "$OFF"
printf '  target   %s\n' "$TARGET"
printf '  source   tag v0.1.0_Applied (5844d6c)\n'
if [ "$APPLY" -eq 1 ]; then
  printf '  mode     %sAPPLY%s\n' "$YEL" "$OFF"
else
  printf '  mode     %sdry run%s (add --apply to delete)\n' "$GRN" "$OFF"
fi

if [ "$n_remove" -eq 0 ] && [ "$n_keep" -eq 0 ]; then
  hdr "nothing to do"
  dim "  none of v0.1.0's $n_total files are present in this repo"
  exit "$EX_NOTHING"
fi

if [ "$n_remove" -gt 0 ]; then
  hdr "WILL REMOVE — hash matches what v0.1.0 shipped ($n_remove)"
  sed 's/^/    /' "$TMP/remove"
fi

if [ "$n_keep" -gt 0 ]; then
  hdr "KEPT — not deleted ($n_keep)"
  awk -F'\t' -v d="$DIM" -v o="$OFF" '{printf "    · %s\n        %s%s%s\n", $1, d, $2, o}' "$TMP/keep"
fi

printf '\n  %s%s absent, %s kept, %s to remove, of %s in this release%s\n' \
  "$DIM" "$n_absent" "$n_keep" "$n_remove" "$n_total" "$OFF"

if [ "$APPLY" -eq 0 ]; then
  printf '\n'
  dim "dry run — nothing was written. Re-run with --apply to delete the list above."
  exit "$EX_OK"
fi

if [ "$ASSUME_YES" -eq 0 ]; then
  printf '\n%sRemove GenericArch v0.1.0 from %s?%s [y/N] ' "$BLD" "$TARGET" "$OFF"
  read -r reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) printf '\n'; warn "aborted — nothing was written"; exit "$EX_ABORT" ;;
  esac
fi

failed=0; removed=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  if rm -f "$TARGET/$rel"; then
    removed=$((removed + 1))
  else
    warn "could not remove $rel"
    failed=$((failed + 1))
  fi
done < "$TMP/remove"

# Deepest first, so a parent is only considered once its children are gone. A directory still
# holding a kept file is non-empty, rmdir refuses, and it survives untouched.
embedded_table | cut -f1 | sed 's|/[^/]*$||' | sort -ru | while IFS= read -r d; do
  p="$TARGET/$d"
  while [ -d "$p" ] && [ "$p" != "$TARGET" ]; do
    rmdir "$p" 2>/dev/null || break
    p="$(dirname "$p")"
  done
done

hdr "Removed GenericArch v0.1.0"
ok "$removed file(s) deleted"
[ "$n_keep" -gt 0 ] && dim "  $n_keep file(s) kept because you had edited them — listed above"
[ "$failed" -gt 0 ] && die "$failed file(s) could not be removed" "$EX_ERR"
exit "$EX_OK"
