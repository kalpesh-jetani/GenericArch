# CLAUDE.md — Generic Apple Platform App Architecture

Reference architecture for **iPhone / iPad / Mac** from one shared codebase. Every package must be
reusable, replaceable, and droppable into a new product with minimal change.

---

## 0. Decisions Claude must ASK about, never assume

**Do not pick one silently.** Present the options with a recommendation, wait, then record it —
`/decide`. Check [DECISIONS.md](docs/DECISIONS.md) first; if a row already answers it, follow it
without re-asking.

| Decision | When to ask | Options |
|---|---|---|
| **Presentation pattern** | **Before every new feature or screen** | MVVM + `@Observable` *(default)* · View-owned state (trivial screens only) · Other |
| **Persistence engine** | Only **if** the feature stores data | SwiftData · Core Data · SQLite/GRDB · Other · **Skip** — trade-offs in [StorageKit.md](docs/modules/StorageKit.md) |
| **Caching / offline policy** | Any screen that fetches remote data | Network-only · Cache-then-network · Offline-first with sync · Skip |
| **New external dependency** | Always, before adding it | Named alternatives + "write it ourselves" + Skip |
| **Extracting a package to a repo** | Only when all three §4.2 tests pass | Extract · Keep local *(default)* |

- Ask **once per feature**, not once per file.
- Always give your recommendation and reason, plus **Other** and (where meaningful) **Skip**.
- Say so in the question if the answer would change the module graph or a §2 rule.
- Don't start the feature while the question is open. Do the answer-independent work first —
  models, protocols, localization keys — then ask.

---

## 1. Stack

**The stack is acquired, never assumed** — `./Scripts/detect-toolchain.sh`:

1. **The project wins.** An existing repo's settings are the shipped contract; a machine upgrade
   must not silently change what the app supports or what it is written in.
2. **The machine fills the gaps** — versions, available SDKs, and the set of valid choices.
3. **Anything neither answers is asked** at init, with the machine's options and the latest
   recommended (`--options`). Record the answer with `/decide`.

Values below are **this repo's resolved answers**, not the tool's defaults. Refresh with
`--markdown`; `./Scripts/check.sh` fails when they drift from the machine.

| Item | Value | Source |
|---|---|---|
| Minimum iOS / iPadOS | **17.0** | project |
| Minimum macOS | **26.6** ⚠ above the installed macOS SDK (26.5) — see below | project |
| Xcode / Swift | **26.6** / **6.3.3** | machine |
| Swift language mode | **6**, strict concurrency = complete *(available: 5, 6)* | machine |
| UI | **SwiftUI** (UIKit/AppKit only behind a `Representable`, only when SwiftUI genuinely cannot) | chosen |
| macOS | **Native SwiftUI target. No Mac Catalyst.** | chosen |
| Dependencies | **SPM.** No CocoaPods, no Carthage, no checked-in `.framework`/`.xcframework` | project |
| Project files | **SPM.** No Tuist, no XcodeGen — [REPO.md](docs/REPO.md) | project |
| Concurrency | **async/await + structured concurrency.** No completion handlers, no Combine in new code, no `DispatchQueue` hopping | project |
| Testing | Swift Testing (`import Testing`); XCTest only for UI tests | project |

**A different stack is a valid answer, and it changes what applies.** The rules in §2 and the module
docs are written for the resolved stack above. Choose UIKit and the DesignSystem docs stop fitting;
choose Combine and §6 does. `/project-init` says which rules a divergent choice invalidates rather
than pretending the architecture is framework-agnostic.

### 1.1 The asymmetric baseline — read before writing shared code

The Mac floor is ~9 OS generations above the iPhone floor.

- **Shared code compiles against iOS 17.** A macOS 26 API in a shared file breaks the iOS build.
- Newer APIs only via `#if os(macOS)` (platform-exclusive) or `if #available` (with a working
  fallback). Never both silently.
- **Never raise the iOS target to reach an API.** Gate it or don't ship it.
- Every gate lives **inside a DesignSystem component or an infrastructure wrapper**. A feature must
  not know which OS it is on.

```swift
platforms: [.iOS(.v17), .macOS("26.6")]
```

The iOS-17-vs-macOS-26 look-and-feel question is **open** ([DECISIONS.md](docs/DECISIONS.md));
until it's answered, DesignSystem tokens stay platform-neutral.

> ⚠ **min macOS 26.6 exceeds the installed macOS SDK 26.5.** SPM accepts it for a library, but an
> app target will not — you cannot deploy above the SDK you build against. Either install an Xcode
> whose SDK is ≥ 26.6, or lower the target to 26.5. `./Scripts/check.sh` fails on this so it can't
> be discovered at archive time.

---

## 2. The rules that must never be broken

1. **No package imports a sibling feature.** Features talk through `Core` protocols and navigate by
   `Route` value → [Navigation.md](docs/modules/Navigation.md)
2. **No third-party type crosses a module boundary.** Wrapper always → §7
3. **No hardcoded user-facing string.** Localized key, always → [LocalizationKit.md](docs/modules/LocalizationKit.md)
4. **No system alert, action sheet, or system-styled message surface.** One presenter →
   [Messaging.md](docs/modules/Messaging.md)
5. **Every data-driven screen handles every content state** — loading, empty, offline, error,
   loaded, plus paging where paged → [Core.md](docs/modules/Core.md), [DesignSystem.md](docs/modules/DesignSystem.md)
6. **Every dependency injected via protocol.** No `.shared`, and no `resolve`, from inside a feature
   type → [DIKit.md](docs/modules/DIKit.md)
7. **No `try?` that swallows an error**, no `fatalError` in a shipping path, no force-unwrap outside
   tests.
8. **No `@unchecked Sendable`** without a comment justifying the manual synchronization.
9. **No silent architectural choice.** If it's in §0, ask.
10. **No `#if DEBUG` or build-flag branching in a feature.** Configuration is read once at the
    composition root and injected as `AppEnvironment` → [SCHEMES.md](.claude/notes/SCHEMES.md)

---

## 3. Architecture principles

**Protocol-oriented** — model every capability as a protocol first, implementation second. Defaults
in protocol extensions, never base classes. Abstract on *capability*, not type (`ImageCaching`,
`TokenRefreshing`). Generics where they remove casting; `any P` at composition boundaries.

**Modular** — one responsibility per package; if it needs a `// MARK: - Unrelated`, split it.
Dependency direction is strictly downward:

```
App shell (thin — @main, composition root, no logic)
      ↓
Features (never import each other)
      ↓
DesignSystem · Navigation
      ↓
Infrastructure (StorageKit, LocalizationKit, LoggingKit, NotificationKit, DIKit, Wrappers)
      ↓
Core (protocols, models, errors — zero dependencies)

   ┄┄ mapped in at our boundary, like any vendor (§7) ┄┄
   GenericArch-NetworkKit · GenericArch-ImageCache   (extracted, zero-dependency)
```

**Boundaries are enforced by `Package.swift`, not repo walls** — a local package still cannot import
a sibling feature. That is why §4 can be one repo without weakening rule 1.

**Inheritable** — a new feature gets standard behavior free and can override any piece. The path is
a **protocol + extension** supplying state handling, error mapping, retry, lifecycle. **No generic
base classes.** Prefer composition wherever both work.

**Scalable** — adding a feature edits zero other features: one local package, one line in the
composition root, one `Route` case. Use `/new-feature`.

---

## 4. Repository

### 4.1 Single repo, two extracted packages

```
GenericArch/
├── App/{GenericArch-iOS, GenericArch-macOS}    thin shells
├── Packages/
│   ├── Core, DIKit, StorageKit, LocalizationKit,
│   │   LoggingKit, NotificationKit, Navigation, DesignSystem
│   ├── Wrappers/                               one target per external library (§7)
│   └── Features/Feature<Name>/
├── docs/                                       reasoning
└── .claude/{notes, skills, commands}
```

Local packages wire with `.package(path:)` and carry **no version numbers** — git history is the
version.

| Extracted repo | Contains |
|---|---|
| `GenericArch-NetworkKit` | HTTP, middleware, token refresh, download/upload, background + resumable transfer |
| `GenericArch-ImageCache` | remote image loading, memory + disk cache, prefetch, off-main decode |

**Both have zero dependencies — neither imports `Core`.** SPM resolves a git dependency from that
repo's root manifest, so an extracted package cannot reach one inside this repo. They declare their
own errors and protocols; we map at our boundary exactly as §7 treats a vendor.

Versioning, local overrides, and adding a package: [REPO.md](docs/REPO.md). Releasing an extracted
package: `/release-bump`.

### 4.2 When to extract — all three must be true

1. **Product-independent** — no knowledge of this product's domain.
2. **Actually reused** — a second product consumes it, not "might one day".
3. **Stable** — its public API is not still being discovered.

Otherwise **keep it local**; local costs nothing and reversing an extraction doesn't. A package that
can't stand alone without `Core` was never product-independent. Extraction is a §0 question.

**One exception, and only this one: seed packages.** `NetworkKit` and `ImageCache` were designated
extracted at inception, before any second product could satisfy test 2. That designation is
deliberate and closed — **the list does not grow by precedent.** Any further extraction must pass all
three tests on evidence, and "we did it for NetworkKit" is not evidence. Feature packages fail all
three by definition and are never candidates.

---

## 5. Index

Where each layer, reference, and inventory lives. Deciding where **new** material belongs:
[STRUCTURE.md](docs/STRUCTURE.md).

### Modules — `docs/modules/`

| Doc | Read it when |
|---|---|
| [Core.md](docs/modules/Core.md) | Shared protocol or domain model; `AppError` mapping; `ContentState`, `Paged` |
| [NetworkKit.md](docs/modules/NetworkKit.md) | Endpoint, middleware, token refresh, download/upload, background transfer *(extracted)* |
| [ImageCache.md](docs/modules/ImageCache.md) | Remote image, cache sizing, prefetch *(extracted)* |
| [StorageKit.md](docs/modules/StorageKit.md) | Persistence, secrets, caches, migrations, the §0 engine question |
| [DIKit.md](docs/modules/DIKit.md) | Dependency key, `Assembly`, preview/test overrides |
| [DesignSystem.md](docs/modules/DesignSystem.md) | Any view, token, component, content state, platform gate |
| [LocalizationKit.md](docs/modules/LocalizationKit.md) | Any user-visible string, plurals, formats, a new language |
| [Messaging.md](docs/modules/Messaging.md) | Any message, error, confirmation, permission rationale |
| [Navigation.md](docs/modules/Navigation.md) | A screen, deep link, split view, state restoration |
| [NotificationKit.md](docs/modules/NotificationKit.md) | Push registration, payload → `Route`, local notifications |
| [LoggingKit.md](docs/modules/LoggingKit.md) | Any log call; anything derived from a response or user input |
| [AppShell.md](docs/modules/AppShell.md) | Composition root, scene phase, restoration, launch gates |

### Cross-cutting — `docs/`

| Doc | Read it when |
|---|---|
| [DECISIONS.md](docs/DECISIONS.md) | **Before any §0 question** — and before re-proposing anything |
| [DONE.md](docs/DONE.md) | **Before calling a change finished** |
| [CONVENTIONS.md](docs/CONVENTIONS.md) | Naming, file layout, access control, doc comments |
| [STRUCTURE.md](docs/STRUCTURE.md) | Where new guidance belongs; the CLAUDE.md approval gate |
| [REPO.md](docs/REPO.md) | Versioning, local overrides, adding a package, why not Tuist |
| [SHARING.md](docs/SHARING.md) | Handing this base to someone else; adopting it into another repo |
| [DELIVERY.md](docs/DELIVERY.md) | CI, signing, app version and build numbers, release, rollback |
| [PERFORMANCE.md](docs/PERFORMANCE.md) | Launch budget, SwiftUI rendering, list scrolling, diagnosing a hitch |
| [GAPS.md](docs/GAPS.md) | What this architecture deliberately does not cover yet |

### Generated inventories — `.claude/notes/`

[FEATURES](.claude/notes/FEATURES.md) · [NAVIGATION](.claude/notes/NAVIGATION.md) ·
[ASSETS-IMAGES](.claude/notes/ASSETS-IMAGES.md) · [ASSETS-COLORS](.claude/notes/ASSETS-COLORS.md) ·
[FONTS](.claude/notes/FONTS.md) · [SCHEMES](.claude/notes/SCHEMES.md) ·
[PROJECT](.claude/notes/PROJECT.md)

**Edit the affected rows in the same change as every insertion or deletion** — screen, route, image,
color, font, scheme, target. That is a targeted edit and needs no approval.

**Never run `sync-app-notes` on your own initiative.** The full rescan overwrites correct rows with
incomplete ones when the tree is half-finished. Propose it, say what would change, and wait for an
explicit yes.

---

## 6. Concurrency (Swift 6, strict)

- UI types and view models are `@MainActor` — mark the type, not each method.
- Services are actors or `Sendable` structs. **Never `@MainActor` a network service.**
- Cross-boundary types are `Sendable`. Prefer value types.
- `async let` / `TaskGroup` for parallel work. Never a fire-and-forget `Task { }` that isn't stored
  and cancelled.
- Every long-running operation is **cancellable** and honors `Task.isCancelled`.
- `AsyncStream` / `AsyncSequence` for continuous data. No `NotificationCenter` for app-internal events.
- **Typed throws inside a package only.** Untyped `throws` at an extracted package's public boundary
  — widening a typed throw there is a major bump for a routine new error case.

---

## 7. External library wrapper policy

**No feature or infrastructure module imports a third-party module directly.** Only its wrapper does.

Every wrapper ships: a protocol describing *our* need (in `Core` or `XWrapperInterface`) · one
implementation in `XWrapper`, the sole place the vendor is imported · **our** types at the boundary,
no vendor enums or errors leaking · a `NoOp` and a `Spy`/`Mock`.

Split `XWrapperInterface` (no vendor dep) from `XWrapper` (vendor dep) so features link only the
interface. **Swapping a vendor must touch exactly one target.** Each wrapper carries its own
`<Vendor>Wrapper.md` recording what we use it for and what we deliberately don't.

---

## 8. Multiplatform, accessibility, security

**Adaptivity** — branch on **size class and platform capability**, never device model or width
constants. Navigation state is data → [Navigation.md](docs/modules/Navigation.md). iPad: keyboard
shortcuts, hover, drag & drop, multiple scenes, Slide Over. Mac: menu bar `Commands`, window
restoration, sidebar, toolbar, context menus. `#if os(...)` lives **inside DesignSystem
components**, not features.

**Accessibility — a requirement, not polish.** Localized `accessibilityLabel`, correct trait,
≥44×44pt on every interactive element. VoiceOver order verified. Dynamic Type to XXXL without
truncation. Respect Reduce Motion, Reduce Transparency, Increase Contrast, Bold Text. Contrast
≥4.5:1 for body text. **Never encode meaning in color alone.** Mostly guaranteed inside components
→ [DesignSystem.md](docs/modules/DesignSystem.md).

**Security & privacy** — ATS enforced, no arbitrary loads. **Certificate pinning off by default**
(a rotated cert bricks every installed copy with no remote fix); opt in per product only with a
rotation plan and kill switch. No PII, tokens, or bodies in logs → [LoggingKit.md](docs/modules/LoggingKit.md).
Secrets to Keychain only → [StorageKit.md](docs/modules/StorageKit.md).
`PrivacyInfo.xcprivacy` current **per package**, including required-reason APIs. Biometrics behind
`BiometricAuthenticating`.

**Verify every screen at:** iPhone portrait/landscape · iPad portrait/landscape/split · Mac resized
small and large · Dynamic Type XXXL · Dark Mode (`/dark-light-mode`) · RTL (`/rtl-support`).

---

## 9. Testing

- Unit-test every view model, mapper, and service against protocol mocks. **No network** — enforced
  by mandatory `testValue` on every dependency key.
- **Snapshots are bounded on purpose:** full matrix (states × light/dark × RTL × XXXL × disabled)
  for DesignSystem components; screens get `loaded` + one failure state. The full matrix per screen
  is 40+ each and becomes the flakiest suite in the repo → [DesignSystem.md](docs/modules/DesignSystem.md)
- Contract tests per wrapper — real implementation and mock satisfy the same suite.
- Localization test: no `.xcstrings` key missing in any language, no view using a raw literal.
- **Every package builds and tests standalone** with `swift test`. That is what keeps boundaries
  honest now that repo walls don't.

---

## 10. Conventions

Naming, file layout, access control, and doc comments: [CONVENTIONS.md](docs/CONVENTIONS.md).
Most are enforced by [`.swiftlint.yml`](.swiftlint.yml) and `./Scripts/check.sh`, so they don't need
to be held in context.

Two that are rules, not conventions: **`public` only what crosses a package boundary** (in an
extracted package every `public` symbol is a semver commitment), and **comments explain *why*, never
*what***.

---

## 11. Finishing a change

**Read [DONE.md](docs/DONE.md) before saying a change is done**, or run `/verify` to walk it against
the diff. Do not declare completion from memory of the checklist — the items most often missed are
the ones that feel already handled.

If something can't be checked here (device, VoiceOver, Mac resize), **say what was skipped**.
Silently omitting it is the failure that checklist exists to prevent.

Build and test: `/build [DEV|TEST|BETA|PROD] [ios|macos] [build|test|archive]`.

---

## 12. For Claude specifically

- **Check §0 first.** If the task touches a listed decision and [DECISIONS.md](docs/DECISIONS.md)
  has no answer, ask before writing code.
- **Read the module doc before touching a module** (§5). It holds the rules and code shapes this file
  deliberately doesn't.
- **Never edit this file without explicit approval** — including when certain. Show the exact text
  and wait ([STRUCTURE.md](docs/STRUCTURE.md)). New guidance almost always belongs elsewhere: a
  module doc, a skill, or a command — none of which require touching this file.
- **Edit the affected `.claude/notes/` rows in the same change** as any insertion or deletion. Never
  run `sync-app-notes` without an explicit yes.
- **Run `./Scripts/check.sh`** before saying a change is done; it enforces §2 mechanically.
- Read the relevant `Package.swift` before adding a dependency edge. If it violates §3's direction,
  stop and say so rather than adding it.
- **Don't propose extracting a package** unless all three §4.2 tests pass.
- When asked for a feature, produce **protocol + mock + implementation + localized keys + every
  content state** — not just the happy path.
- Prefer extending an existing DesignSystem component over a near-duplicate.
- If a requirement conflicts with a §2 rule, **raise it** — don't silently work around it.
- Never introduce a non-SPM dependency, a completion-handler API, or a raw string literal in UI.
