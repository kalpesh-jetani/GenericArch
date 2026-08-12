# Project File & Targets

The `.xcodeproj`, every target in it, and how each one is configured.

- **Maintained by:** targeted edit whenever a target, capability, entitlement, `Info.plist` key, or linked package changes.
  A full rescan is the `/sync-app-notes` **command** — it runs only when you type it.
- **Read this when:** adding a target or extension, adding a capability, wiring a package into a
  target, or debugging a signing/entitlement failure.
- **Lives in:** the repo root's `.xcodeproj` only. Packages have no project file — they are SPM
  manifests, local under `Packages/` (CLAUDE.md §4.1).
- **Companion:** [SCHEMES.md](SCHEMES.md) covers DEV/TEST/BETA/PROD *configurations*. This file
  covers *targets*. The matrix at the bottom joins them.

---

## The project file is a thin shell

CLAUDE.md §3: the app targets carry **no logic** — `@main`, the composition root, scene setup,
menu commands, and nothing else. Everything real lives in a package.

**Allowed in the `.xcodeproj`:** target definitions, file references for the shell's own sources,
package product links, build phases, and a pointer to the `.xcconfig` per configuration.

**Not allowed:** build settings typed into the Xcode UI. Every setting lives in an `.xcconfig`
(see [SCHEMES.md](SCHEMES.md)) — with a hand-maintained project file, a UI-set value is an
invisible change that survives review and breaks a different configuration.

This is what keeps REPO's "SPM only, no Tuist/XcodeGen" decision viable: the project file stays
small enough not to produce real merge conflicts. **If it starts producing them, that's the
revisit trigger** — say so rather than resolving the same conflict twice.

---

## Target inventory

| Target | Type | Platform | Deployment | Bundle ID | Signing | Packages linked |
|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — |

<!-- Example, delete when the app targets exist:
| GenericArch-iOS      | App        | iOS   | 17.0 | com.<org>.genericarch      | Automatic | local: Core, DesignSystem, Navigation, DIKit, StorageKit, Features · remote: NetworkKit, ImageCache |
| GenericArch-macOS    | App        | macOS | 26.6 | com.<org>.genericarch      | Manual    | (same set) |
| GenericArch-iOSTests | Unit test  | iOS   | 17.0 | —                          | —         | app under test only |
| GenericArch-UITests  | UI test    | iOS   | 17.0 | —                          | —         | — |
-->

**Deployment targets must match `Package.swift`** — iOS 17.0, macOS 26.6 (CLAUDE.md §1.1). A target
set higher than its packages compiles; a target set *lower* fails to resolve. Never raise either to
reach an API — gate it or don't ship it.

---

## Per-target notes

### GenericArch-iOS (App)
- Scenes, `UIApplicationDelegate` adaptor only where an OS callback demands one
  (`handleEventsForBackgroundURLSession`, push registration).
- Registers `BGAppRefreshTask` / `BGProcessingTask` at launch —
  **iOS only** ([NetworkKit.md](../../docs/modules/NetworkKit.md)).
- Calls `FontRegistrar.registerAll()` before first render ([FONTS.md](FONTS.md)).

### GenericArch-macOS (App)
- Native SwiftUI, **no Mac Catalyst** (CLAUDE.md §1).
- Owns menu bar `Commands`, window sizing and restoration.
- Hardened Runtime on; notarization exercised from BETA onward, not first attempted at PROD.
- No `BGTaskScheduler` — the Mac equivalent is a plain background task or a login item, decided
  per product.

### Test targets
- Unit tests target the app only for shell-level wiring. **Package tests live in their package**
  and run with `swift test --package-path Packages/<Name>` (CLAUDE.md §9) — don't duplicate them
  here.
- UI tests need `ENABLE_TESTABILITY=YES`, so they run against DEV or TEST, never BETA/PROD.

### Extensions — when they arrive
Each extension is its own target with its own bundle ID (`<app-id>.<extension>`), its own
entitlements, and its own `Info.plist`.

An extension **links packages directly** — it never imports the app. That's a payoff of the
modular design: a share extension can link `Core` + `StorageKit` and stay tiny. Shared data goes
through an **App Group**, listed in the entitlement matrix below.

| Extension | Bundle ID | Shares via | Packages linked |
|---|---|---|---|
| — | — | — | — |

---

## Capabilities & entitlements

| Capability | iOS app | macOS app | Extensions | Notes |
|---|---|---|---|---|
| App Sandbox | n/a | — | — | Required for Mac App Store |
| Hardened Runtime | n/a | — | — | Required for notarization |
| Push Notifications | — | — | — | APNs env differs per configuration ([SCHEMES.md](SCHEMES.md)) |
| Background Modes | — | — | — | Only the modes actually used — an unused mode is a review rejection |
| Keychain Sharing | — | — | — | Needed if an extension reads tokens |
| App Groups | — | — | — | The only sane app↔extension data channel |
| Associated Domains | — | — | — | Universal links ([Navigation.md](../../docs/modules/Navigation.md)) |
| Sign in with Apple | — | — | — | Mandatory if you offer other third-party sign-in |

Entitlements are **per target and per configuration** — a DEV build using the production push
environment silently fails to receive notifications.

---

## Info.plist keys

Substituted from `.xcconfig` where the value differs per configuration. Track them here because a
missing key is a runtime failure, not a build error.

| Key | Target | Value / source | Why |
|---|---|---|---|
| — | — | — | — |

The ones that bite:

- **`NS*UsageDescription`** — a permission request with no usage string **crashes on call**, not at
  build. Every permission in [Messaging.md](../../docs/modules/Messaging.md)'s pre-prompt flow needs
  its matching key, localized via `InfoPlist.xcstrings`.
- **`UIAppFonts` / `ATSApplicationFontsPath`** — main bundle only. Package fonts need runtime
  registration ([FONTS.md](FONTS.md)).
- **`UIBackgroundModes`** — must match what the code actually does.
- **`NSAppTransportSecurity`** — ATS enforced, no arbitrary loads (CLAUDE.md §8). An exception
  here needs a recorded reason.
- **`CFBundleURLTypes` / Associated Domains** — must match the deep-link parser's patterns.
- **`ITSAppUsesNonExemptEncryption`** — set it, or every upload stalls on a manual question.

---

## Package links per target

A target links **only** what it uses. Over-linking bloats the binary and hides layering mistakes.

| Package | iOS app | macOS app | Test | Extensions |
|---|---|---|---|---|
| — | — | — | — | — |

Features are linked by the app targets only — never by each other (CLAUDE.md §2.1). If a package
appears in this table that no source file imports, remove it.

---

## Target × Configuration × Scheme

| Target | DEV / `Debug` | TEST / `Test` | BETA / `Beta` | PROD / `Release` |
|---|---|---|---|---|
| GenericArch-iOS | ✅ build/run | ✅ test | ✅ archive | ✅ archive |
| GenericArch-macOS | ✅ build/run | ✅ test | ✅ archive + notarize | ✅ archive + notarize |
| Unit tests | ✅ | ✅ | — | — |
| UI tests | ✅ | ✅ | — | — |

Both platforms ship from the same four configurations — never a fifth macOS-only config
([SCHEMES.md](SCHEMES.md)).

---

## Privacy manifests

`PrivacyInfo.xcprivacy` is kept **per package** (CLAUDE.md §8), and each app target aggregates
them. Required-reason API declarations must cover what the *packages* do, not just the shell — a
missing declaration is an App Store rejection at upload, after the build succeeded.

| Target / package | Manifest present | Required-reason APIs declared |
|---|---|---|
| — | — | — |

---

## Gaps

| Finding | Where | Noted |
|---|---|---|
| — | — | — |

`/sync-app-notes` flags: build settings set in the project file instead of an `.xcconfig`;
deployment target mismatched against `Package.swift`; a linked package no source file imports; a
permission used with no `NS*UsageDescription`; entitlements that differ from the capability matrix;
an extension importing the app; a background mode declared but unused; and any package missing
`PrivacyInfo.xcprivacy`.
