#!/usr/bin/env bash
# Report the toolchain this repo will actually build with, and emit a CLAUDE.md §1 block for it.
#
#   ./Scripts/detect-toolchain.sh              # human-readable report
#   ./Scripts/detect-toolchain.sh --markdown   # just the §1 table, ready to paste
#
# Precedence, deliberately: a PROJECT FILE beats the MACHINE.
#   • Deployment targets come from Package.swift / *.xcconfig when they exist — those are the
#     shipped contract, and a machine upgrade must not silently change what the app supports.
#   • Toolchain versions come from the machine, because that is what will compile it.
# A fresh repo has no project file, so the machine defines both. That is the only case where
# installed versions get to set the baseline.
set -o pipefail
cd "$(dirname "$0")/.."

RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; DIM=$'\033[2m'; BLD=$'\033[1m'; OFF=$'\033[0m'
MD=0; [ "${1:-}" = "--markdown" ] && MD=1

# ── Machine ────────────────────────────────────────────────────────────────
SWIFT=$(swift --version 2>/dev/null | sed -n 's/.*Apple Swift version \([0-9.]*\).*/\1/p' | head -1)
XCODE=$(xcodebuild -version 2>/dev/null | sed -n 's/^Xcode \([0-9.]*\)/\1/p' | head -1)
MACOS_SDK=$(xcrun --sdk macosx --show-sdk-version 2>/dev/null)
IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null)
HOST_OS=$(sw_vers -productVersion 2>/dev/null)
[ -z "$SWIFT" ] && SWIFT="not found"
[ -z "$XCODE" ] && XCODE="not found"

# ── Project files (authoritative for deployment targets) ───────────────────
SRC_IOS=""; SRC_MACOS=""; ORIGIN=""

# 1. Package.swift platforms — the strongest signal in an SPM repo.
PKG=$(ls Packages/*/Package.swift Package.swift 2>/dev/null | head -1)
if [ -n "$PKG" ]; then
  line=$(grep -h 'platforms:' "$PKG" 2>/dev/null | head -1)
  SRC_IOS=$(printf '%s' "$line" | sed -n 's/.*\.iOS(\.v\([0-9_]*\)).*/\1/p' | tr '_' '.')
  [ -z "$SRC_IOS" ] && SRC_IOS=$(printf '%s' "$line" | sed -n 's/.*\.iOS("\([0-9.]*\)").*/\1/p')
  SRC_MACOS=$(printf '%s' "$line" | sed -n 's/.*\.macOS("\([0-9.]*\)").*/\1/p')
  [ -z "$SRC_MACOS" ] && SRC_MACOS=$(printf '%s' "$line" | sed -n 's/.*\.macOS(\.v\([0-9_]*\)).*/\1/p' | tr '_' '.')
  [ -n "$SRC_IOS$SRC_MACOS" ] && ORIGIN="$PKG"
fi

# 2. .xcconfig deployment targets — win over Package.swift for the app itself.
XC=$(ls Configurations/*.xcconfig *.xcconfig 2>/dev/null | head -1)
if [ -n "$XC" ]; then
  xi=$(grep -h 'IPHONEOS_DEPLOYMENT_TARGET' Configurations/*.xcconfig *.xcconfig 2>/dev/null | head -1 | sed 's/.*=[[:space:]]*//')
  xm=$(grep -h 'MACOSX_DEPLOYMENT_TARGET' Configurations/*.xcconfig *.xcconfig 2>/dev/null | head -1 | sed 's/.*=[[:space:]]*//')
  [ -n "$xi" ] && { SRC_IOS="$xi"; ORIGIN="$XC"; }
  [ -n "$xm" ] && { SRC_MACOS="$xm"; ORIGIN="$XC"; }
fi

if [ -z "$ORIGIN" ]; then
  ORIGIN="none — fresh repo, machine defines the baseline"
  SRC_IOS="${SRC_IOS:-17.0}"
  SRC_MACOS="${SRC_MACOS:-$MACOS_SDK}"
fi

# ── Markdown output ────────────────────────────────────────────────────────
if [ "$MD" -eq 1 ]; then
  cat <<MDOUT
| Item | Value |
|---|---|
| Minimum iOS / iPadOS | **$SRC_IOS** |
| Minimum macOS | **$SRC_MACOS** |
| Xcode / Swift | **$XCODE** / **$SWIFT**, Swift 6 language mode, **strict concurrency = complete** |
MDOUT
  exit 0
fi

# ── Report ─────────────────────────────────────────────────────────────────
echo
echo "${BLD}Toolchain — what this repo will actually build with${OFF}"
echo
printf '  %-26s %s\n' "Swift (machine)"   "$SWIFT"
printf '  %-26s %s\n' "Xcode (machine)"   "$XCODE"
printf '  %-26s %s\n' "macOS SDK"         "${MACOS_SDK:-?}"
printf '  %-26s %s\n' "iOS SDK"           "${IOS_SDK:-?}"
printf '  %-26s %s\n' "host macOS"        "${HOST_OS:-?}"
echo
printf '  %-26s %s\n' "min iOS (declared)"   "$SRC_IOS"
printf '  %-26s %s\n' "min macOS (declared)" "$SRC_MACOS"
printf '  %-26s %s%s%s\n' "read from" "$DIM" "$ORIGIN" "$OFF"
echo

warn=0
verlt() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ] && [ "$1" != "$2" ]; }

# A deployment target above the SDK cannot be satisfied — the SDK has no symbols for it.
if [ -n "$MACOS_SDK" ] && [ -n "$SRC_MACOS" ] && verlt "$MACOS_SDK" "$SRC_MACOS"; then
  echo "${RED}✗ min macOS $SRC_MACOS is ABOVE the installed macOS SDK $MACOS_SDK${OFF}"
  echo "  ${DIM}An app target will refuse this. Either install a newer Xcode or lower the target.${OFF}"
  warn=$((warn + 1))
fi
if [ -n "$IOS_SDK" ] && [ -n "$SRC_IOS" ] && verlt "$IOS_SDK" "$SRC_IOS"; then
  echo "${RED}✗ min iOS $SRC_IOS is above the installed iOS SDK $IOS_SDK${OFF}"; warn=$((warn + 1))
fi

# CLAUDE.md §1 must describe this machine, not an aspiration.
if [ -f CLAUDE.md ]; then
  claimed=$(grep -E '^\| Xcode / Swift \|' CLAUDE.md | head -1)
  if [ -n "$claimed" ]; then
    echo "$claimed" | grep -q "\*\*$XCODE\*\*" || {
      echo "${YEL}⚠ CLAUDE.md §1 disagrees with this machine${OFF}"
      echo "  ${DIM}says:  $(printf '%s' "$claimed" | sed 's/|/ /g' | tr -s ' ')${OFF}"
      echo "  ${DIM}found: Xcode $XCODE / Swift $SWIFT${OFF}"
      echo "  ${DIM}Fix with --markdown, and get approval before editing CLAUDE.md.${OFF}"
      warn=$((warn + 1))
    }
  fi
fi

[ "$warn" -eq 0 ] && echo "${GRN}toolchain and declared targets are consistent${OFF}"
echo
echo "${DIM}Emit the §1 table: ./Scripts/detect-toolchain.sh --markdown${OFF}"
exit 0
