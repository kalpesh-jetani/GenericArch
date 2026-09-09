#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Enforce the CLAUDE.md section 2 rules a linter cannot express, plus the project's own iOS floor and doc currency.
#@usage     check.sh
#@in        none
#@out       stdout:pass/fail report per rule
#@exit      0=clean 1=violations
#@effects   read-only, BUT COMPILES at the project's iOS floor — slow. Validating a change is what it is for (CLAUDE.md 2.12); running or testing the app still needs consent
# Enforces the CLAUDE.md §2 rules a linter can't express, plus the iOS floor this repo states and doc currency.
# Run before a PR; run in CI as a required check (docs/DELIVERY.md).
#
#   ./Scripts/check.sh
#
# Portable to bash 3.2 (macOS system bash) — no mapfile, no associative arrays.
set -o pipefail
cd "$(dirname "$0")/.."

RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; DIM=$'\033[2m'; OFF=$'\033[0m'
fails=0; warns=0
GREPOPTS=(-rnE --include='*.swift' --exclude-dir=.build --exclude-dir=Tests)

# ── The OpenSpec projection ────────────────────────────────────────────────
# Runs BEFORE the no-Swift exit below, on purpose: the projection is built from CLAUDE.md and
# docs/DECISIONS.md, so it can drift in a repo that has no Swift in it at all.
#
# It is here rather than in a habit the user has to remember. Editing a §2 rule silently staled the
# span that carries those rules into OpenSpec, and nothing said so — so this is the one gate that
# already runs before a PR (docs/DELIVERY.md) picking that up for free.
#
# A warning, never a failure: a stale projection is a one-command fix and has no business blocking
# an unrelated Swift change. Exit 7 is "this repo has no OpenSpec config", which is not a finding.
if [ -x Scripts/openspec-sync.sh ]; then
  Scripts/openspec-sync.sh --check --tsv >/dev/null 2>&1
  case $? in
    0|7) : ;;
    *)   printf '%s⚠ the OpenSpec projection is stale%s\n' "$YEL" "$OFF"
         printf '  %srun /openspec-install (or ./Scripts/openspec-sync.sh --check to see the drift)%s\n' \
           "$DIM" "$OFF"
         warns=$((warns + 1)) ;;
  esac
fi

ROOTS=()
[ -d Packages ] && ROOTS+=(Packages)
[ -d App ] && ROOTS+=(App)

if [ ${#ROOTS[@]} -eq 0 ]; then
  echo "no Swift sources yet — nothing to check"; exit 0
fi

# report <severity> <rule> <fix-hint> <regex> [extra-grep-args...]
report() {
  sev="$1"; rule="$2"; hint="$3"; rx="$4"; shift 4
  hits=$(grep "${GREPOPTS[@]}" "$@" -- "$rx" "${ROOTS[@]}" 2>/dev/null)
  [ -z "$hits" ] && return 0
  if [ "$sev" = error ]; then
    printf '%s✗ %s%s\n' "$RED" "$rule" "$OFF"; fails=$((fails + 1))
  else
    printf '%s⚠ %s%s\n' "$YEL" "$rule" "$OFF"; warns=$((warns + 1))
  fi
  printf '  %s%s%s\n' "$DIM" "$hint" "$OFF"
  printf '%s\n' "$hits" | sed 's/^/    /' | head -8
}

echo "── Swift rules ────────────────────────────────────────────"
report error "§2.4 system alert"     "Route through the single message presenter (CLAUDE.md §2.4)." '\.(alert|confirmationDialog|actionSheet)[[:space:]]*\('
report error "§2.7 fatalError"       "Return a mapped AppError; assertions vanish in release."      '\bfatalError[[:space:]]*\('
report error "§1 Combine"            "Use async/await and AsyncSequence."                           '^import Combine'
report error "§1 DispatchQueue"      "Use @MainActor or structured concurrency."                    'DispatchQueue\.(main|global)'
report error "§8 fixed font size"    "Font.custom needs relativeTo: or Dynamic Type breaks."        'Font\.custom\([^)]*size:[[:space:]]*[0-9]+[[:space:]]*\)'
report warn  "§2.7 swallowed try?"   "Handle or map it, or comment why discarding is correct."       'try\?[[:space:]]'
report warn  "RTL left/right"        "Use leading/trailing and chevron.forward (skill: rtl-support)." '\.(left|right)\b|chevron\.(left|right)'

echo "── Feature-scoped ─────────────────────────────────────────"
if [ -d Packages/Features ]; then
  featreport() {
    rule="$1"; hint="$2"; rx="$3"
    hits=$(grep -rnE --include='*.swift' --exclude-dir=.build --exclude-dir=Tests -- "$rx" Packages/Features 2>/dev/null \
           | grep -v '/DI/.*Assembly\.swift')
    [ -z "$hits" ] && return 0
    printf '%s✗ %s%s\n  %s%s%s\n' "$RED" "$rule" "$OFF" "$DIM" "$hint" "$OFF"; fails=$((fails + 1))
    printf '%s\n' "$hits" | sed 's/^/    /' | head -8
  }
  featreport "§2.10 build flag in feature" "Use the injected AppEnvironment (notes/SCHEMES.md)." '#if[[:space:]]+(DEBUG|TEST|BETA)'
  featreport "§1.1 os() in feature"        "Gate inside a DesignSystem component."              '#if[[:space:]]+os\('
  featreport "§2.6 resolve in feature"     "Take the protocol through init; only Assembly sees the container." '\bDIContainer\b|\bresolve[[:space:]]*\('
  featreport "§2.6 ambient singleton"      "Inject by protocol."                                '\.shared\b'
  featreport "§2.1 sibling feature import" "Features never import each other."                  '^import Feature'
  featreport "design literal in feature"   "Use a DesignSystem token."                          'Color\([[:space:]]*(red|white|hex):'
else
  printf '  %sno Packages/Features yet%s\n' "$DIM" "$OFF"
fi

# The floor is whatever THIS repo states, read through detect-toolchain.sh so this gate and every
# other reader agree. It used to be the literal ios17.0 below, which validated each consuming repo
# against a number it may never have chosen: a project whose floor is 18 was typechecked at 17 and
# failed on APIs its own floor permits, and one still on 16 was typechecked at 17 and passed code
# its floor forbids. Only a `project` row counts — a `machine` row is an installed SDK, which is a
# ceiling, not a deployment decision.
FLOOR_IOS=""
if [ -x Scripts/detect-toolchain.sh ]; then
  FLOOR_IOS=$(NO_COLOR=1 ./Scripts/detect-toolchain.sh --markdown 2>/dev/null \
    | awk -F'|' '/Minimum iOS/ && $4 ~ /project/ {gsub(/[^0-9.]/,"",$3); print $3; exit}')
fi

echo "── iOS ${FLOOR_IOS:-?} floor (§1.1) ────────────────────────────────────"
# `swift build` on a Mac compiles only the macOS slice, so a macOS-26-only API in shared code
# passes it silently and only fails later in the app build. Typecheck against the iOS SDK here.
#
# LIMITATION: this is a bare `swiftc -typecheck` with no module search paths, so a package that
# imports a sibling reports "no such module" instead of the availability error. It therefore fully
# validates dependency-free packages (Core) and only partially validates the rest. The complete
# check is the app's iOS build in CI (docs/DELIVERY.md) — this catches the common case early.
IOS_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)
if [ -z "$IOS_SDK" ]; then
  printf '%s⚠ no iOS simulator SDK — floor NOT checked%s\n' "$YEL" "$OFF"; warns=$((warns + 1))
elif [ -z "$FLOOR_IOS" ]; then
  # §0: a floor is never defaulted. Picking one here would report a pass against a number nobody
  # chose, which is worse than saying the check could not run.
  printf '%s⚠ this repo states no iOS floor — floor NOT checked%s\n' "$YEL" "$OFF"
  printf '  %sSet IPHONEOS_DEPLOYMENT_TARGET in an .xcconfig, or platforms: in Package.swift.%s\n' "$DIM" "$OFF"
  warns=$((warns + 1))
else
  checked=0
  for pkg in Packages/*/ Packages/Features/*/; do
    [ -f "${pkg}Package.swift" ] || continue
    name=$(basename "$pkg")
    OLDIFS="$IFS"; IFS=$'\n'
    srcs=$(find "${pkg}Sources" -name '*.swift' 2>/dev/null)
    IFS="$OLDIFS"
    [ -z "$srcs" ] && continue
    checked=$((checked + 1))
    OLDIFS="$IFS"; IFS=$'\n'
    out=$(xcrun swiftc -sdk "$IOS_SDK" -target "arm64-apple-ios$FLOOR_IOS-simulator" \
            -swift-version 6 -typecheck $srcs 2>&1 | grep -E 'only available in iOS|error:' | head -5)
    IFS="$OLDIFS"
    if [ -n "$out" ]; then
      printf '%s✗ %s does not compile at the iOS %s floor%s\n' "$RED" "$name" "$FLOOR_IOS" "$OFF"
      printf '  %sGate with #if os(macOS) or if #available, inside DesignSystem (§1.1).%s\n' "$DIM" "$OFF"
      printf '%s\n' "$out" | sed 's/^/    /'; fails=$((fails + 1))
    fi
  done
  printf '  %s%d package(s) typechecked at iOS %s%s\n' "$DIM" "$checked" "$FLOOR_IOS" "$OFF"
fi

echo "── Toolchain (§1) ─────────────────────────────────────────"
# §1 must describe this machine. A baseline nobody can build with is worse than none, and a
# deployment target above the SDK only fails at archive time otherwise.
if [ -x Scripts/detect-toolchain.sh ]; then
  tc=$(./Scripts/detect-toolchain.sh 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^(✗|⚠)')
  if [ -n "$tc" ]; then
    printf '%s\n' "$tc" | while IFS= read -r l; do
      case "$l" in
        ✗*) printf '  %s%s%s\n' "$RED" "$l" "$OFF" ;;
        *)  printf '  %s%s%s\n' "$YEL" "$l" "$OFF" ;;
      esac
    done
    printf '%s\n' "$tc" | grep -q '^✗' && fails=$((fails + 1)) || warns=$((warns + 1))
    printf '  %srun /upgrade-stack — it asks twice before changing anything%s\n' "$DIM" "$OFF"
  else
    printf '  %stoolchain matches §1%s\n' "$DIM" "$OFF"
  fi
fi

echo "── Note paths resolve ─────────────────────────────────────"
# FEATURES.md and NAVIGATION.md are indexes — someone greps a screen there and expects the file.
# A path that no longer exists sends them somewhere confidently wrong, so it is an error, not a nit.
# Commented-out example rows are skipped: they document the format before any real code exists.
for note in .claude/notes/FEATURES.md .claude/notes/NAVIGATION.md; do
  [ -f "$note" ] || continue
  missing=$(python3 - "$note" <<'PY'
import re, sys, pathlib
text = pathlib.Path(sys.argv[1]).read_text()
text = re.sub(r'<!--.*?-->', '', text, flags=re.S)          # drop illustrative examples
paths = set(re.findall(r'\b((?:Packages|App|docs|Scripts)/[\w./-]*\.\w+)', text))
print('\n'.join(sorted(p for p in paths if not pathlib.Path(p.split(':')[0]).exists())))
PY
)
  if [ -n "$missing" ]; then
    printf '%s✗ %s references files that do not exist%s\n' "$RED" "$note" "$OFF"
    printf '  %sFix the row or move it to Gaps — a wrong path is worse than a missing one.%s\n' "$DIM" "$OFF"
    printf '%s\n' "$missing" | sed 's/^/    /'; fails=$((fails + 1))
  fi
done
printf '  %sindex paths verified%s\n' "$DIM" "$OFF"

echo "── Doc comments ───────────────────────────────────────────"
# Every function and initialiser carries a /// stating what the signature cannot
# (docs/CONVENTIONS.md). SwiftLint's missing_docs only covers public/open; this covers all of them.
# A @Test case whose string already describes it is exempt — a /// there would only duplicate.
undoc=$(python3 - <<'PY'
import re, pathlib
DECL = re.compile(r'^\s*(?:@\w+\s+)*(?:public |private |internal |fileprivate |package |static |mutating |open |final )*(?:func|init)\b')
out = []
for f in sorted(pathlib.Path('.').rglob('*.swift')):
    sp = str(f)
    if '.build' in sp or not (sp.startswith('Packages') or sp.startswith('App')):
        continue
    lines = f.read_text().splitlines()
    for i, line in enumerate(lines):
        if not DECL.match(line):
            continue
        prev = lines[i - 1].strip() if i else ''
        if prev.startswith('///') or prev.startswith('@Test('):
            continue
        out.append(f"{f}:{i+1}  {line.strip()[:70]}")
print('\n'.join(out))
PY
)
if [ -n "$undoc" ]; then
  printf '%s✗ declarations with no /// doc comment%s\n' "$RED" "$OFF"
  printf '  %sState the contract: thrown errors, cancellation, why a parameter matters.%s\n' "$DIM" "$OFF"
  printf '%s\n' "$undoc" | sed 's/^/    /' | head -10
  fails=$((fails + 1))
else
  printf '  %severy function and initialiser is documented%s\n' "$DIM" "$OFF"
fi

echo "── Docs & keys ────────────────────────────────────────────"
for pkg in Packages/*/ Packages/Features/*/; do
  [ -f "${pkg}Package.swift" ] || continue
  name=$(basename "$pkg")
  # §2.16: every component carries its own CLAUDE.md — the rules that bind only inside it, loaded
  # only when a session touches it. The reference doc beside it is optional (STRUCTURE.md).
  if [ ! -f "${pkg}CLAUDE.md" ]; then
    printf '%s⚠ %s has no CLAUDE.md — expected %sCLAUDE.md (§2.16)%s\n' "$YEL" "$name" "$pkg" "$OFF"
    warns=$((warns + 1))
  fi
done

# Every DependencyKey must supply testValue — this is what makes "no network in unit tests" real.
OLDIFS="$IFS"; IFS=$'\n'
for f in $(grep -rlE ':[[:space:]]*DependencyKey' --include='*.swift' --exclude-dir=.build "${ROOTS[@]}" 2>/dev/null); do
  grep -q 'testValue' "$f" || {
    printf '%s✗ %s declares a DependencyKey with no testValue%s\n' "$RED" "$f" "$OFF"; fails=$((fails + 1)); }
done
IFS="$OLDIFS"

echo "───────────────────────────────────────────────────────────"
if [ "$fails" -gt 0 ]; then
  printf '%s%d rule(s) failed%s, %d warning(s)\n' "$RED" "$fails" "$OFF" "$warns"; exit 1
fi
printf '%sall rules pass%s, %d warning(s)\n' "$GRN" "$OFF" "$warns"
