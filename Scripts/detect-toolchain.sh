#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Resolve the actual stack: min iOS/macOS, Xcode, Swift, language mode. Never quote these from memory.
#@usage     detect-toolchain.sh [--markdown|--options|--mismatches] [--root DIR]
#@in        --markdown:flag(emit PROJECT.md rows) --options:flag(machine-derived choice lists for /project-init) --mismatches:flag(one SEVERITY|id|what|current|available|remediation row per finding, severity BLOCKING|OPPORTUNITY|DRIFT) --root:dir(repo whose manifests answer the project half; default this checkout — cd-ing before the call does NOT work)
#@out       stdout:resolved stack values
#@exit      0=ok — always, including when --mismatches reports BLOCKING. Callers gate on the BLOCKING rows, never on status
#@effects   read-only
#@when      what is the stack|min ios version|which xcode|swift version|toolchain
# Determine the tech stack this repo actually uses — never assume one.
#
#   ./Scripts/detect-toolchain.sh              # full report
#   ./Scripts/detect-toolchain.sh --markdown   # PROJECT.md 'Resolved stack', ready to paste
#   ./Scripts/detect-toolchain.sh --options    # choice lists for /project-init, machine-derived
#
# Precedence, deliberately:
#   1. THE PROJECT wins. An existing repo's settings are the shipped contract — a machine upgrade
#      must not silently change what the app supports, or what framework it is written in.
#   2. THE MACHINE fills the gaps. It supplies versions, available SDKs, and the set of valid
#      choices, because it is what will compile the thing.
#   3. Anything neither can answer is ASKED, with the machine's options and the latest recommended.
#
# Nothing here is hardcoded to SwiftUI/SPM/Swift 6. Those are this repo's *resolved* answers, not
# the tool's assumptions.
set -o pipefail

RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; DIM=$'\033[2m'; BLD=$'\033[1m'; OFF=$'\033[0m'
MODE=report
# The repo whose manifests answer the "project" half. Defaults to this checkout, because that is the
# common case — but a caller installing or scaffolding INTO another repo must be able to ask about
# THAT repo. Changing directory before the call does not do it: the cd below is unconditional, so
# every such caller silently read this checkout's floors and reported them as the target's.
ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --markdown)   MODE=markdown; shift ;;
    --options)    MODE=options; shift ;;
    --mismatches) MODE=mismatches; shift ;;
    --root)       ROOT="${2:-}"; shift 2 || true ;;
    *)            shift ;;
  esac
done
if [ -n "$ROOT" ]; then
  [ -d "$ROOT" ] || { echo "no such directory: $ROOT" >&2; exit 2; }
  cd "$ROOT" || exit 2
else
  cd "$(dirname "$0")/.."
fi

# ── Machine ────────────────────────────────────────────────────────────────
SWIFT=$(swift --version 2>/dev/null | sed -n 's/.*Apple Swift version \([0-9.]*\).*/\1/p' | head -1)
XCODE=$(xcodebuild -version 2>/dev/null | sed -n 's/^Xcode \([0-9.]*\)/\1/p' | head -1)
XCODE_PATH=$(xcode-select -p 2>/dev/null)
HOST_OS=$(sw_vers -productVersion 2>/dev/null)
MACOS_SDK=$(xcrun --sdk macosx --show-sdk-version 2>/dev/null)
IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null)
: "${SWIFT:=not found}" "${XCODE:=not found}"

# Every Xcode present, not just the selected one — a team often has several.
XCODES=$(ls -d /Applications/Xcode*.app 2>/dev/null | while read -r a; do
  v=$(defaults read "$a/Contents/Info" CFBundleShortVersionString 2>/dev/null)
  [ -n "$v" ] && echo "$v ($a)"
done | sort -u)

# Language modes this compiler will actually accept — probed, not assumed.
LANG_MODES=""
echo 'let _x = 1' > "${TMPDIR:-/tmp}/_lm.swift"
for v in 5 6; do
  xcrun swiftc -swift-version "$v" -typecheck "${TMPDIR:-/tmp}/_lm.swift" 2>/dev/null \
    && LANG_MODES="$LANG_MODES $v"
done
rm -f "${TMPDIR:-/tmp}/_lm.swift"
LANG_MODES="${LANG_MODES# }"
LATEST_MODE=$(echo "$LANG_MODES" | tr ' ' '\n' | sort -V | tail -1)

PLATFORMS=$(xcodebuild -showsdks 2>/dev/null \
  | sed -nE 's/^[[:space:]]*(iOS|macOS|watchOS|tvOS|visionOS) ([0-9.]+).*/\1 \2/p' \
  | sort -u)

# ── Project (authoritative where present) ──────────────────────────────────
det() { # det <label> <value-if-found>
  [ -n "$2" ] && echo "$2" || echo ""
}
SRC_GLOB="Packages App Sources . "

has() { grep -rqE "$1" --include='*.swift' --exclude-dir=.build Packages App Sources 2>/dev/null; }
count() { grep -rlE "$1" --include='*.swift' --exclude-dir=.build Packages App Sources 2>/dev/null | wc -l | tr -d ' '; }

UI=""; N_SWIFTUI=$(count '^import SwiftUI'); N_UIKIT=$(count '^import (UIKit|AppKit)')
IB=$(find . \( -name '*.storyboard' -o -name '*.xib' \) -not -path '*/.build/*' 2>/dev/null | wc -l | tr -d ' ')
if [ "$N_SWIFTUI" -gt 0 ] && [ "$N_UIKIT" -gt 0 ]; then UI="SwiftUI + UIKit/AppKit (mixed)"
elif [ "$N_SWIFTUI" -gt 0 ]; then UI="SwiftUI"
elif [ "$N_UIKIT" -gt 0 ]; then UI="UIKit/AppKit"
fi
[ "$IB" -gt 0 ] && UI="${UI:-UIKit/AppKit} + $IB storyboard/xib"

DEPS=""
[ -n "$(ls Packages/*/Package.swift Package.swift 2>/dev/null)" ] && DEPS="SPM"
[ -f Podfile ] && DEPS="${DEPS:+$DEPS + }CocoaPods"
[ -f Cartfile ] && DEPS="${DEPS:+$DEPS + }Carthage"
[ -n "$(find . -name '*.xcframework' -not -path '*/.build/*' 2>/dev/null | head -1)" ] && DEPS="${DEPS:+$DEPS + }vendored xcframework"

GEN=""
[ -f Project.swift ] && GEN="Tuist"
[ -f project.yml ] && GEN="${GEN:+$GEN + }XcodeGen"
[ -z "$GEN" ] && [ -n "$(ls -d *.xcodeproj 2>/dev/null)" ] && GEN="checked-in .xcodeproj"
[ -z "$GEN" ] && GEN="SPM only"

CONC=""
if grep -rq 'swiftLanguageMode(.v6)\|swift-version 6\|StrictConcurrency' Packages/*/Package.swift Package.swift 2>/dev/null; then
  CONC="Swift 6 language mode"
fi
has '^import Combine' && CONC="${CONC:+$CONC + }Combine"
has '\(.*@escaping.*\) -> Void' && CONC="${CONC:+$CONC + }completion handlers"

TESTS=""
has '^import Testing' && TESTS="Swift Testing"
has '^import XCTest' && TESTS="${TESTS:+$TESTS + }XCTest"

# Deployment targets: .xcconfig beats Package.swift; both beat nothing.
SRC_IOS=""; SRC_MACOS=""; ORIGIN=""
PKG=$(ls Packages/*/Package.swift Package.swift 2>/dev/null | head -1)
if [ -n "$PKG" ]; then
  line=$(grep -h 'platforms:' "$PKG" 2>/dev/null | head -1)
  SRC_IOS=$(printf '%s' "$line" | sed -n 's/.*\.iOS(\.v\([0-9_]*\)).*/\1/p' | tr '_' '.')
  [ -z "$SRC_IOS" ] && SRC_IOS=$(printf '%s' "$line" | sed -n 's/.*\.iOS("\([0-9.]*\)").*/\1/p')
  SRC_MACOS=$(printf '%s' "$line" | sed -n 's/.*\.macOS("\([0-9.]*\)").*/\1/p')
  [ -z "$SRC_MACOS" ] && SRC_MACOS=$(printf '%s' "$line" | sed -n 's/.*\.macOS(\.v\([0-9_]*\)).*/\1/p' | tr '_' '.')
  [ -n "$SRC_IOS$SRC_MACOS" ] && ORIGIN="$PKG"
fi
if ls Configurations/*.xcconfig *.xcconfig >/dev/null 2>&1; then
  xi=$(grep -h 'IPHONEOS_DEPLOYMENT_TARGET' Configurations/*.xcconfig *.xcconfig 2>/dev/null | head -1 | sed 's/.*=[[:space:]]*//')
  xm=$(grep -h 'MACOSX_DEPLOYMENT_TARGET' Configurations/*.xcconfig *.xcconfig 2>/dev/null | head -1 | sed 's/.*=[[:space:]]*//')
  [ -n "$xi" ] && { SRC_IOS="$xi"; ORIGIN="an .xcconfig"; }
  [ -n "$xm" ] && { SRC_MACOS="$xm"; ORIGIN="an .xcconfig"; }
fi
FRESH=0
if [ -z "$ORIGIN" ]; then
  FRESH=1; ORIGIN="none — fresh repo, machine sets the baseline"
  SRC_IOS="${SRC_IOS:-$IOS_SDK}"; SRC_MACOS="${SRC_MACOS:-$MACOS_SDK}"
fi

# ── --options : machine-derived choices for /project-init ──────────────────
if [ "$MODE" = options ]; then
  echo "# Machine-derived stack options. Latest is recommended; nothing here is a default."
  echo
  echo "swift_language_mode: $LANG_MODES   (recommend: $LATEST_MODE)"
  echo "xcode:"; printf '%s\n' "$XCODES" | sed 's/^/  - /'
  echo "platforms_available:"; printf '%s\n' "$PLATFORMS" | sed 's/^/  - /'
  echo "ui_framework: SwiftUI | UIKit/AppKit | mixed        (recommend: SwiftUI)"
  echo "dependencies: SPM | CocoaPods | Carthage            (recommend: SPM)"
  echo "project_files: SPM only | Tuist | XcodeGen | .xcodeproj   (recommend: SPM only)"
  echo "concurrency: async/await strict | async/await minimal | Combine | completion handlers   (recommend: async/await strict)"
  echo "testing: Swift Testing | XCTest | both              (recommend: Swift Testing, XCTest for UI)"
  [ "$FRESH" -eq 0 ] && echo && echo "# NOTE: this project already answers some of these — see --report. Do not re-ask those."
  exit 0
fi

# ── --mismatches : classified, machine-readable ────────────────────────────
# Format: SEVERITY|id|what|current|available|remediation
#   BLOCKING    cannot build as configured — must be resolved
#   OPPORTUNITY builds fine; a newer option exists. Adopting it is a CHOICE, sometimes a
#               product decision that drops users. Never applied without asking.
#   DRIFT       docs disagree with reality — doc-only fix
if [ "$MODE" = mismatches ]; then
  vlt() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ] && [ "$1" != "$2" ]; }

  [ -n "$MACOS_SDK" ] && [ -n "$SRC_MACOS" ] && vlt "$MACOS_SDK" "$SRC_MACOS" && \
    echo "BLOCKING|macos-target-above-sdk|min macOS exceeds the installed SDK|$SRC_MACOS|SDK $MACOS_SDK|lower the target to $MACOS_SDK, or install an Xcode whose SDK is >= $SRC_MACOS"
  [ -n "$IOS_SDK" ] && [ -n "$SRC_IOS" ] && vlt "$IOS_SDK" "$SRC_IOS" && \
    echo "BLOCKING|ios-target-above-sdk|min iOS exceeds the installed SDK|$SRC_IOS|SDK $IOS_SDK|lower the target to $IOS_SDK, or install a newer Xcode"

  # Language mode below the newest the compiler accepts.
  PROJ_MODE=""
  grep -rq 'swiftLanguageMode(.v6)\|swift-version 6' Packages/*/Package.swift Package.swift 2>/dev/null && PROJ_MODE=6
  grep -rq 'swiftLanguageMode(.v5)\|swift-version 5' Packages/*/Package.swift Package.swift 2>/dev/null && PROJ_MODE=5
  [ -n "$PROJ_MODE" ] && [ -n "$LATEST_MODE" ] && vlt "$PROJ_MODE" "$LATEST_MODE" && \
    echo "OPPORTUNITY|swift-language-mode|Swift language mode is behind the compiler|$PROJ_MODE|$LATEST_MODE|migrate to mode $LATEST_MODE — expect new concurrency diagnostics; do it package by package"

  # The recorded stack disagreeing with the machine is a doc problem, not a build problem.
  if [ -f .claude/notes/PROJECT.md ]; then
    c=$(grep -E '^\| Xcode / Swift \|' .claude/notes/PROJECT.md | head -1)
    [ -n "$c" ] && ! printf '%s' "$c" | grep -q "\*\*$XCODE\*\*" && \
      echo "DRIFT|recorded-toolchain|PROJECT.md 'Resolved stack' disagrees with the machine|see PROJECT.md|Xcode $XCODE / Swift $SWIFT|refresh it from --markdown"
  fi

  for pair in "UI:$UI" "dependencies:$DEPS" "concurrency:$CONC" "testing:$TESTS"; do
    k="${pair%%:*}"; v="${pair#*:}"
    [ -z "$v" ] && echo "DRIFT|unresolved-$k|$k is not answered by the project|(none)|see --options|ask at init and record with /decide"
  done
  exit 0
fi

# ── --markdown : the 'Resolved stack' table ────────────────────────────────
if [ "$MODE" = markdown ]; then
  # The detected rows — paste over PROJECT.md "Resolved stack".
  cat <<MDOUT
| Item | Value | Source |
|---|---|---|
| Minimum iOS / iPadOS | **$SRC_IOS** | $([ "$FRESH" -eq 1 ] && echo "machine" || echo "project") |
| Minimum macOS | **$SRC_MACOS** | $([ "$FRESH" -eq 1 ] && echo "machine" || echo "project") |
| Xcode / Swift | **$XCODE** / **$SWIFT** | machine |
| Swift language mode | **$LATEST_MODE** (available: $LANG_MODES) | machine |
MDOUT
  # The chosen constraints are CLAUDE.md §1 rules, not data — a divergence is a
  # violation to raise, not a table to refresh. Reported, never pasted.
  echo
  echo "# CLAUDE.md §1 chosen constraints, as the project actually reads:"
  for pair in "UI:${UI:-unresolved}" "Dependencies:${DEPS:-unresolved}" \
              "Project files:${GEN:-unresolved}" "Concurrency:${CONC:-unresolved}" \
              "Testing:${TESTS:-unresolved}"; do
    echo "#   ${pair%%:*}: ${pair#*:}"
  done
  exit 0
fi

# ── Report ─────────────────────────────────────────────────────────────────
echo
echo "${BLD}Stack — what this repo actually uses${OFF}"
echo
echo "${BLD}machine${OFF}"
printf '  %-24s %s\n' "Swift"            "$SWIFT"
printf '  %-24s %s\n' "Xcode (selected)" "$XCODE  ${DIM}$XCODE_PATH${OFF}"
[ "$(printf '%s\n' "$XCODES" | grep -c .)" -gt 1 ] && printf '  %-24s %s\n' "Xcode (all)" "$(printf '%s' "$XCODES" | tr '\n' ' ')"
printf '  %-24s %s\n' "language modes"   "$LANG_MODES  ${DIM}(latest: $LATEST_MODE)${OFF}"
printf '  %-24s %s\n' "host macOS"       "${HOST_OS:-?}"
printf '  %-24s\n'    "SDKs"
printf '%s\n' "$PLATFORMS" | sed "s/^/    /"
echo
echo "${BLD}project${OFF}  ${DIM}(blank = not answered here; /project-init asks)${OFF}"
printf '  %-24s %s\n' "UI"             "${UI:-${YEL}unresolved${OFF}}"
printf '  %-24s %s\n' "dependencies"   "${DEPS:-${YEL}unresolved${OFF}}"
printf '  %-24s %s\n' "project files"  "${GEN:-${YEL}unresolved${OFF}}"
printf '  %-24s %s\n' "concurrency"    "${CONC:-${YEL}unresolved${OFF}}"
printf '  %-24s %s\n' "testing"        "${TESTS:-${YEL}unresolved${OFF}}"
printf '  %-24s %s\n' "min iOS"        "$SRC_IOS"
printf '  %-24s %s\n' "min macOS"      "$SRC_MACOS"
printf '  %-24s %s%s%s\n' "read from"   "$DIM" "$ORIGIN" "$OFF"
echo

warn=0
verlt() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ] && [ "$1" != "$2" ]; }

if [ -n "$MACOS_SDK" ] && [ -n "$SRC_MACOS" ] && verlt "$MACOS_SDK" "$SRC_MACOS"; then
  echo "${RED}✗ min macOS $SRC_MACOS is ABOVE the installed macOS SDK $MACOS_SDK${OFF}"
  echo "  ${DIM}An app target will refuse this. Install a newer Xcode or lower the target.${OFF}"
  warn=$((warn + 1))
fi
if [ -n "$IOS_SDK" ] && [ -n "$SRC_IOS" ] && verlt "$IOS_SDK" "$SRC_IOS"; then
  echo "${RED}✗ min iOS $SRC_IOS is above the installed iOS SDK $IOS_SDK${OFF}"; warn=$((warn + 1))
fi

if [ -f .claude/notes/PROJECT.md ]; then
  claimed=$(grep -E '^\| Xcode / Swift \|' .claude/notes/PROJECT.md | head -1)
  if [ -n "$claimed" ] && ! printf '%s' "$claimed" | grep -q "\*\*$XCODE\*\*"; then
    echo "${YEL}⚠ PROJECT.md 'Resolved stack' disagrees with this machine${OFF}"
    echo "  ${DIM}found: Xcode $XCODE / Swift $SWIFT — refresh with --markdown${OFF}"
    warn=$((warn + 1))
  fi
fi

unresolved=0
for v in "$UI" "$DEPS" "$CONC" "$TESTS"; do [ -z "$v" ] && unresolved=$((unresolved + 1)); done
if [ "$unresolved" -gt 0 ]; then
  echo "${YEL}⚠ $unresolved stack choice(s) unresolved${OFF}"
  echo "  ${DIM}Run /project-init — it asks with these options: ./Scripts/detect-toolchain.sh --options${OFF}"
fi

if [ "$warn" -gt 0 ]; then
  echo
  echo "${BLD}Run /upgrade-stack${OFF} to review and act on these."
  echo "  ${DIM}It asks twice before changing anything: once for what to address, once for the exact edits.${OFF}"
fi
[ "$warn" -eq 0 ] && [ "$unresolved" -eq 0 ] && echo "${GRN}stack fully resolved and consistent${OFF}"
echo
exit 0
