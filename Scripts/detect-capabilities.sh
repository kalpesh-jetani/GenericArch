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
# Evidence scan for the /gaps Path A triage. Read-only: greps, never builds.
#   ./Scripts/detect-capabilities.sh [source-root]
# Prints:  STATUS <tab> item <tab> evidence
# STATUS is FOUND or ABSENT — mapping those to ✅/⛔/▶ is a judgement /gaps makes,
# deliberately not encoded here (see "absence of evidence is not always a decision").
set -u
ROOT="${1:-.}"
scan() {                       # scan <item> <pattern>
  hits=$(grep -rlE "$2" --include='*.swift' --include='*.plist' --include='*.entitlements' \
         --include='*.yml' --include='Package.swift' "$ROOT" 2>/dev/null \
         | grep -v -e /Pods/ -e /build/ -e /.git/ | head -3 | tr '\n' ' ')
  if [ -n "$hits" ]; then printf 'FOUND\t%s\t%s\n' "$1" "$hits"
  else                    printf 'ABSENT\t%s\t—\n'  "$1"; fi
}
scan "feature-flags"   'RemoteConfig|LaunchDarkly|FeatureFlag'
# Bare vendor words produce false positives: "Segment" matches a UI segmented control,
# "Transaction." matches any DB/MQTT transaction. Anchor on imports and call shapes.
scan "analytics"       'logEvent\(|import Amplitude|import Mixpanel|import Segment\b|PostHog|FirebaseAnalytics'
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
printf '%s\t%s\t%s\n' "$([ -f "$ROOT/.swiftlint.yml" ] && echo FOUND || echo ABSENT)" "swiftlint" ".swiftlint.yml"
printf '%s\t%s\t%s\n' "$(grep -rlq XCUIApplication "$ROOT" 2>/dev/null && echo FOUND || echo ABSENT)" "ui-tests" "XCUIApplication"
deps=$(grep -c 'repositoryURL\|"location"' "$ROOT"/*.xcodeproj/project.pbxproj 2>/dev/null | head -1)
printf 'INFO\tsupply-chain\t%s external package refs\n' "${deps:-0}"
