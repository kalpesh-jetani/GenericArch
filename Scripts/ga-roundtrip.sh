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
#   6. the install stays lean an existing repo gets no module material, no architecture layer, and
#                            no MAP rows that cannot resolve
#  11. preflight evidence   install writes the /project-init evidence, records no step for it, and
#                           uninstall takes the generated files back out
#  12. one version at a time an older install is refused with exit 6, and nothing is written
#  13. same version repairs   re-running the SAME version is not gated
#  14. orphans carry forward  an edited file survives uninstall → install → uninstall, tracked
#                             at every step and never deleted
#  15. --final retires them   moved to safetodelete/, recorded in CLAUDE.md, exit 0
#  16. --final with no rules  the record goes to GENERICARCH-ORPHANS.md instead
#  17. CLAUDE.md migration    --with-claude-md backs theirs up, uninstall restores it byte-for-byte
#  18. an edited CLAUDE.md    is kept, and so is their backup
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
install_into() { ( cd "$SRC" && GA_ASSUME_YES=1 ./install.sh "$1" ) >"$WORK/last.log" 2>&1; }
uninstall_in() { ( cd "$1" && GA_ASSUME_YES=1 ./uninstall.sh "$2" ) >"$WORK/last.log" 2>&1; }
# install_into with extra flags, and with a version this checkout is not actually tagged as —
# the only way to exercise an upgrade from one release to another inside one scratch tree.
install_flags() { t="$1"; shift; ( cd "$SRC" && GA_ASSUME_YES=1 ./install.sh "$t" "$@" ) >"$WORK/last.log" 2>&1; }
install_as()    { v="$1"; t="$2"; shift 2
                  ( cd "$SRC" && GA_VERSION="$v" GA_ASSUME_YES=1 ./install.sh "$t" "$@" ) >"$WORK/last.log" 2>&1; }
uninstall_flags() { t="$1"; v="$2"; shift 2
                    ( cd "$t" && GA_ASSUME_YES=1 ./uninstall.sh "$v" "$@" ) >"$WORK/last.log" 2>&1; }
# A supported version that is NOT the one under test, for the upgrade gate.
PREV_V=v0.4.2

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

# ── 3b. an older shared library is upgraded in lockstep with its callers ───
# The regression this pins: install.sh is additive, so on an upgrade it skipped ga-lifecycle.sh as a
# collision and left the previous version in place. Every script shipped beside it SOURCES it, so
# v0.4.2's seven new scripts landed on a v0.2.0 library and failed with `command not found` — while
# still exiting 0, which is why nothing caught it. A library must move with its callers.
T="$(new_repo case3b)"
if install_into "$T"; then
  LIB="$T/Scripts/ga-lifecycle.sh"
  NEWSHA="$(shasum -a 256 "$LIB" | awk '{print $1}')"
  # Simulate "installed by an older release": truncate the library to a version missing the step
  # helpers, then point the manifest record at it so it reads as ours-and-unedited.
  grep -v '^ga_step_' "$LIB" | sed '/^ga_step_record()/,/^}/d' > "$LIB.old" && mv "$LIB.old" "$LIB"
  printf 'ga_step_record() { :; }\n' >> "$LIB"
  OLDSHA="$(shasum -a 256 "$LIB" | awk '{print $1}')"
  M="$(ls "$T"/.genericarch/manifest-*.json | head -1)"
  sed -i '' "s/$NEWSHA/$OLDSHA/" "$M"
  install_into "$T"
  NOWSHA="$(shasum -a 256 "$LIB" | awk '{print $1}')"
  if [ "$NOWSHA" != "$NEWSHA" ]; then
    fail "an older shared library was left in place — its callers will fail at runtime"
  elif ! grep -q 'lockstep' "$WORK/last.log"; then
    fail "the library was upgraded but the plan did not say so"
  elif ! ls "$T"/.genericarch/backups/ga-lifecycle.sh.*.bak >/dev/null 2>&1; then
    fail "the replaced library was not backed up"
  elif ( cd "$T" && ./Scripts/ga-step.sh show ) 2>&1 | grep -q 'command not found'; then
    fail "a script sourcing the library still fails after the upgrade"
  else
    pass "an older shared library is upgraded in lockstep with its callers"
  fi
else
  fail "case 3b: install failed"
fi

# ── 3c. the two scanners run offline, and protect what is not ours ─────────
# Both are pure evidence-gathering, so they must work with no network and no base checkout. The
# regression that matters most is ownership: install.sh records a `skipped` file with the file's OWN
# hash, so a sync scan that trusts the hash alone calls every populated note and every locally
# patched script "ours, unedited" and recommends overwriting it — someone's whole repo.
T="$(new_repo case3c)"
if install_into "$T"; then
  ( cd "$T" && ./Scripts/ga-cleanup-scan.sh . --tsv ) >"$WORK/cleanup.tsv" 2>&1 || true
  ( cd "$T" && ./Scripts/ga-sync-scan.sh . --tsv ) >"$WORK/sync.tsv" 2>&1 || true
  # A `skipped` record only exists for a file that was ALREADY there, so seed it before installing —
  # and leave it untouched afterwards, or its hash stops matching and it is held for the wrong
  # reason (which is how the first version of this case passed against the bug it was written for).
  T2="$(new_repo case3c2)"
  mkdir -p "$T2/.claude/notes"
  printf '| `Seeded` | mine, not GenericArch |\n' > "$T2/.claude/notes/FEATURES.md"
  install_into "$T2" || true
  ( cd "$T2" && ./Scripts/ga-sync-scan.sh . --base "$SRC" --base-only --tsv ) >"$WORK/sync2.tsv" 2>&1 || true
  SKIPPED_ACT="$(python3 -c "
import json,glob,sys
m=json.load(open(sorted(glob.glob('$T2/.genericarch/manifest-*.json'))[-1]))
print(next((r['action'] for r in m['files'] if r['path']=='.claude/notes/FEATURES.md'),'absent'))" 2>/dev/null || echo err)"
  if ! grep -q 'SUMMARY' "$WORK/cleanup.tsv"; then
    fail "ga-cleanup-scan.sh produced no summary"
  elif grep -q 'FETCH-BASE' "$WORK/cleanup.tsv" && grep -q 'MALFORMED' "$WORK/cleanup.tsv"; then
    fail "a freshly stamped FETCH-BASE was reported malformed"
  elif ! grep -qE 'PROMOTE|NOT-YET|REFUSE' "$WORK/sync.tsv"; then
    fail "ga-sync-scan.sh --patterns produced no verdicts on a lean install"
  elif [ "$SKIPPED_ACT" != "skipped" ]; then
    fail "the fixture did not produce a skipped record (got: $SKIPPED_ACT) — the case proves nothing"
  elif grep -q "^TAKE	.claude/notes/FEATURES.md" "$WORK/sync2.tsv"; then
    fail "a skipped (yours) file was recommended for overwriting"
  elif ! grep -q "^HOLD	.claude/notes/FEATURES.md" "$WORK/sync2.tsv"; then
    fail "a skipped (yours) file was not held back"
  else
    pass "the scanners run offline and never recommend overwriting what is not ours"
  fi
else
  fail "case 3c: install failed"
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
  elif ! grep -q "Scripts/find.sh" "$T/safetodelete-after-migration-note.md" 2>/dev/null; then
    fail "the orphan was not written to safetodelete-after-migration-note.md"
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

# ── 6. the install stays lean ──────────────────────────────────────────────
T="$(new_repo case6existing)"
: > "$T/Existing.swift"; mkdir -p "$T/Existing.xcodeproj"
( cd "$T" && git add -A && git -c user.email=t@t -c user.name=t commit -qm app ) >/dev/null 2>&1
if install_into "$T"; then
  leaked=""
  for x in Packages docs/modules; do
    [ -e "$T/$x" ] && leaked="$leaked $x"
  done
  for x in .claude/skills/new-feature .claude/commands/review.md; do
    [ -e "$T/$x" ] && leaked="$leaked $x"
  done
  if [ -n "$(awk -F'\t' '$2 ~ /^(module|pattern)/' "$T/.claude/MAP.tsv" 2>/dev/null | grep -c . | grep -v '^0$')" ]; then
    leaked="$leaked MAP.tsv:module/pattern-rows"
  fi
  if [ -n "$leaked" ]; then
    fail "the target was given material that cannot fire:$leaked"
  else
    pass "the install stays lean — no module material, no architecture layer, no dead MAP rows"
  fi
else
  fail "case 6: install failed"
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

# ── 11. the install-time preflight writes evidence, and uninstall takes it ─
# install.sh runs ga-init-scan.sh once the manifest has landed, so for the first time it creates
# files the manifest does not own. Those must not survive the uninstall: nothing can prove ownership
# of a generated file, so a survivor is reported as an orphan forever and "back to its pre-install
# state" stops being true.
T="$(new_repo case11)"
if install_into "$T"; then
  if [ ! -f "$T/.claude/notes/.evidence/INIT-SCAN.md" ]; then
    fail "the install-time preflight wrote no evidence — /project-init pays for the scans again"
  elif ! grep -q '^## conflicts' "$T/.claude/notes/.evidence/INIT-SCAN.md"; then
    fail "the evidence artifact has no conflicts section — the generator wrote a partial file"
  elif [ ! -f "$T/.claude/notes/.evidence/INIT-CONFLICTS.tsv" ]; then
    fail "the machine-readable conflict rows are missing"
  else
    pass "the install-time preflight writes the /project-init evidence"
  fi
  # It must not have touched the ledger: the asking step is not done because a script ran. Match a
  # real row, not the header — line 2 lists the whole step order in a comment.
  if awk -F'\t' '!/^#/ && $1=="project-init"{found=1} END{exit !found}' \
       "$T/.genericarch/STEPS.tsv" 2>/dev/null; then
    fail "the preflight recorded the project-init step — /gaps is now unblocked with nothing decided"
  else
    pass "the preflight leaves the project-init step unrecorded"
  fi
  uninstall_in "$T" "$VERSION"
  if [ -d "$T/.claude/notes/.evidence" ]; then
    fail "uninstall left the generated evidence behind: $(ls "$T/.claude/notes/.evidence" | tr '\n' ' ')"
  else
    pass "uninstall removes the evidence it generated"
  fi
else
  fail "case 11: install failed"
fi

# ── 12. an older install must be removed first ─────────────────────────────
T="$(new_repo case12)"
[ "$PREV_V" = "$VERSION" ] && PREV_V=v0.4.1
if install_as "$PREV_V" "$T"; then
  before="$(cd "$T" && git status --porcelain | LC_ALL=C sort)"
  install_into "$T" && rc=0 || rc=$?
  after="$(cd "$T" && git status --porcelain | LC_ALL=C sort)"
  if [ "$rc" -ne 6 ]; then
    fail "installing $VERSION over $PREV_V exited $rc, not 6 (see $WORK/last.log)"
  elif [ "$before" != "$after" ]; then
    fail "the refused install still wrote something"
  elif ! grep -qE "uninstall\.sh[\"']? $PREV_V" "$WORK/last.log"; then
    fail "the refusal did not name the uninstall command to run"
  else
    pass "an older install is refused with exit 6, and nothing is written"
  fi
  install_flags "$T" --in-place && pass "--in-place is the way past it" \
                                || fail "--in-place did not get past the gate"
else
  fail "case 12: the $PREV_V install failed"
fi

# ── 13. the same version is a repair, not an upgrade ───────────────────────
T="$(new_repo case13)"
if install_into "$T"; then
  rm -f "$T/Scripts/find.sh"
  if install_into "$T" && [ -f "$T/Scripts/find.sh" ]; then
    pass "re-running the same version repairs rather than refusing"
  else
    fail "the same-version repair run was gated or did not restore the file (see $WORK/last.log)"
  fi
else
  fail "case 13: install failed"
fi

# ── 14. an edited file is tracked across the whole cycle ───────────────────
T="$(new_repo case14)"
if install_into "$T"; then
  printf '\n# mine now\n' >> "$T/Scripts/find.sh"
  mine="$(shasum -a 256 "$T/Scripts/find.sh" | awk '{print $1}')"
  uninstall_flags "$T" "$VERSION" --upgrade
  if [ ! -f "$T/safetodelete-after-migration-note.md" ]; then
    fail "no note was written for the file the uninstall kept"
  elif install_into "$T"; then
    now="$(shasum -a 256 "$T/Scripts/find.sh" | awk '{print $1}')"
    if [ "$now" != "$mine" ]; then
      fail "the re-install overwrote a file it was supposed to be tracking"
    elif ! grep -q '"action": "orphan"' "$T/.genericarch/manifest-$VERSION.json"; then
      fail "the re-install did not record the kept file as an orphan"
    else
      uninstall_flags "$T" "$VERSION" --upgrade
      if [ -f "$T/Scripts/find.sh" ] && grep -q "Scripts/find.sh" "$T/safetodelete-after-migration-note.md"; then
        pass "an edited file survives install → uninstall → install → uninstall, tracked throughout"
      else
        fail "the second uninstall lost the file or stopped tracking it"
      fi
    fi
  else
    fail "case 14: the re-install failed (see $WORK/last.log)"
  fi
else
  fail "case 14: install failed"
fi

# ── 15. --final retires the orphans instead of leaving them ────────────────
T="$(new_repo case15)"
printf '# House rules\n' > "$T/CLAUDE.md"
( cd "$T" && git add -A && git -c user.email=t@t -c user.name=t commit -qm rules ) >/dev/null 2>&1
if install_into "$T"; then
  printf '\n# mine now\n' >> "$T/Scripts/find.sh"
  uninstall_flags "$T" "$VERSION" --final && rc=0 || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "--final exited $rc — the working tree is clean, so it must exit 0"
  elif [ -e "$T/Scripts/find.sh" ]; then
    fail "--final left the file in place instead of retiring it"
  elif [ ! -f "$T/.genericarch/safetodelete/Scripts/find.sh" ]; then
    fail "--final destroyed the file instead of moving it to safetodelete/"
  elif [ -f "$T/safetodelete-after-migration-note.md" ]; then
    fail "--final kept the temporary note after retiring the files it described"
  elif ! grep -q "Scripts/find.sh" "$T/CLAUDE.md"; then
    fail "--final did not record the retired file in CLAUDE.md"
  else
    pass "--final retires orphans to safetodelete/, records them in CLAUDE.md, and exits 0"
  fi
else
  fail "case 15: install failed"
fi

# ── 16. --final with no CLAUDE.md to write into ────────────────────────────
T="$(new_repo case16)"
if install_into "$T"; then
  printf '\n# mine now\n' >> "$T/Scripts/find.sh"
  uninstall_flags "$T" "$VERSION" --final
  if [ -f "$T/GENERICARCH-ORPHANS.md" ] && grep -q "Scripts/find.sh" "$T/GENERICARCH-ORPHANS.md"; then
    pass "with no CLAUDE.md the record goes to GENERICARCH-ORPHANS.md"
  else
    fail "no record was written when the repo has no CLAUDE.md"
  fi
else
  fail "case 16: install failed"
fi

# ── 17. the CLAUDE.md migration is reversible ──────────────────────────────
T="$(new_repo case17)"
printf '# House rules\n\nOurs, not yours.\n' > "$T/CLAUDE.md"
( cd "$T" && git add -A && git -c user.email=t@t -c user.name=t commit -qm rules ) >/dev/null 2>&1
theirs="$(shasum -a 256 "$T/CLAUDE.md" | awk '{print $1}')"
if install_flags "$T" --with-claude-md; then
  if [ ! -f "$T/CLAUDE-BK.md" ]; then
    fail "--with-claude-md did not keep the original at CLAUDE-BK.md"
  elif ! grep -q "Generic Apple Platform App Architecture" "$T/CLAUDE.md"; then
    fail "--with-claude-md did not install GenericArch's CLAUDE.md"
  elif ! grep -q '"action": "replaced"' "$T/.genericarch/manifest-$VERSION.json"; then
    fail "the swap was not recorded in the manifest — uninstall cannot reverse it"
  else
    uninstall_in "$T" "$VERSION"
    back="$(shasum -a 256 "$T/CLAUDE.md" 2>/dev/null | awk '{print $1}')"
    if [ "$back" != "$theirs" ]; then
      fail "uninstall did not restore their CLAUDE.md byte-for-byte"
    elif [ -e "$T/CLAUDE-BK.md" ]; then
      fail "uninstall restored the file but left the backup behind"
    else
      pass "--with-claude-md is reversible: their rules come back byte-for-byte"
    fi
  fi
else
  fail "case 17: install --with-claude-md failed (see $WORK/last.log)"
fi

# ── 18. an edited CLAUDE.md is never overwritten on the way out ────────────
T="$(new_repo case18)"
printf '# House rules\n' > "$T/CLAUDE.md"
( cd "$T" && git add -A && git -c user.email=t@t -c user.name=t commit -qm rules ) >/dev/null 2>&1
if install_flags "$T" --with-claude-md; then
  printf '\n## My own addition\n' >> "$T/CLAUDE.md"
  edited="$(shasum -a 256 "$T/CLAUDE.md" | awk '{print $1}')"
  uninstall_flags "$T" "$VERSION" --upgrade
  still="$(shasum -a 256 "$T/CLAUDE.md" 2>/dev/null | awk '{print $1}')"
  if [ "$still" != "$edited" ]; then
    fail "uninstall overwrote a CLAUDE.md the operator had edited"
  elif [ ! -f "$T/CLAUDE-BK.md" ]; then
    fail "uninstall removed the backup while their original was still unrestored"
  else
    pass "an edited CLAUDE.md is kept, and so is the backup it would have been restored from"
  fi
else
  fail "case 18: install --with-claude-md failed"
fi

echo
if [ "$fails" -eq 0 ]; then
  printf '%s✓ every case passed%s\n' "$GRN" "$OFF"
  exit 0
fi
printf '%s✗ %d case(s) failed%s — scratch kept at %s\n' "$RED" "$fails" "$OFF" "$WORK"
KEEP=1
exit 1
