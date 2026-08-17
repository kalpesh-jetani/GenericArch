#!/usr/bin/env bash
#@kind      util
#@platform  macos
#@claude    call
#@purpose   Survey an existing iOS repo, score how far its structure already matches this architecture, and emit a revision or migration plan.
#@usage     survey-repo.sh <repo-path> [--tsv] [--threshold N]
#@in        repo:dir --tsv:flag(machine output) --threshold:int(match %% that picks revise over migrate, default 70)
#@out       stdout:profile + structure-match score + verdict + ordered plan + conformance counts; --tsv emits kind,key,value,weight,state
#@exit      0=at or above threshold (revise) 1=below threshold (migrate) 2=usage 3=not a repo
#@effects   read-only. Never compiles, never writes to the surveyed repo
# Survey an existing repo and say whether to revise it or migrate it.
#
#   ./Scripts/claude-utils/survey-repo.sh ~/code/TheirApp
#   ./Scripts/claude-utils/survey-repo.sh ~/code/TheirApp --threshold 60
#   ./Scripts/claude-utils/survey-repo.sh ~/code/TheirApp --tsv > survey.tsv
#
# `adopt.sh` copies the tooling in and `/project-init` reconciles the rules. Neither
# answers the question you actually have first: **how far is this repo from the
# architecture already, and is the job a revision or a migration?**
#
# The answer is a score, not a yes/no. A repo at 85% needs a handful of targeted
# changes; one at 20% needs Core extracted before anything else can move. Below the
# threshold the plan is ordered by what unblocks the most, because migrating in the
# wrong order means doing the same work twice.
#
# REPORTS ONLY — it never writes to the surveyed repo, and never builds (§2.12).
#
# Counts, not listings. A legacy repo can hold thousands of rule violations, and a
# report that listed them all would be unreadable and unusable. Each rule gets a
# count plus up to three example files; `audit-feature.sh` is the per-package tool
# once packages exist.
. "$(dirname "$0")/_common.sh"

usage_text() { usage_from "$0"; }

[ $# -ge 1 ] || usage
case "$1" in -h|--help) usage "$EX_OK" ;; esac

TARGET_ARG="$1"; shift
TSV=0; THRESHOLD=70
while [ $# -gt 0 ]; do
  case "$1" in
    --tsv)       TSV=1; shift ;;
    --threshold) [ $# -ge 2 ] || die "--threshold needs a number" "$EX_USAGE"
                 THRESHOLD="$2"; shift 2 ;;
    -h|--help)   usage "$EX_OK" ;;
    *)           die "unknown argument: $1" "$EX_USAGE" ;;
  esac
done
case "$THRESHOLD" in ''|*[!0-9]*) die "--threshold must be a number" "$EX_USAGE" ;; esac

[ -d "$TARGET_ARG" ] || die "no such directory: $TARGET_ARG" "$EX_USAGE"
REPO="$(cd "$TARGET_ARG" && pwd)"

TMP="${TMPDIR:-/tmp}/ga-survey.$$"
trap 'rm -f "$TMP" "$TMP.sw" "$TMP.src"' EXIT INT TERM
: > "$TMP"

# row <kind> <key> <value> <weight> <state>
#   kind   profile | structure | conformance | plan
#   state  yes | no | partial | n/a   (weight is 0 for non-scoring rows)
row() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:-0}" "${5:-n/a}" >> "$TMP"; }

# Swift sources, once — a large app has thousands of files and re-walking the tree
# per check is what makes a survey too slow to run.
find "$REPO" -name '*.swift' -type f \
  -not -path '*/.build/*' -not -path '*/Pods/*' -not -path '*/Carthage/*' \
  -not -path '*/DerivedData/*' -not -path '*/.git/*' -not -path '*/vendor/*' \
  2>/dev/null | sort > "$TMP.sw"
N_SWIFT=$(count_stdin < "$TMP.sw")
[ "$N_SWIFT" -gt 0 ] || die "no Swift sources under $REPO — is this an iOS repo?" "$EX_PRECOND"

# Non-test sources, once. A rule may be relaxed in tests (§2.7), so they are
# excluded from conformance counts.
grep -v -iE '(test|spec)' "$TMP.sw" > "$TMP.src" 2>/dev/null || : > "$TMP.src"

# c <pattern> — matching file count. xargs, not $(…): a real app has thousands of
# sources and one command line cannot hold them (ARG_MAX). The -s guard stops grep
# falling back to stdin, which would hang, when the list is empty.
c() {
  [ -s "$TMP.src" ] || { printf '0'; return 0; }
  tr '\n' '\0' < "$TMP.src" | xargs -0 grep -lE "$1" 2>/dev/null | wc -l | tr -d ' '
}
# ex <pattern> — up to three example paths, repo-relative.
ex() {
  [ -s "$TMP.src" ] || return 0
  tr '\n' '\0' < "$TMP.src" | xargs -0 grep -lE "$1" 2>/dev/null \
    | head -3 | sed "s|^$REPO/||" | tr '\n' ' '
}
# all <pattern> — matches anywhere, tests included (for profile counts).
all() {
  [ -s "$TMP.sw" ] || return 0
  tr '\n' '\0' < "$TMP.sw" | xargs -0 grep -lE "$1" 2>/dev/null | wc -l | tr -d ' '
}
# anywhere <pattern> — true if any source matches; replaces `grep -rq $(cat …)`.
anywhere() {
  [ -s "$TMP.sw" ] || return 1
  tr '\n' '\0' < "$TMP.sw" | xargs -0 grep -lE "$1" 2>/dev/null | grep -q .
}
has_file() { ls "$REPO"/$1 >/dev/null 2>&1; }

# ── Profile: what is this repo? ────────────────────────────────────────────
BUILD=''
has_file 'Podfile'                && BUILD="$BUILD CocoaPods"
has_file 'Cartfile'               && BUILD="$BUILD Carthage"
has_file 'Package.swift'          && BUILD="$BUILD SPM"
has_file '*.xcworkspace'          && BUILD="$BUILD xcworkspace"
has_file '*.xcodeproj'            && BUILD="$BUILD xcodeproj"
has_file 'Tuist' 2>/dev/null      && BUILD="$BUILD Tuist"
has_file 'project.yml'            && BUILD="$BUILD XcodeGen"
row profile "build system" "${BUILD:-unknown}"

N_SWIFTUI=$(c '^[[:space:]]*import SwiftUI')
N_UIKIT=$(c 'UIViewController|UIView\b|import UIKit')
N_STORYBOARD=$(find "$REPO" -name '*.storyboard' -o -name '*.xib' 2>/dev/null | grep -vc '/Pods/' || true)
row profile "UI framework" "SwiftUI in $N_SWIFTUI file(s) · UIKit in $N_UIKIT · $N_STORYBOARD storyboard/xib"

N_ASYNC=$(c '(func [A-Za-z0-9_]+\([^)]*\) async|await )')
N_COMPLETION=$(c 'completion[[:space:]]*:|completionHandler')
N_COMBINE=$(c '^[[:space:]]*import Combine')
N_GCD=$(c 'DispatchQueue')
row profile "concurrency" "async/await in $N_ASYNC · completion handlers in $N_COMPLETION · Combine in $N_COMBINE · GCD in $N_GCD"

N_TESTING=$(all '^[[:space:]]*import Testing')
N_XCTEST=$(all '^[[:space:]]*import XCTest')
row profile "tests" "Swift Testing in $N_TESTING file(s) · XCTest in $N_XCTEST"

N_PKG=$(find "$REPO" -name Package.swift -not -path '*/.build/*' -not -path '*/Pods/*' 2>/dev/null | wc -l | tr -d ' ')
row profile "SPM packages" "$N_PKG manifest(s)"
row profile "Swift sources" "$N_SWIFT file(s)"

FLOORS=$(grep -hoE 'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+|\.iOS\(\.v[0-9]+\)|\.macOS\("?[0-9.]+"?\)' \
  "$REPO"/*.xcodeproj/project.pbxproj "$REPO"/Package.swift 2>/dev/null | sort -u | tr '\n' ' ')
row profile "deployment floors" "${FLOORS:-not found — check the project file}"

# ── Structure match, weighted ──────────────────────────────────────────────
# Weights are load-bearing, not decoration: Core existing is worth more than a
# lint config, because everything else depends on it. A flat score would call a
# repo with four config files 'closer' than one with its domain layer extracted.
score() {                                    # score <key> <weight> <test-result> <detail>
  if [ "$3" -eq 0 ]; then
    row structure "$1" "$4" "$2" yes
  else
    row structure "$1" "$4" "$2" no
  fi
}

has_file 'Packages';                            score "Packages/ directory"        8  $? "local SPM packages live here"
[ -d "$REPO/Packages/Core" ];                   score "Packages/Core"             14  $? "protocols, models, errors — everything depends on it"
[ -d "$REPO/Packages/Features" ];               score "Packages/Features/"        12  $? "one package per feature"
ls -d "$REPO"/Packages/Features/Feature* >/dev/null 2>&1
                                                score "Feature<Name> packages"    10  $? "the scalable unit"
[ -d "$REPO/App" ] || ls -d "$REPO"/*.xcodeproj >/dev/null 2>&1
                                                score "app shell"                  6  $? "thin @main + composition root"
grep -rqE '\.package\(path:' "$REPO"/Package.swift "$REPO"/Packages/*/Package.swift 2>/dev/null
                                                score "path dependencies"          8  $? "packages wired by path, no version numbers"
! has_file 'Podfile' && ! has_file 'Cartfile';   score "SPM only"                  10  $? "no CocoaPods or Carthage"
[ "$N_SWIFTUI" -gt 0 ] && [ "$N_SWIFTUI" -ge "$N_UIKIT" ]
                                                score "SwiftUI-first"              8  $? "SwiftUI at least as prevalent as UIKit"
[ "$N_ASYNC" -gt 0 ] && [ "$N_ASYNC" -ge "$N_COMPLETION" ]
                                                score "async/await-first"          8  $? "structured concurrency over completion handlers"
[ "$N_TESTING" -gt 0 ];                          score "Swift Testing"              4  $? "import Testing, not XCTest"
anywhere 'ContentState'
                                                score "ContentState"               6  $? "one state enum per data-driven screen"
anywhere 'protocol [A-Za-z]*(Providing|Fetching|Caching|Storing|Presenting)'
                                                score "capability protocols"       6  $? "abstraction on capability, not type"
find "$REPO" -name '*.xcstrings' 2>/dev/null | grep -q .
                                                score "string catalogs"            4  $? ".xcstrings, not .strings or literals"
[ -f "$REPO/CLAUDE.md" ];                        score "CLAUDE.md"                  2  $? "the rulebook"
[ -f "$REPO/.claude/MAP.tsv" ];                  score "the .claude/ index"         2  $? "MAP.tsv, notes, skills"
[ -f "$REPO/.swiftlint.yml" ];                   score "lint config"                2  $? "conventions enforced mechanically"

TOTAL=$(awk -F'\t' '$1=="structure" {t += $4} END {print t + 0}' "$TMP")
GOT=$(awk -F'\t' '$1=="structure" && $5=="yes" {t += $4} END {print t + 0}' "$TMP")
PCT=$(awk -v g="$GOT" -v t="$TOTAL" 'BEGIN {printf "%d", (t > 0 ? 100 * g / t : 0)}')

# ── Conformance: counts, with exemplars ────────────────────────────────────
conf() {                                     # conf <rule> <pattern> <fix>
  n=$(c "$2")
  [ "$n" -gt 0 ] || return 0
  row conformance "$1" "$n file(s) · e.g. $(ex "$2")|$3" 0 no
}
conf "vendor import in app code" '^[[:space:]]*import (Alamofire|Moya|SnapKit|RxSwift|Realm|Firebase|SDWebImage|Kingfisher|SwiftyJSON)' \
  "Wrap each vendor: protocol in Core, one implementation in <Vendor>Wrapper (§7)"
conf "system alert used directly" '\.alert\(|UIAlertController|NSAlert\(' \
  "Route through MessagePresenting — one presenter (§2.4)"
conf "singleton access" '\.shared\b' \
  "Inject by protocol via the composition root (§2.6)"
conf "swallowed error" 'try\?' \
  "Map to a typed error with retryability set deliberately (§2.7)"
conf "fatalError in shipping code" 'fatalError\(' \
  "Return a typed error, or make the state unrepresentable (§2.7)"
conf "build-flag branch" '#if[[:space:]]+(DEBUG|RELEASE|BETA)' \
  "Read config once at the root, inject as AppEnvironment (§2.10)"
conf "literal user-facing string" 'Text\("[^"]{2,}"|\.title = "' \
  "Localized keys in an .xcstrings catalog (§2.3)"
conf "GCD queue hopping" 'DispatchQueue\.(main|global)' \
  "@MainActor on the type; actors for services (§6)"

# ── Output ─────────────────────────────────────────────────────────────────
if [ "$TSV" -eq 1 ]; then
  printf '# kind\tkey\tvalue\tweight\tstate\n'
  cat "$TMP"
  printf 'summary\tmatch\t%s\t%s\t%s\n' "$PCT" "$TOTAL" "$([ "$PCT" -ge "$THRESHOLD" ] && echo revise || echo migrate)"
  [ "$PCT" -ge "$THRESHOLD" ] && exit "$EX_OK"
  exit "$EX_ERR"
fi

hdr "survey — $(basename "$REPO")"
awk -F'\t' '$1=="profile" {printf "  %-20s %s\n", $2, $3}' "$TMP"

hdr "structure match — ${PCT}% (${GOT}/${TOTAL} weighted)"
awk -F'\t' -v g="$GRN" -v r="$RED" -v d="$DIM" -v o="$OFF" '
  $1=="structure" {
    mark = ($5 == "yes") ? g "✓" o : r "·" o
    printf "  %s %-26s %s(w%-2s)%s %s\n", mark, $2, d, $4, o, ($5=="yes" ? "" : $3)
  }' "$TMP"

MISSING=$(awk -F'\t' '$1=="structure" && $5=="no" {print $2}' "$TMP")

printf '\n'
if [ "$PCT" -ge "$THRESHOLD" ]; then
  ok "at or above the ${THRESHOLD}% threshold — this is a REVISION, not a migration"
  hdr "what to do"
  info "1. Adopt the tooling:      ./Scripts/adopt.sh $REPO --apply"
  info "2. Reconcile the rules:    /project-init   (your rules win by default)"
  info "3. Audit each feature:     ./Scripts/claude-utils/audit-feature.sh <FeatureName>"
  info "4. Derive gap statuses:    /gaps"
  if [ -n "$MISSING" ]; then
    printf '\n'
    dim "still missing, in weight order:"
    awk -F'\t' '$1=="structure" && $5=="no" {printf "%s\t%s\n", $4, $2}' "$TMP" \
      | sort -rn | awk -F'\t' '{printf "    w%-3s %s\n", $1, $2}'
  fi
else
  warn "below the ${THRESHOLD}% threshold — this is a MIGRATION, and order matters"
  hdr "staged plan — each stage unblocks the next"
  # Ordered by dependency, not by size. Extracting Core before the build system is
  # settled means extracting it twice.
  n=1
  emit() { info "$n. $1"; dim "     $2"; n=$((n + 1)); }
  has_file 'Podfile' || has_file 'Cartfile'
  [ $? -eq 0 ] && emit "Move dependencies to SPM" \
    "CocoaPods/Carthage first — module extraction cannot start until the build system is SPM (§1)"
  [ -d "$REPO/Packages/Core" ] || emit "Extract Core — protocols, models, errors, zero dependencies" \
    "Everything else depends on it. Start with the error type and ContentState (Core.md)"
  anywhere '^[[:space:]]*(public )?protocol ' || emit "Introduce capability protocols" \
    "Abstract on capability (ImageCaching, TokenRefreshing), not on type (§3)"
  emit "Add the DI seam" \
    "One composition root; features receive dependencies, never resolve them (§2.6, DIKit.md)"
  find "$REPO" -name '*.xcstrings' 2>/dev/null | grep -q . || emit "Move strings to an .xcstrings catalog" \
    "Then the no-literal rule can be enforced mechanically (§2.3)"
  [ "$N_SWIFTUI" -ge "$N_UIKIT" ] || emit "Migrate screens to SwiftUI behind Representables" \
    "UIKit stays only where SwiftUI genuinely cannot (§1)"
  [ -d "$REPO/Packages/Features" ] || emit "Carve the first feature into Packages/Features/" \
    "One vertical slice end-to-end proves the seams before the second (new-feature skill)"
  emit "Adopt the tooling and reconcile rules" \
    "./Scripts/adopt.sh $REPO --apply, then /project-init — adopt-for-new-code-only is the usual answer for a hard conflict (ADOPTION.md)"
fi

N_CONF=$(count_match '^conformance' "$TMP")
if [ "$N_CONF" -gt 0 ]; then
  hdr "rule conformance — counts, not a full listing"
  awk -F'\t' -v d="$DIM" -v o="$OFF" '$1=="conformance" {
    split($3, p, "|")
    printf "  %-30s %s\n", $2, p[1]
    printf "  %-30s %s→ %s%s\n\n", "", d, p[2], o
  }' "$TMP"
  dim "per-package detail once packages exist: audit-feature.sh <FeatureName>"
fi

printf '\n'
dim "read-only — nothing in $(basename "$REPO") was changed, and nothing was built (§2.12)"

[ "$PCT" -ge "$THRESHOLD" ] && exit "$EX_OK"
exit "$EX_ERR"
