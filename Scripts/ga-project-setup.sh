#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    needs-approval
#@purpose   Gate the Xcode toolchain and prepare a new repo's project inputs — the four .xcconfig files and the checklist for creating the .xcodeproj itself.
#@usage     ga-project-setup.sh <target-dir> [--apply] [--yes] [--product NAME] [--bundle-id ID] [--team-id ID] [--org NAME] [--targets ios,macos] [--ios N] [--macos V] [--adopt|--prepare]
#@in        target:dir --apply:flag(without it, dry run) --yes:flag(skip the prompt; same as GA_ASSUME_YES=1) --product:string(product name, default the target's basename) --bundle-id:string(base reverse-DNS id, no stage suffix) --team-id:string(10-char Apple Team ID; never invented, omit if unknown) --org:string(organization name for file headers) --targets:csv(ios,macos) --ios:int(iOS deployment floor) --macos:string(macOS deployment floor) --prepare:flag(force prepare mode) --adopt:flag(force adopt mode)
#@out       stdout:the toolchain verdict, the answers, and the plan; with --apply the Configurations/ files and XCODE-SETUP.md exist
#@exit      0=ok 2=usage 3=Xcode toolchain missing or incomplete — nothing written 4=declined at the prompt 1=other error
#@effects   with --apply: writes Configurations/{Base,DEV,TEST,BETA,PROD}.xcconfig and XCODE-SETUP.md under the TARGET. NEVER creates, opens or edits an .xcodeproj
#@when      xcode project setup|new repo project|xcconfig files|bundle id per stage|team id|command line tools missing|create the xcode project
#
# Why this exists: GenericArch installs rules, skills and packages, but the .xcodeproj is the one
# thing it has never produced. Generating it would mean either a second build-system-of-record or a
# hand-authored pbxproj that nothing here can verify opens. Which generators were considered, and
# why none was taken: docs/REPO.md.
#
# So this script prepares everything that IS mechanical — the toolchain gate, the four committed
# .xcconfig files that CLAUDE.md §2.10 and .claude/notes/SCHEMES.md specify, and an exact checklist
# — and leaves the two minutes of File > New > Project to a human with Xcode open. What it writes is
# reviewable text; what it declines to write is a binary nobody could review.
#
# It runs BEFORE the GenericArch install, so it depends on nothing the install provides.
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=Scripts/ga-lifecycle.sh
. "$HERE/ga-lifecycle.sh"
SRC="$(cd "$HERE/.." && pwd)"

TARGET=""; APPLY=0; MODE=""
PRODUCT=""; BUNDLE_ID=""; TEAM_ID=""; ORG=""; TARGETS=""; IOS=""; MACOS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)     APPLY=1; shift ;;
    --yes)       GA_ASSUME_YES=1; export GA_ASSUME_YES; shift ;;
    --product)   PRODUCT="${2:-}"; shift 2 || true ;;
    --bundle-id) BUNDLE_ID="${2:-}"; shift 2 || true ;;
    --team-id)   TEAM_ID="${2:-}"; shift 2 || true ;;
    --org)       ORG="${2:-}"; shift 2 || true ;;
    --targets)   TARGETS="${2:-}"; shift 2 || true ;;
    --ios)       IOS="${2:-}"; shift 2 || true ;;
    --macos)     MACOS="${2:-}"; shift 2 || true ;;
    --prepare)   MODE="prepare"; shift ;;
    --adopt)     MODE="adopt"; shift ;;
    -h|--help)   sed -n '5,8p' "$0"; exit "$GA_EX_USAGE" ;;
    -*)          ga_die "unknown flag: $1" "$GA_EX_USAGE" ;;
    *)           [ -z "$TARGET" ] || ga_die "one target only" "$GA_EX_USAGE"; TARGET="$1"; shift ;;
  esac
done

# Same order as install.sh: platform before anything is read, so a Linux run says why rather than
# failing later on a missing xcode-select.
ga_require_macos

TARGET="${TARGET:-$(pwd)}"
[ -d "$TARGET" ] || ga_die "no such directory: $TARGET" "$GA_EX_USAGE"
TARGET="$(cd "$TARGET" && pwd)"
[ -w "$TARGET" ] || ga_die "target is not writable: $TARGET" "$GA_EX_ERR"

# ── 1. The toolchain gate ──────────────────────────────────────────────────
# Two separate things, and conflating them is the usual confusion: the Command Line Tools give you
# swift/xcrun/git, and full Xcode.app gives you the project templates. Preparing inputs needs the
# first; the checklist this script prints cannot be followed without the second. So both are
# checked, and each failure names its own fix.
ga_hdr "── Xcode toolchain ────────────────────────────────────"

DEVDIR="$(xcode-select -p 2>/dev/null || true)"
if [ -z "$DEVDIR" ] || [ ! -d "$DEVDIR" ]; then
  ga_die "Xcode Command Line Tools are not installed — nothing was written.

  Install them, then re-run:
      xcode-select --install

  If they are installed but xcode-select points somewhere stale, point it at your Xcode:
      sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer" "$GA_EX_COMPAT"
fi
ga_ok "Command Line Tools: $DEVDIR"

if ! xcrun --find swift >/dev/null 2>&1; then
  ga_die "xcode-select resolves to $DEVDIR but xcrun cannot find swift there — the toolchain is
  incomplete and nothing was written.

  Repair or reinstall the tools, then re-run:
      sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install" "$GA_EX_COMPAT"
fi
ga_ok "swift: $(xcrun swift --version 2>/dev/null | head -1)"

# The developer dir of full Xcode ends in Xcode.app/Contents/Developer; the bare CLT install lives at
# /Library/Developer/CommandLineTools. Creating a project is a full-Xcode operation, so in prepare
# mode this is a stop, not a warning — printing "now open Xcode" to someone who has no Xcode is
# worse than refusing.
HAS_XCODE_APP=0
case "$DEVDIR" in *.app/Contents/Developer) [ -x "$DEVDIR/usr/bin/xcodebuild" ] && HAS_XCODE_APP=1 ;; esac

# ── 2. Prepare or adopt ────────────────────────────────────────────────────
# Which one is decided by the target, not by preference: a directory that already holds a project
# needs its settings reconciled, and one that does not needs them written from scratch.
FOUND_PROJ=""
for p in "$TARGET"/*.xcodeproj "$TARGET"/*.xcworkspace; do
  [ -e "$p" ] && FOUND_PROJ="$FOUND_PROJ ${p##*/}"
done
FOUND_PROJ="${FOUND_PROJ# }"

if [ -z "$MODE" ]; then
  if [ -n "$FOUND_PROJ" ]; then MODE="adopt"; else MODE="prepare"; fi
fi

if [ "$MODE" = "prepare" ] && [ "$HAS_XCODE_APP" -eq 0 ]; then
  ga_die "only the Command Line Tools are installed — $DEVDIR

  Preparing the inputs would succeed, but the next step it prints (File > New > Project) needs full
  Xcode, so this would hand you a checklist you cannot follow. Nothing was written.

  Install Xcode from the App Store, then:
      sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer

  Already have a project and only want its .xcconfig files refreshed?  --adopt" "$GA_EX_COMPAT"
fi
[ "$HAS_XCODE_APP" -eq 1 ] && ga_ok "full Xcode: $DEVDIR" \
  || ga_warn "Command Line Tools only — enough to adopt, not to create a project"

ga_hdr "── Project setup ($MODE) ──────────────────────────────"
printf '  into     %s\n' "$TARGET"
if [ "$MODE" = "adopt" ]; then
  printf '  found    %s%s%s\n' "$GA_BLD" "${FOUND_PROJ:-<none — forced with --adopt>}" "$GA_OFF"
  ga_dim "  Your project stays exactly as it is. This only writes the .xcconfig files it should"
  ga_dim "  reference, and never opens or edits the .xcodeproj."
else
  printf '  found    %sno .xcodeproj — you will create it after this\n' "$GA_DIM$GA_OFF"
fi
echo

# ── 3. The answers ─────────────────────────────────────────────────────────
# Every one of these is either supplied by flag or asked. Nothing is defaulted silently: the bundle
# ID and the floors are decisions with consequences (re-provisioning, and which devices are dropped),
# and CLAUDE.md §0 puts the floors on the never-defaulted list explicitly.
have_tty() { { exec 3<>/dev/tty; } 2>/dev/null && { exec 3>&-; return 0; }; return 1; }

ask() {   # ask <prompt> <default>  → echoes the answer
  _a=""
  if have_tty; then
    exec 3<>/dev/tty
    if [ -n "$2" ]; then printf '  %s%s%s [%s] ' "$GA_BLD" "$1" "$GA_OFF" "$2" >&3
    else                 printf '  %s%s%s ' "$GA_BLD" "$1" "$GA_OFF" >&3; fi
    read -r _a <&3 || _a=""
    exec 3>&-
  fi
  printf '%s' "${_a:-$2}"
}

MISSING=""
need() {   # need <value> <flag-name>
  [ -n "$1" ] || MISSING="$MISSING $2"
}

[ -n "$PRODUCT" ] || PRODUCT="$(ask 'Product name?' "$(basename "$TARGET")")"

if [ -z "$BUNDLE_ID" ]; then
  # Suggested, never assumed — the suggestion is a shape to correct, and the prompt says so.
  _suggest="com.example.$(printf '%s' "$PRODUCT" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
  BUNDLE_ID="$(ask "Base bundle ID? (no stage suffix — .dev/.test/.beta are added per configuration)" "$_suggest")"
fi
case "$BUNDLE_ID" in
  *.*) : ;;
  *)   ga_die "bundle ID must be reverse-DNS, e.g. com.acme.$PRODUCT — got: $BUNDLE_ID" "$GA_EX_USAGE" ;;
esac
case "$BUNDLE_ID" in
  com.example.*) ga_warn "bundle ID is still the com.example placeholder — change it before you ship;
  it appears in all four .xcconfig files and renaming later means re-provisioning" ;;
esac

if [ -z "$TEAM_ID" ]; then
  # Deliberately allowed to stay empty. A fabricated Team ID is worse than a blank one: it looks
  # answered, signs nothing, and is found at the first archive.
  TEAM_ID="$(ask 'Apple Team ID? (10 chars — leave blank if you do not have it yet)' '')"
fi
if [ -n "$TEAM_ID" ]; then
  case "$TEAM_ID" in
    *[!A-Z0-9]*|???????????*|?????????) ga_die "Team ID must be exactly 10 uppercase alphanumerics — got: $TEAM_ID" "$GA_EX_USAGE" ;;
  esac
fi

[ -n "$ORG" ] || ORG="$(ask 'Organization name? (file headers; blank to skip)' '')"

if [ -z "$TARGETS" ]; then
  TARGETS="$(ask 'Targets? ios,macos / ios / macos' 'ios,macos')"
fi
WANT_IOS=0; WANT_MACOS=0
case ",$TARGETS," in *,ios,*) WANT_IOS=1 ;; esac
case ",$TARGETS," in *,macos,*) WANT_MACOS=1 ;; esac
[ "$WANT_IOS" -eq 1 ] || [ "$WANT_MACOS" -eq 1 ] \
  || ga_die "--targets must include ios and/or macos — got: $TARGETS" "$GA_EX_USAGE"

# The stack is acquired, never assumed (CLAUDE.md §1). One precedence, and detect-toolchain.sh owns
# it: THE PROJECT wins — its settings are the shipped contract — then the machine fills the gaps, and
# only what neither answers is asked. Re-asking something the project already answers is how a setup
# starts overwriting decisions it was told to respect.
#
# Two channels, because they answer different questions: --markdown carries the resolved rows with a
# Source column, and the human report carries the installed SDKs, which are the ceiling rather than
# an answer.
PROJ_IOS=""; PROJ_MACOS=""; SWIFT_MODE=""; SDK_IOS=""; SDK_MACOS=""
if [ -x "$SRC/Scripts/detect-toolchain.sh" ]; then
  # --root, not a cd: detect-toolchain.sh cd's to its own repo root unconditionally, so changing
  # directory before the call silently reported THIS checkout's floors as the target's.
  _md="$(NO_COLOR=1 "$SRC/Scripts/detect-toolchain.sh" --markdown --root "$TARGET" 2>/dev/null || true)"
  # Only rows whose Source says `project` count as the project's answer. A `machine` row is an SDK
  # or a compiler capability, which is a ceiling, not a deployment decision.
  PROJ_IOS="$(printf '%s\n' "$_md"   | awk -F'|' '/Minimum iOS/ && $4 ~ /project/ {gsub(/[^0-9.]/,"",$3); print $3; exit}')"
  PROJ_MACOS="$(printf '%s\n' "$_md" | awk -F'|' '/Minimum macOS/ && $4 ~ /project/ {gsub(/[^0-9.]/,"",$3); print $3; exit}')"
  # Xcode's SWIFT_VERSION build setting is the LANGUAGE MODE (5.0, 6.0), not the compiler version
  # (6.3.3) — so this row, never the "Xcode / Swift" one. Project answer first, machine latest after.
  # Only the bolded value: that row reads "**6** (available: 5 6)", so stripping every non-digit
  # concatenates all three into 656.
  SWIFT_MODE="$(printf '%s\n' "$_md" | awk '/Swift language mode/ {if (match($0, /\*\*[0-9]+\*\*/)) {print substr($0, RSTART+2, RLENGTH-4); exit}}')"
  _dt="$(NO_COLOR=1 "$SRC/Scripts/detect-toolchain.sh" 2>/dev/null || true)"
  SDK_IOS="$(printf '%s\n' "$_dt" | awk '/^ *iOS [0-9]/ {print $2; exit}')"
  SDK_MACOS="$(printf '%s\n' "$_dt" | awk '/^ *macOS [0-9]/ {print $2; exit}')"
fi

# A floor the project already states is not a question. Adopting an existing project is exactly
# where this matters: its .xcodeproj and manifests are the contract, and this script is only writing
# the .xcconfig files that should agree with them.
if [ "$WANT_IOS" -eq 1 ] && [ -z "$IOS" ] && [ -n "$PROJ_IOS" ]; then
  IOS="$PROJ_IOS"; ga_ok "min iOS $IOS — from this repo's own manifests, not asked"
fi
if [ "$WANT_MACOS" -eq 1 ] && [ -z "$MACOS" ] && [ -n "$PROJ_MACOS" ]; then
  MACOS="$PROJ_MACOS"; ga_ok "min macOS $MACOS — from this repo's own manifests, not asked"
fi

# Whatever is left the project does not answer, so it is asked. The SDK is offered as the ceiling;
# §0 forbids defaulting to it.
if [ "$WANT_IOS" -eq 1 ] && [ -z "$IOS" ]; then
  IOS="$(ask "Minimum iOS? (major only${SDK_IOS:+ — installed SDK is $SDK_IOS})" '')"
  need "$IOS" "--ios"
fi
if [ "$WANT_MACOS" -eq 1 ] && [ -z "$MACOS" ]; then
  MACOS="$(ask "Minimum macOS?${SDK_MACOS:+ (installed SDK is $SDK_MACOS)}" '')"
  need "$MACOS" "--macos"
fi
if [ -n "$MISSING" ]; then
  ga_die "no terminal to ask on, and these were not supplied:$MISSING

  A deployment floor is never defaulted (CLAUDE.md §0) — a number a script picked reads, six months
  on, as a decision somebody made. Pass them explicitly:
      $(basename "$0") \"$TARGET\" --targets $TARGETS${IOS:+ --ios $IOS}${MACOS:+ --macos $MACOS} --apply --yes" "$GA_EX_USAGE"
fi

# A floor above the SDK cannot build. detect-toolchain.sh reports it too, but that runs after the
# install and this is the moment the number is chosen.
vlt() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ] && [ "$1" != "$2" ]; }
[ -n "$IOS" ]   && [ -n "$SDK_IOS" ]   && vlt "$SDK_IOS" "$IOS" \
  && ga_die "min iOS $IOS is above the installed iOS SDK $SDK_IOS — an app target refuses that.
  Lower the floor, or install an Xcode whose SDK is >= $IOS. Nothing was written." "$GA_EX_COMPAT"
[ -n "$MACOS" ] && [ -n "$SDK_MACOS" ] && vlt "$SDK_MACOS" "$MACOS" \
  && ga_die "min macOS $MACOS is above the installed macOS SDK $SDK_MACOS — an app target refuses that.
  Lower the floor, or install an Xcode whose SDK is >= $MACOS. Nothing was written." "$GA_EX_COMPAT"

# ── 4. The plan ────────────────────────────────────────────────────────────
CFGDIR="$TARGET/Configurations"
ga_hdr "── Plan ───────────────────────────────────────────────"
printf '  product    %s%s%s\n' "$GA_BLD" "$PRODUCT" "$GA_OFF"
printf '  bundle ID  %s%s%s  %s(.dev / .test / .beta per stage, none for PROD)%s\n' \
  "$GA_BLD" "$BUNDLE_ID" "$GA_OFF" "$GA_DIM" "$GA_OFF"
printf '  team ID    %s\n' "${TEAM_ID:-$(printf '%snot set — signing left unconfigured%s' "$GA_YEL" "$GA_OFF")}"
printf '  targets    %s%s%s\n' "$GA_BLD" \
  "$([ "$WANT_IOS" -eq 1 ] && printf 'iOS/iPadOS '; [ "$WANT_MACOS" -eq 1 ] && printf 'macOS')" "$GA_OFF"
printf '  floors     %s%s\n' "${IOS:+iOS $IOS}" "${MACOS:+${IOS:+ · }macOS $MACOS}"
echo
for f in Base DEV TEST BETA PROD; do
  if [ -e "$CFGDIR/$f.xcconfig" ]; then
    printf '  %skeep%s Configurations/%s.xcconfig %s(exists — not overwritten)%s\n' \
      "$GA_YEL" "$GA_OFF" "$f" "$GA_DIM" "$GA_OFF"
  else
    printf '  %s+%s    Configurations/%s.xcconfig\n' "$GA_GRN" "$GA_OFF" "$f"
  fi
done
if [ -e "$TARGET/XCODE-SETUP.md" ]; then
  printf '  %skeep%s XCODE-SETUP.md %s(exists — not overwritten)%s\n' "$GA_YEL" "$GA_OFF" "$GA_DIM" "$GA_OFF"
else
  printf '  %s+%s    XCODE-SETUP.md %s(the checklist for creating the project)%s\n' \
    "$GA_GRN" "$GA_OFF" "$GA_DIM" "$GA_OFF"
fi
echo
ga_dim "  No .xcodeproj is created, opened or edited — the project shell stays yours to make."
echo

if [ "$APPLY" -eq 0 ]; then
  ga_warn "dry run — nothing written. Re-run with --apply to write these."
  exit "$GA_EX_OK"
fi
ga_confirm "Write these files into ${TARGET##*/}?" || { ga_warn "declined — nothing written"; exit "$GA_EX_ABORT"; }

# ── 5. Write ───────────────────────────────────────────────────────────────
# Existing files are never overwritten: this may be re-run to add a target or fix a floor, and a
# blind rewrite would discard hand-tuned build settings, which is the one thing .xcconfig files
# exist to keep reviewable.
mkdir -p "$CFGDIR"
WROTE=0

# Base carries only what is genuinely shared. Per-configuration values belong in the four files that
# include it, or the diff stops telling you which stage changed.
if [ ! -e "$CFGDIR/Base.xcconfig" ]; then
  {
    printf '// Base.xcconfig — settings shared by every configuration.\n'
    printf '// Generated by Scripts/ga-project-setup.sh. Edit freely; it is never overwritten.\n'
    printf '//\n'
    printf '// Do NOT set build settings in the Xcode UI. With a thin .xcodeproj an .xcconfig diff is\n'
    printf '// the only readable record of what changed (.claude/notes/SCHEMES.md).\n\n'
    printf 'PRODUCT_NAME = %s\n' "$PRODUCT"
    printf 'PRODUCT_BUNDLE_IDENTIFIER = %s\n' "$BUNDLE_ID"
    [ -n "$ORG" ]     && printf 'ORGANIZATION_NAME = %s\n' "$ORG"
    [ -n "$TEAM_ID" ] && printf 'DEVELOPMENT_TEAM = %s\n' "$TEAM_ID" \
                      || printf '// DEVELOPMENT_TEAM = <your 10-char Team ID>   // unset on purpose — never invented\n'
    printf '\n'
    [ -n "$IOS" ]   && printf 'IPHONEOS_DEPLOYMENT_TARGET = %s.0\n' "$IOS"
    [ -n "$MACOS" ] && printf 'MACOSX_DEPLOYMENT_TARGET = %s\n' "$MACOS"
    # Acquired, never quoted from memory (CLAUDE.md §1): the language mode the project states, or
    # the newest this compiler accepts. Written as <mode>.0, which is the form Xcode expects. If the
    # detector could not answer, say so rather than emitting a malformed "= .0".
    if [ -n "$SWIFT_MODE" ]; then printf '\nSWIFT_VERSION = %s.0\n' "$SWIFT_MODE"
    else printf '\n// SWIFT_VERSION — not resolved. ./Scripts/detect-toolchain.sh reports the modes\n'
         printf '// this compiler accepts; set the one you mean rather than inheriting a guess.\n'; fi
    printf 'SWIFT_STRICT_CONCURRENCY = complete\n'
    printf 'CLANG_ENABLE_MODULES = YES\n'
    printf 'ENABLE_USER_SCRIPT_SANDBOXING = YES\n'
    printf '\n// Read ONCE at the composition root into a typed AppEnvironment, never by a feature\n'
    printf '// (CLAUDE.md §2.10). Add to Info.plist:  AppEnvironment = $(APP_ENVIRONMENT)\n'
  } > "$CFGDIR/Base.xcconfig"
  WROTE=$((WROTE + 1)); printf '  %s+%s Configurations/Base.xcconfig\n' "$GA_GRN" "$GA_OFF"
fi

# The four stages, exactly as .claude/notes/SCHEMES.md specifies them. TEST/BETA/PROD are all
# release-like on purpose: a QA build compiled -Onone has tested nothing.
write_stage() {   # write_stage <name> <config> <suffix> <display> <cond> <testability> <optlevel> <dbginfo> <env>
  [ -e "$CFGDIR/$1.xcconfig" ] && return 0
  {
    printf '// %s.xcconfig — the %s configuration (scheme %s).\n' "$1" "$2" "$1"
    printf '// Generated by Scripts/ga-project-setup.sh. Edit freely; it is never overwritten.\n\n'
    printf '#include "Base.xcconfig"\n\n'
    if [ -n "$3" ]; then
      printf 'PRODUCT_BUNDLE_IDENTIFIER = $(inherited)%s\n' "$3"
    else
      printf '// PRODUCT_BUNDLE_IDENTIFIER inherited from Base — PROD carries no suffix\n'
    fi
    printf 'PRODUCT_DISPLAY_NAME = %s\n' "$4"
    printf 'APP_ENVIRONMENT = %s\n\n' "$9"
    if [ -n "$5" ]; then printf 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = %s\n' "$5"
    else                 printf '// SWIFT_ACTIVE_COMPILATION_CONDITIONS — none for this stage\n'; fi
    printf 'ENABLE_TESTABILITY = %s\n' "$6"
    printf 'SWIFT_OPTIMIZATION_LEVEL = %s\n' "$7"
    printf 'DEBUG_INFORMATION_FORMAT = %s\n' "$8"
  } > "$CFGDIR/$1.xcconfig"
  WROTE=$((WROTE + 1)); printf '  %s+%s Configurations/%s.xcconfig\n' "$GA_GRN" "$GA_OFF" "$1"
}
write_stage DEV  Debug   '.dev'  "$PRODUCT DEV"  'DEBUG' YES '-Onone' 'dwarf'           dev
write_stage TEST Test    '.test' "$PRODUCT QA"   'TEST'  YES '-O'     'dwarf-with-dsym' test
write_stage BETA Beta    '.beta' "$PRODUCT Beta" 'BETA'  NO  '-O'     'dwarf-with-dsym' beta
write_stage PROD Release ''      "$PRODUCT"      ''      NO  '-Owholemodule' 'dwarf-with-dsym' prod

# The checklist. This is the deliverable in prepare mode: everything a person needs to make the
# project match the files above, in the order Xcode asks for it.
if [ ! -e "$TARGET/XCODE-SETUP.md" ]; then
  {
    printf '# Creating the Xcode project\n\n'
    printf 'Generated by `Scripts/ga-project-setup.sh`. Delete this file once the project exists.\n\n'
    printf 'Nothing in GenericArch generates an `.xcodeproj`. The four `.xcconfig` files beside\n'
    printf 'this one are already written — this is how to point a project at them.\n\n'
    printf '## 1. Create the project\n\n'
    printf 'Xcode > File > New > Project, in `%s`:\n\n' "$TARGET"
    printf '| Field | Value |\n|---|---|\n'
    printf '| Product Name | `%s` |\n' "$PRODUCT"
    printf '| Organization Identifier | `%s` |\n' "${BUNDLE_ID%.*}"
    [ -n "$ORG" ] && printf '| Organization Name | `%s` |\n' "$ORG"
    printf '| Interface | SwiftUI |\n| Language | Swift |\n| Testing System | Swift Testing |\n'
    printf '| Storage | None |\n\n'
    printf 'Uncheck "Create Git repository" — this directory already is one.\n\n'
    printf '## 2. Targets\n\n'
    [ "$WANT_IOS" -eq 1 ]   && printf -- '- **iOS** target `%s` — one target covers iPhone and iPad. Min deploy **iOS %s**.\n' "$PRODUCT" "$IOS"
    [ "$WANT_MACOS" -eq 1 ] && printf -- '- **macOS** target `%s` — a native SwiftUI target. **Not** Mac Catalyst (CLAUDE.md §1). Min deploy **macOS %s**.\n' "$PRODUCT" "$MACOS"
    printf '\nPut the iOS target'"'"'s files under `App/iOS/` and the macOS target'"'"'s under `App/macOS/`.\n'
    printf 'The app shell stays thin: `@main`, the composition root, no logic (CLAUDE.md §3).\n\n'
    printf '## 3. Configurations\n\n'
    printf 'Project > Info > Configurations. Rename `Debug` to keep it, add the other three, then\n'
    printf 'set each one'"'"'s `Based on Configuration File` for **both** the project and every target:\n\n'
    printf '| Configuration | File | Scheme to create |\n|---|---|---|\n'
    printf '| Debug | `Configurations/DEV.xcconfig` | DEV |\n'
    printf '| Test | `Configurations/TEST.xcconfig` | TEST |\n'
    printf '| Beta | `Configurations/BETA.xcconfig` | BETA |\n'
    printf '| Release | `Configurations/PROD.xcconfig` | PROD |\n\n'
    printf 'Delete every build setting Xcode wrote into the project itself — if a value is in both\n'
    printf 'places the project wins silently, and the `.xcconfig` stops being the record.\n\n'
    printf '## 4. Info.plist\n\n'
    printf 'Add one key so the stage reaches Swift as a value rather than a `#if`:\n\n'
    printf '```\nAppEnvironment = $(APP_ENVIRONMENT)\n```\n\n'
    printf 'Read it **once**, at the composition root, into a typed `AppEnvironment`\n'
    printf '(`.claude/notes/SCHEMES.md`). A feature that reads a build flag cannot be tested for the\n'
    printf 'other three configurations.\n\n'
    printf '## 5. Add the packages\n\n'
    printf 'File > Add Package Dependencies > Add Local, for each package under `Packages/`, then add\n'
    printf 'each one to the target'"'"'s Frameworks list. Add by **path** — never a version.\n\n'
    printf '## 6. Check it\n\n'
    printf '```bash\n'
    printf './Scripts/detect-toolchain.sh          # floors should read %s\n' "${IOS:+iOS $IOS}${MACOS:+ / macOS $MACOS}"
    printf 'xcodebuild -list                      # four configurations, four schemes\n'
    printf '```\n\n'
    printf 'Then `/sync-app-notes` fills the scheme inventory in `.claude/notes/SCHEMES.md` from these\n'
    printf 'files, and `/verify` walks the rest.\n'
  } > "$TARGET/XCODE-SETUP.md"
  WROTE=$((WROTE + 1)); printf '  %s+%s XCODE-SETUP.md\n' "$GA_GRN" "$GA_OFF"
fi

echo
if [ "$WROTE" -eq 0 ]; then
  ga_ok "everything was already present — nothing rewritten"
else
  ga_ok "$WROTE file(s) written"
fi

ga_hdr "── Next ───────────────────────────────────────────────"
if [ "$MODE" = "prepare" ]; then
  printf '  1. %sOpen XCODE-SETUP.md and create the project%s — steps 1-4, about two minutes\n' "$GA_BLD" "$GA_OFF"
  printf '  2. Install GenericArch, then scaffold the packages the project will consume:\n'
  printf '       %s/install.sh %s\n' "$SRC" "$TARGET"
  printf '       ./Scripts/ga-scaffold.sh . --list\n'
  printf '  3. Come back to XCODE-SETUP.md step 5 to add those packages to the target\n'
else
  printf '  1. Point your existing configurations at the files above — XCODE-SETUP.md step 3\n'
  printf '  2. %s/install.sh %s --mode new\n' "$SRC" "$TARGET"
  ga_dim "     --mode new matters: an .xcodeproj makes the installer read this as an existing repo,"
  ga_dim "     which skips Scaffold/ and ga-scaffold.sh — the packages you have not written yet."
fi
echo
exit "$GA_EX_OK"
