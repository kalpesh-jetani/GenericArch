#!/usr/bin/env bash
#@kind      tool
#@platform  macos
#@claude    call
#@purpose   Report which app capabilities and entitlements the project declares.
#@usage     detect-capabilities.sh
#@in        none
#@out       stdout:capability list
#@exit      0=ok
#@effects   read-only
#@when      which capabilities|entitlements declared|does it use analytics|push enabled
# Evidence scan for the /gaps Path A triage. Read-only: greps, never builds.
#   ./Scripts/detect-capabilities.sh [source-root]
# Prints:  STATUS <tab> item <tab> evidence
# STATUS is FOUND or ABSENT — mapping those to ✅/⛔/▶ is a judgement /gaps makes,
# deliberately not encoded here (see "absence of evidence is not always a decision").
set -u
ROOT="${1:-.}"
# Resolved dependency checkouts answer for the wrong repo: a vendored .xcframework under
# SourcePackages/ was reported as this app's own crash reporting. Prune every such directory,
# not just Pods. Anything added here must also be pruned in the two probes at the bottom.
SKIP='-e /Pods/ -e /build/ -e /.git/ -e /.build/ -e /SourcePackages/ -e /DerivedData/ -e /Carthage/ -e /node_modules/'
# shellcheck disable=SC2086
scan() {                       # scan <item> <pattern>
  hits=$(grep -rlE "$2" --include='*.swift' --include='*.plist' --include='*.entitlements' \
         --include='*.yml' --include='Package.swift' "$ROOT" 2>/dev/null \
         | grep -v $SKIP | head -3 | tr '\n' ' ')
  if [ -n "$hits" ]; then printf 'FOUND\t%s\t%s\n' "$1" "$hits"
  else                    printf 'ABSENT\t%s\t—\n'  "$1"; fi
}
scan "feature-flags"   'RemoteConfig|LaunchDarkly|FeatureFlag'
# Bare vendor words produce false positives: "Segment" matches a UI segmented control,
# "Transaction." matches any DB/MQTT transaction. Anchor on imports and call shapes.
scan "analytics"       'logEvent\(|import Amplitude|import Mixpanel|import Segment\b|import Smartlook|PostHog|FirebaseAnalytics'
scan "crash-reporting" 'Crashlytics|Sentry|Bugsnag'
scan "storekit"        'import StoreKit|SKProduct|Product\.products\('
scan "auth-flows"      'AuthenticationServices|ASWebAuthenticationSession|SignInWithAppleButton'
scan "cloudkit-sync"   'import CloudKit|NSPersistentCloudKitContainer'
scan "widgets-intents" 'WidgetKit|AppIntent|ActivityKit'
scan "universal-links" 'associated-domains|apple-app-site-association|onOpenURL'
scan "handoff"         'NSUserActivity'
scan "keyboard-focus"  '@FocusState'
scan "haptics"         'UIFeedbackGenerator|sensoryFeedback|UIImpactFeedback'
scan "biometrics"      'LocalAuthentication|LAContext'
scan "search"          '\.searchable\('
scan "push"            'UNUserNotificationCenter|aps-environment'
# Routed through scan() rather than a bare recursive grep. The bare form carried no --include, so
# it matched THIS FILE — the pattern appears in its own source — and reported ui-tests FOUND in a
# repo with zero test targets. scan()'s include list excludes .sh, and its SKIP excludes vendored
# test code. Same reason the two probes below search instead of assuming the repo root.
scan "ui-tests"        'XCUIApplication'

# shellcheck disable=SC2086
lint=$(find "$ROOT" -name '.swiftlint.yml' -o -name '.swiftformat' 2>/dev/null | grep -v $SKIP | head -1)
printf '%s\t%s\t%s\n' "$([ -n "$lint" ] && echo FOUND || echo ABSENT)" "swiftlint" "${lint:-.swiftlint.yml}"

# A root-only glob reported "0 external package refs" for an app with 25 of them, because its
# .xcodeproj sits one directory down. Count DISTINCT repository URLs: a remote package carries
# several markers each, so counting markers turned 25 packages into 67 and swapped one wrong
# number for another. Package.resolved is preferred where present — it is the resolved truth.
# shellcheck disable=SC2086
resolved=$(find "$ROOT" -path '*xcshareddata/swiftpm/Package.resolved' 2>/dev/null | grep -v $SKIP | head -1)
deps=0
if [ -n "$resolved" ]; then
  deps=$(grep -cE '"(identity|package)"[[:space:]]*:' "$resolved" 2>/dev/null | head -1)
else
  # shellcheck disable=SC2086
  pbx=$(find "$ROOT" -name 'project.pbxproj' 2>/dev/null | grep -v $SKIP)
  [ -n "$pbx" ] && deps=$(printf '%s\n' "$pbx" | tr '\n' '\0' \
    | xargs -0 grep -hoE '(repositoryURL|"location")[^;,]*' 2>/dev/null \
    | sed -E 's/.*[=:][[:space:]]*//; s/^"//; s/";?$//' | sort -u | wc -l | tr -d ' ')
fi
printf 'INFO\tsupply-chain\t%s external package refs\n' "${deps:-0}"
