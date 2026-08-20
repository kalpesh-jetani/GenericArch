# Project settings

Configuration-time properties: the things decided in a manifest, an `.xcconfig`, an entitlement or a
plist, and then left alone.

- **When to read this:** adding a capability, wiring an environment, setting a floor, or answering a
  privacy or security question about how the app is configured. **Not** session reading — none of it
  is needed to write a view or a view model.
- **Owns:** the *rules* these settings must satisfy.
- **Does not own:** the current values. Those are scanned, never hand-written —
  [.claude/notes/PROJECT.md](../.claude/notes/PROJECT.md) for targets, capabilities and the resolved
  stack, [.claude/notes/SCHEMES.md](../.claude/notes/SCHEMES.md) for stages and configurations.

```bash
./Scripts/detect-toolchain.sh          # what the project says vs what the machine has
./Scripts/detect-capabilities.sh       # which capabilities and entitlements are declared
./Scripts/sync-notes.sh --apply        # refresh the generated inventories, offline
```

---

## Where a setting is allowed to live

**SPM for dependencies and project files.** No CocoaPods, Carthage, Tuist, XcodeGen, or a checked-in
`.framework`/`.xcframework` — [REPO.md](REPO.md).

**Configuration is read once, at the composition root**, and injected onward as `AppEnvironment`. A
feature never reads a build flag, an `.xcconfig` value or an `Info.plist` key directly — that is
CLAUDE.md §2.10, and the reason is that a feature which knows its environment cannot be tested in
another one.

## Deployment floors

**Detected, never defaulted.** They live in each `Package.swift` `platforms:` line — the manifest is
what the compiler obeys — and no tool here writes one for you. A manifest with **no** `platforms:`
line means the question is unanswered, which is a valid state and a §0 decision, not a gap to fill
in silently.

Reading the answer, and why an SDK version is not a floor:
[.claude/notes/PROJECT.md](../.claude/notes/PROJECT.md). What the choice costs either way:
[Scaffold/ARCHITECTURE-OPTIONS.md](../Scaffold/ARCHITECTURE-OPTIONS.md).

**Shared code compiles against the lower floor** (CLAUDE.md §1.1). Reach a newer API with
`#if os(macOS)` or `if #available` and a working fallback — never by raising a floor, and never in a
feature: the gate lives inside a DesignSystem component or an infrastructure wrapper.

## Security and privacy

Each of these is a setting, not a coding habit, which is why they live here:

- **ATS enforced.** No arbitrary loads. An exception is a decision with a recorded reason.
- **Certificate pinning off by default.** Opt in per product only with a rotation plan *and* a kill
  switch — a rotated certificate with neither bricks every installed copy, with no remote fix.
- **`PrivacyInfo.xcprivacy` current per package**, including required-reason APIs. Per *package*,
not
  once for the app: a manifest that omits a package's reasons fails review for the whole submission.
- **Secrets in the Keychain only**, behind a protocol → [StorageKit.md](modules/StorageKit.md). Not
  `UserDefaults`, not a plist, not an `.xcconfig` that ships in the bundle.
- **No PII, tokens or response bodies in logs** → [LoggingKit.md](modules/LoggingKit.md). Anything
  derived from a response or from user input is treated as private.
- **Biometrics behind `BiometricAuthenticating`** — a protocol, so a test never touches the real
one.

## Capabilities, entitlements, signing

Adding a capability changes three things at once: the entitlement file, the provisioning profile,
and
usually a `NS*UsageDescription`. A permission with no usage description crashes at the call, not at
build — which is why the scan flags it as a finding rather than a blank cell.

Signing for TEST/BETA/PROD is manual, via CI credentials → [DELIVERY.md](DELIVERY.md) *Code
signing*.
Targets, app groups and current entitlements:
[.claude/notes/PROJECT.md](../.claude/notes/PROJECT.md).

## Localization

Every user-facing string is a localized key from the first screen, and the language set is a project
setting: [LocalizationKit.md](modules/LocalizationKit.md). A release ships no language whose keys
are
incomplete — that is on the [DELIVERY.md](DELIVERY.md) *Release checklist*, not left to notice.
