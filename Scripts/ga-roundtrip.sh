#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Prove install → uninstall is a round trip: a throwaway repo ends byte-identical to how it started, with no orphans.
#@usage     ga-roundtrip.sh [--keep]
#@in        --keep:flag(leave the scratch repos on disk for inspection)
#@out       stdout:per-case PASS/FAIL table
#@exit      0=every case passed 1=a case failed 2=usage
#@effects   writes only inside a scratch directory under $TMPDIR; never touches this repo or any target
#@when      did I break the installer|is uninstall clean|regression test the lifecycle|before releasing a version|ci check for install
#
# This is the test the eight-commit adoption history was, run deliberately instead of by accident:
#
#   1. clean round trip     install → uninstall leaves git status empty and exits 0
#   2. declined stays gone  ga-remove.sh → moved to safetodelete/, re-install must NOT re-create it,
#                           and --revive puts it back
#   3. reseal works         edit an installed file → reseal → uninstall removes it
#   4. orphans are reported edit without reseal → uninstall keeps it, reports it, exits 1
#   5. one root only        installing into a nested dir of an installed repo is refused
#   8. offline notes         sync-notes.sh classifies every note and needs no network
#   6. the two directions    a fresh repo gets the module material and the scaffold; an existing one
#                            gets neither, and its scaffold step is recorded not-applicable
#
# Every case runs against a git repo made from nothing, so a failure is this tooling's, never the
# host repo's. Requires a committed HEAD: the installer verifies referenced docs against the ref.
set -u
SRC="$(cd "$(dirname "$0")/.." && pwd)"
KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1
[ $# -gt 1 ] && { echo "usage: ga-roundtrip.sh [--keep]" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ga-roundtrip.XXXXXX")"
cleanup() { [ "$KEEP" -eq 1 ] || rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

RED=$'\033[31m'; GRN=$'\033[32m'; DIM=$'\033[2m'; BLD=$'\033[1m'; OFF=$'\033[0m'
fails=0
pass() { printf '  %sPASS%s  %s\n' "$GRN" "$OFF" "$1"; }
fail() { printf '  %sFAIL%s  %s\n' "$RED" "$OFF" "$1"; fails=$((fails + 1)); }

new_repo() {   # new_repo <name> → path to a fresh Swift-looking git repo
  d="$WORK/$1"; mkdir -p "$d"
  ( cd "$d" && git init -q . && : > App.swift && git add -A \
      && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1
  printf '%s' "$d"
}
# A repo with NO Swift file: the compatibility gate reads it as fresh, which is what selects the
# new-repo install. new_repo() seeds App.swift on purpose and would be read as an existing one.
new_empty_repo() {
  d="$WORK/$1"; mkdir -p "$d"
  ( cd "$d" && git init -q . \
      && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init ) >/dev/null 2>&1
  printf '%s' "$d"
}
install_into() { ( cd "$SRC" && GA_ASSUME_YES=1 ./install.sh "$1" ) >"$WORK/last.log" 2>&1; }
uninstall_in() { ( cd "$1" && GA_ASSUME_YES=1 ./uninstall.sh "$2" ) >"$WORK/last.log" 2>&1; }

VERSION="${GA_VERSION:-$(git -C "$SRC" tag --sort=-v:refname --merged HEAD 2>/dev/null | head -1)}"
[ -n "$VERSION" ] || { echo "no version tag reachable from HEAD — set GA_VERSION" >&2; exit 1; }

printf '%sGenericArch lifecycle round trip%s  %s(%s, scratch: %s)%s\n\n' \
  "$BLD" "$OFF" "$DIM" "$VERSION" "$WORK" "$OFF"

# ── 1. clean round trip ────────────────────────────────────────────────────
T="$(new_repo case1)"
if install_into "$T" && uninstall_in "$T" "$VERSION"; then
  dirty="$(cd "$T" && git status --porcelain)"
  [ -z "$dirty" ] && pass "clean round trip leaves no trace" \
                  || fail "clean round trip left: $(printf '%s' "$dirty" | tr '\n' ' ')"
else
  fail "clean round trip: install or uninstall exited non-zero (see $WORK/last.log)"
fi

# ── 2. a declined file must stay declined ──────────────────────────────────
T="$(new_repo case2)"
if install_into "$T"; then
  ( cd "$T" && GA_ASSUME_YES=1 ./Scripts/ga-remove.sh Scripts/scan-fonts.py \
      --reason "roundtrip test" --apply ) >/dev/null 2>&1
  install_into "$T"
  if [ -e "$T/Scripts/scan-fonts.py" ]; then
    fail "re-install re-created a declined file"
  elif [ ! -f "$T/.genericarch/safetodelete/Scripts/scan-fonts.py" ]; then
    fail "a declined file was destroyed instead of moved to safetodelete/"
  else
    pass "a declined file is not re-created, and its bytes are kept"
  fi
  ( cd "$T" && GA_ASSUME_YES=1 ./Scripts/ga-remove.sh --revive Scripts/scan-fonts.py --apply ) >/dev/null 2>&1
  [ -f "$T/Scripts/scan-fonts.py" ] && pass "--revive restores it from safetodelete/" \
                                    || fail "--revive did not restore the file"
else
  fail "case 2: install failed"
fi

# ── 3. reseal keeps an edited file removable ───────────────────────────────
T="$(new_repo case3)"
if install_into "$T"; then
  printf '\n# edited\n' >> "$T/Scripts/find.sh"
  ( cd "$T" && ./Scripts/ga-reseal.sh --apply ) >/dev/null 2>&1
  uninstall_in "$T" "$VERSION"
  [ -e "$T/Scripts/find.sh" ] && fail "reseal did not make an edited file removable" \
                              || pass "reseal keeps an edited file removable"
else
  fail "case 3: install failed"
fi

# ── 4. an unresealed edit is kept, reported, and exits non-zero ────────────
T="$(new_repo case4)"
if install_into "$T"; then
  printf '\n# edited, not resealed\n' >> "$T/Scripts/find.sh"
  uninstall_in "$T" "$VERSION" && rc=0 || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "partial uninstall exited 0 — a caller cannot tell it was partial"
  elif [ ! -e "$T/Scripts/find.sh" ]; then
    fail "an edited file was deleted"
  elif ! grep -q "Scripts/find.sh" "$T/.genericarch/orphans-$VERSION.txt" 2>/dev/null; then
    fail "the orphan was not written to the orphan report"
  else
    pass "an unresealed edit is kept, reported, and exits non-zero"
  fi
else
  fail "case 4: install failed"
fi

# ── 5. one install per checkout ────────────────────────────────────────────
T="$(new_repo case5)"
if install_into "$T"; then
  mkdir -p "$T/Nested"
  if install_into "$T/Nested"; then
    fail "a second root in the same checkout was allowed"
  else
    grep -q "already installed at another root" "$WORK/last.log" \
      && pass "a second root in the same checkout is refused" \
      || fail "the second install failed, but not for the root reason (see $WORK/last.log)"
  fi
else
  fail "case 5: install failed"
fi

# ── 6. existing vs new: the module material travels one way only ───────────
T="$(new_empty_repo case6new)"
if install_into "$T"; then
  missing=""
  for x in Scaffold/LAYOUT.tsv Scaffold/ARCHITECTURE-OPTIONS.md Scaffold/seed/Core Scripts/ga-scaffold.sh; do
    [ -e "$T/$x" ] || missing="$missing $x"
  done
  for x in .claude/skills/new-feature .claude/commands/review.md; do
    [ -e "$T/$x" ] || missing="$missing $x"
  done
  [ -z "$missing" ] && pass "a new repo gets the scaffold, the seed packages and the architecture layer" \
                    || fail "a new repo is missing:$missing"
  ( cd "$T" && GA_ASSUME_YES=1 ./Scripts/ga-scaffold.sh . --with navigation --apply ) >/dev/null 2>&1
  if [ ! -f "$T/Packages/Navigation/Package.swift" ]; then
    fail "the scaffold produced no manifest"
  elif grep -qE '\.iOS\(\.v|macOS\("' "$T/Packages/Navigation/Package.swift"; then
    fail "the scaffold wrote a deployment floor nobody chose"
  else
    pass "the scaffold writes no version — floors are detected or left unset"
  fi
else
  fail "case 6: install into a fresh repo failed"
fi

T="$(new_repo case6existing)"
: > "$T/Existing.swift"; mkdir -p "$T/Existing.xcodeproj"
( cd "$T" && git add -A && git -c user.email=t@t -c user.name=t commit -qm app ) >/dev/null 2>&1
if install_into "$T"; then
  leaked=""
  for x in Scaffold Packages docs/modules Scripts/ga-scaffold.sh; do
    [ -e "$T/$x" ] && leaked="$leaked $x"
  done
  for x in .claude/skills/new-feature .claude/commands/review.md; do
    [ -e "$T/$x" ] && leaked="$leaked $x"
  done
  if [ -n "$(awk -F'\t' '$2 ~ /^(module|pattern)/' "$T/.claude/MAP.tsv" 2>/dev/null | grep -c . | grep -v '^0$')" ]; then
    leaked="$leaked MAP.tsv:module/pattern-rows"
  fi
  if [ -n "$leaked" ]; then
    fail "an existing repo was given material that cannot fire:$leaked"
  elif ! grep -q "not applicable" "$T/.genericarch/STEPS.tsv" 2>/dev/null; then
    fail "the scaffold step was left pending on an existing repo — every later command is blocked"
  else
    pass "an existing repo gets no module material, and nothing waits on the scaffold step"
  fi
else
  fail "case 6: install into an existing repo failed"
fi

# ── 7. the architecture layer is opt-in, and the opt-in works ──────────────
T="$(new_repo case7)"
if ( cd "$SRC" && GA_ASSUME_YES=1 ./install.sh "$T" --with-architecture ) >"$WORK/last.log" 2>&1; then
  if [ -e "$T/.claude/skills/new-feature" ] && [ -e "$T/.claude/commands/review.md" ] \
     && [ -n "$(awk -F'\t' '$2 ~ /^module/' "$T/.claude/MAP.tsv" | grep -c . | grep -v '^0$')" ]; then
    pass "--with-architecture adds it to an existing repo"
  else
    fail "--with-architecture did not add the architecture layer"
  fi
else
  fail "case 7: install --with-architecture failed (see $WORK/last.log)"
fi

# ── 8. the offline note pass runs without Claude and without a network ─────
T="$(new_repo case8)"
if install_into "$T"; then
  ( cd "$T" && ./Scripts/sync-notes.sh --check ) >"$WORK/sn.log" 2>&1; rc=$?
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ] && [ "$rc" -ne 3 ]; then
    fail "sync-notes.sh --check exited $rc — expected 0 (in sync), 1 (drift) or 3 (no markers)"
  elif ! grep -q "Needs judgement" "$WORK/sn.log"; then
    fail "sync-notes.sh did not report which notes it refuses to generate"
  else
    pass "sync-notes.sh --check runs offline and classifies every note"
  fi
  ( cd "$T" && ./Scripts/sync-notes.sh --evidence ) >/dev/null 2>&1
  n=$(ls "$T"/.claude/notes/.evidence/*.tsv 2>/dev/null | grep -c . || echo 0)
  [ "$n" -ge 6 ] && pass "--evidence writes candidates for the judgement notes ($n files)" \
                 || fail "--evidence produced $n candidate file(s), expected 6"
  # A partial note must never read as complete: the caveat belongs INSIDE the managed block.
  if ( cd "$T" && ./Scripts/sync-notes.sh --init-markers ) >/dev/null 2>&1 \
     && ( cd "$T" && ./Scripts/sync-notes.sh --apply ) >/dev/null 2>&1; then
    # Only a note that actually received rows can be missing a caveat. An empty repo has no
    # imagesets, routers or xcconfigs, so those generators correctly write nothing at all.
    bad=""; checked=0
    for note in ASSETS-IMAGES API-MAP NAVIGATION SCHEMES; do
      f="$T/.claude/notes/$note.md"
      [ -f "$f" ] || continue
      rows=$(awk '/GA:ROWS —/ {inb=1; next} /GA:ROWS end/ {inb=0} inb && /^\|/ && $0 !~ /^\| *-+/' "$f" | grep -c . || echo 0)
      [ "$rows" -gt 2 ] || continue
      checked=$((checked + 1))
      grep -q 'incomplete on purpose' "$f" || bad="$bad $note"
    done
    if [ -n "$bad" ]; then
      fail "partial note(s) generated rows with no caveat:$bad"
    elif [ "$checked" -gt 0 ]; then
      pass "every partial note with rows states what its scan did not establish ($checked)"
    else
      pass "no partial note had generatable content in this repo — nothing claimed"
    fi
  else
    pass "no partial note had generatable content in this empty repo"
  fi
else
  fail "case 8: install failed"
fi

# ── 9. a partial note, against a repo that actually has content ────────────
# Case 8 runs on an empty repo, where every partial generator correctly writes nothing — which
# proves the classification but not the caveat. This builds the minimum a generator needs.
T="$(new_repo case9)"
mkdir -p "$T/Assets.xcassets/Logo.imageset"
printf '{"images":[{"filename":"a.png","scale":"1x"}],"appearances":[{"appearance":"luminosity","value":"dark"}]}\n' \
  > "$T/Assets.xcassets/Logo.imageset/Contents.json"
: > "$T/Assets.xcassets/Logo.imageset/a.png"
( cd "$T" && git add -A && git -c user.email=t@t -c user.name=t commit -qm assets ) >/dev/null 2>&1
if install_into "$T"; then
  ( cd "$T" && ./Scripts/sync-notes.sh --init-markers && ./Scripts/sync-notes.sh --apply ) >/dev/null 2>&1
  f="$T/.claude/notes/ASSETS-IMAGES.md"
  if ! grep -q 'Logo' "$f" 2>/dev/null; then
    fail "the ASSETS-IMAGES generator did not pick up an imageset that exists"
  elif ! grep -q 'incomplete on purpose' "$f"; then
    fail "a partial note was generated with rows and no caveat — it reads as complete"
  elif ! grep -q 'whether an asset is USED' "$f"; then
    fail "the caveat does not name what the scan failed to establish"
  else
    pass "a partial note carries its rows AND what it could not prove"
  fi
else
  fail "case 9: install failed"
fi

# ── 10. the scoped package rules reach a scaffolded repo ───────────────────
T="$(new_empty_repo case10)"
if install_into "$T"; then
  ( cd "$T" && GA_ASSUME_YES=1 ./Scripts/ga-scaffold.sh . --apply ) >/dev/null 2>&1
  if [ ! -f "$T/Packages/CLAUDE.md" ]; then
    fail "the scoped package rules never reached Packages/ — a session there loses §4, §7 and §9"
  elif [ -f "$T/Scaffold/seed/CLAUDE.md" ]; then
    fail "a bare CLAUDE.md sits in the staging tree — the harness may load it as real scoped rules"
  else
    pass "Packages/CLAUDE.md lands in a scaffolded repo, and nothing stray is named CLAUDE.md"
  fi
else
  fail "case 10: install failed"
fi

echo
if [ "$fails" -eq 0 ]; then
  printf '%s✓ every case passed%s\n' "$GRN" "$OFF"
  exit 0
fi
printf '%s✗ %d case(s) failed%s — scratch kept at %s\n' "$RED" "$fails" "$OFF" "$WORK"
KEEP=1
exit 1
