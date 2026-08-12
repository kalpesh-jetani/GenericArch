# Schemes & Build Configurations

Four schemes, four configurations, one rule for picking between them.

- **Maintained by:** targeted edit whenever a scheme, configuration, bundle ID, or environment value changes.
  A full rescan is the `/sync-app-notes` **command** — it runs only when you type it.
- **Read this when:** choosing which scheme to build, adding a configuration-dependent value,
  wiring an environment, or preparing a release.
- **Lives in:** the app repo's `.xcodeproj` only. Packages have no schemes — they build with
  `swift build` / `swift test` standalone (CLAUDE.md §9).

---

## The four

| Scheme | Configuration | Stage | Who runs it | Distribution |
|---|---|---|---|---|
| **DEV** | `Debug` | Development | Engineers, all day | None — simulator and local device |
| **TEST** | `Test` | QA | QA team, automated suites | TestFlight internal / ad-hoc |
| **BETA** | `Beta` | Prerelease | External testers, stakeholders | TestFlight external / notarized DMG |
| **PROD** | `Release` | Final release | End users | App Store / Mac App Store |

`Test`, `Beta`, and `Release` are all **release-like** configurations — optimized, assertions
compiled out. Only `DEV` is unoptimized. A QA build that behaves differently from the shipped build
because it was compiled `-Onone` has tested nothing.

---

## When to use which

### DEV — `Debug`
**Use for:** everything you do while writing code. Local runs, previews, unit tests, debugger,
Instruments.

**Never use for:** anything handed to another person. A `Debug` build's timing, memory behavior,
and optimizer output differ enough that "works on DEV" is not evidence.

- `-Onone`, full debug symbols, `ENABLE_TESTABILITY=YES`
- Points at the dev API; self-signed and staging certs accepted
- Debug menu on, verbose logging, all feature flags togglable at runtime
- Analytics and crash reporting → **NoOp wrapper**, never the live project (§7)

### TEST — `Test`
**Use for:** QA verification, regression passes, automated UI test runs, bug reproduction by
someone who isn't the author.

**Why it's separate from BETA:** QA needs a build that is release-like *and* still diagnosable —
verbose logs, an environment switcher, a visible build number. External testers must not see any of
that.

- Optimized (`-O`), `DWARF with dSYM File`, `ENABLE_TESTABILITY=YES` (UI tests need it)
- Points at the QA/staging API
- Debug menu on, log level `debug`, crash reporting → **separate QA project**, never production
- Installed alongside DEV and PROD — distinct bundle ID and icon

### BETA — `Beta`
**Use for:** prerelease distribution to people outside the team, dogfooding, staged rollout
rehearsal, and the final "does this look like the real thing" check before submission.

**Treat it as production with a feedback channel.** If it differs from PROD in anything other than
the environment it points at and its crash-reporting destination, the rehearsal is worthless.

- Identical build settings to `Release`
- Points at **production** API unless there is a stated reason not to — record that reason here
- Debug menu **off**, log level `info`, crash reporting → separate beta project
- Real provisioning profile, real signing path, notarization exercised on Mac

### PROD — `Release`
**Use for:** App Store / Mac App Store submission only.

- `-O` whole-module, `DWARF with dSYM File`, `ENABLE_TESTABILITY=NO`
- Production API. Certificate pinning **off unless the threat model demands it** (CLAUDE.md §8) —
  if enabled, it needs a documented rotation plan and a remote kill switch
- No debug menu, no `TEST`/`BETA` compilation conditions, log level `info` and above with
  redaction enforced ([LoggingKit.md](../../docs/modules/LoggingKit.md))
- Assertions compiled out — which is exactly why CLAUDE.md §2.7 forbids `fatalError` in shipping
  paths and relies on typed errors instead

---

## What differs, per configuration

| Setting | DEV | TEST | BETA | PROD |
|---|---|---|---|---|
| Bundle ID suffix | `.dev` | `.test` | `.beta` | *(none)* |
| Display name | App DEV | App QA | App Beta | App |
| App icon | dev variant | qa variant | beta variant | production |
| API environment | dev | staging | production | production |
| Optimization | `-Onone` | `-O` | `-O` | `-O` whole-module |
| `SWIFT_ACTIVE_COMPILATION_CONDITIONS` | `DEBUG` | `TEST` | `BETA` | *(none)* |
| `ENABLE_TESTABILITY` | YES | YES | NO | NO |
| Debug info | `DWARF` | `DWARF with dSYM` | `DWARF with dSYM` | `DWARF with dSYM` |
| Debug menu | on | on | off | off |
| Log level | `trace` | `debug` | `info` | `info` |
| Crash / analytics | NoOp | QA project | Beta project | Production project |
| Certificate pinning | off | off | off* | off* |
| APNs environment | sandbox | sandbox | production | production |

\* Pinning is **opt-in per product** (CLAUDE.md §8), not a configuration default. When a product
enables it, it goes on for BETA and PROD only — never for DEV/TEST, where staging certs are used.

Distinct bundle IDs are what let all four coexist on one device — a tester filing "it's broken"
while running last week's TEST build is a recurring waste of a day.

---

## Inventory

Filled by `/sync-app-notes` from the `.xcconfig` files and the project's scheme list.

| Scheme | Configuration | Bundle ID | Base URL | Signing | Verified |
|---|---|---|---|---|---|
| — | — | — | — | — | — |

---

## How configuration reaches code

Build settings live in **`.xcconfig` files**, one per configuration, committed and reviewable.
Don't set values in the Xcode build-settings UI — with a thin `.xcodeproj` (REPO), an
`.xcconfig` diff is the only readable record of what changed.

```
Configurations/
  Base.xcconfig
  DEV.xcconfig      #include "Base.xcconfig"
  TEST.xcconfig
  BETA.xcconfig
  PROD.xcconfig
```

Values reach Swift through `Info.plist` substitution, resolved **once** at the composition root
into a typed value, then injected:

```swift
// Core — no feature ever reads a build flag
public enum AppEnvironment: String, Sendable {
    case dev, test, beta, prod

    public var isDebugMenuEnabled: Bool { self == .dev || self == .test }
    // Pinning is opt-in per product; `pinsCertificates` is a build setting, not an
    // environment property. Off unless the threat model demands it (CLAUDE.md §8).
    public var isReleaseLike: Bool     { self == .beta || self == .prod }
}

// App target, composition root — the ONLY place the flag is read
let environment = AppEnvironment(rawValue: Bundle.main.appEnvironmentKey) ?? .prod
builder.register(AppEnvironmentKey.self, environment)
```

**Defaulting to `.prod` is deliberate:** a misconfigured build should fail closed — pinned,
quiet, no debug menu — not open.

### The rule that keeps this clean

**`#if DEBUG` must never appear in a feature.** Same shape as the `#if os(...)` rule (§1.1):
compile-time branching lives in the composition root and infrastructure, and features receive an
injected `AppEnvironment`. A feature that reads a build flag can't be unit-tested for the other
three configurations.

```swift
// ❌ in a feature
#if DEBUG
    showDebugPanel()
#endif

// ✅ in a feature
if environment.isDebugMenuEnabled { showDebugPanel() }
```

---

## Launch guards

Assert the combination at launch, in DEBUG, and fail the build in CI rather than shipping a
mismatch:

- PROD must not resolve a non-production base URL.
- PROD must not compile with `DEBUG`, `TEST`, or `BETA` conditions set.
- Any configuration with the debug menu on must not carry a production bundle ID.
- Crash-reporting destination must match the configuration — a beta build reporting into the
  production project poisons release metrics.

---

## Commands

```bash
xcodebuild -scheme GenericArch-DEV  -configuration Debug   -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme GenericArch-TEST -configuration Test    -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -scheme GenericArch-BETA -configuration Beta    -destination 'generic/platform=iOS' archive
xcodebuild -scheme GenericArch-PROD -configuration Release -destination 'generic/platform=iOS' archive
```

macOS uses the same four schemes with `-destination 'platform=macOS'`. Both platforms ship from the
same configuration set — never a fifth "macOS release" config.

---

## Gaps

| Finding | Where | Noted |
|---|---|---|
| — | — | — |

`/sync-app-notes` flags: a configuration with no matching scheme, a scheme with no `.xcconfig`,
duplicate bundle IDs across configurations, `#if DEBUG` inside a feature package, `DEBUG` set on a
release-like configuration, a live analytics key in a non-PROD config, and PROD pointing at a
non-production URL.
