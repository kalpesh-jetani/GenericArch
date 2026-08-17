# CLAUDE.md — Generic Apple Platform App Architecture

Reference architecture for **iPhone / iPad / Mac** from one codebase. Every package must be
reusable, replaceable, and droppable into a new product with minimal change.

---

## 0. Decisions Claude must ASK about, never assume

Check [DECISIONS.md](docs/DECISIONS.md) first; if a row answers it, follow it without re-asking.
Otherwise offer the options with a recommendation plus **Other** and (where meaningful) **Skip**,
wait, then record it with `/decide`. Options and trade-offs per decision: the `new-feature` skill.

| Decision | When to ask |
|---|---|
| **Presentation pattern** | **Before every new feature or screen** |
| **Persistence engine** | Only **if** the feature stores data |
| **Caching / offline policy** | Any screen that fetches remote data |
| **New external dependency** | Always, before adding it |
| **Extracting a package to a repo** | Only when all three §4.2 tests pass |

Ask **once per feature**, not once per file. Say so in the question if the answer would change the
module graph or a §2 rule. Don't start while the question is open — do the answer-independent work
first (models, protocols, localization keys), then ask.

---

## 1. Stack

**Acquired, never assumed** — `./Scripts/detect-toolchain.sh`. The project wins, the machine fills
the gaps, the rest is asked at init and recorded with `/decide`.

**Never quote a version from memory or from this file.** Min iOS, min macOS, Xcode, Swift and
language mode live in [PROJECT.md](.claude/notes/PROJECT.md) (refresh with `--markdown`);
`./Scripts/check.sh` fails when they drift.

Fixed by **choice**, not detection — a divergent answer changes what §2 and the module docs apply
to, and `/project-init` names what it invalidates:

- **SwiftUI.** UIKit/AppKit only behind a `Representable`, only where SwiftUI genuinely cannot.
- **macOS is a native SwiftUI target. No Mac Catalyst.**
- **SPM for dependencies and project files.** No CocoaPods, Carthage, Tuist, XcodeGen, or a
  checked-in `.framework`/`.xcframework` — [REPO.md](docs/REPO.md).
- **async/await + structured concurrency.** No completion handlers, no Combine in new code, no
  `DispatchQueue` hopping.
- **Swift Testing** (`import Testing`). XCTest only for UI tests.

### 1.1 The asymmetric baseline — read before writing shared code

The Mac floor sits many OS generations above the iPhone floor, and shared code must satisfy the
lower one. Take both from the `platforms:` line in a `Package.swift` — the manifest is what the
compiler obeys.

- **Shared code compiles against the iOS floor.** A newer API breaks the iOS build even where the
  Mac target would accept it.
- Newer APIs only via `#if os(macOS)` (platform-exclusive) or `if #available` (with a working
  fallback). Never both silently.
- **Never raise a floor to reach an API.** Gate it or don't ship it.
- Every gate lives **inside a DesignSystem component or an infrastructure wrapper** — a feature must
  not know which OS it is on.

Cross-floor look-and-feel is **open** ([DECISIONS.md](docs/DECISIONS.md)); until it's answered,
DesignSystem tokens stay platform-neutral.

---

## 2. The rules that must never be broken

1. **No package imports a sibling feature.** Features talk through `Core` protocols and navigate by
   `Route` value → [Navigation.md](docs/modules/Navigation.md)
2. **No third-party type crosses a module boundary.** Wrapper always → §7
3. **No hardcoded user-facing string.** Localized key, always →
   [LocalizationKit.md](docs/modules/LocalizationKit.md)
4. **No system alert, action sheet, or system-styled message surface.** One presenter →
   [Messaging.md](docs/modules/Messaging.md)
5. **Every data-driven screen handles every content state** — loading, empty, offline, error,
   loaded, plus paging where paged → [Core.md](docs/modules/Core.md),
   [DesignSystem.md](docs/modules/DesignSystem.md)
6. **Every dependency injected via protocol.** No `.shared`, and no `resolve`, from inside a feature
   type → [DIKit.md](docs/modules/DIKit.md)
7. **No `try?` that swallows an error**, no `fatalError` in a shipping path, no force-unwrap outside
   tests.
8. **No `@unchecked Sendable`** without a comment justifying the manual synchronization.
9. **No silent architectural choice.** If it's in §0, ask.
10. **No `#if DEBUG` or build-flag branching in a feature.** Configuration is read once at the
    composition root and injected as `AppEnvironment` → [SCHEMES.md](.claude/notes/SCHEMES.md)
11. **Never `commit` or `push`** — not to "save progress", not because the work looks finished.
    Leave it in the working tree and say what changed. Only an explicit "commit"/"push" counts; a
    release or `/project-init` run is not one.
12. **Never build, run, or test the app.** No `swift build`, `swift test`, `xcodebuild`, no
    simulator or device launch, nothing that invokes the compiler — including `./Scripts/check.sh`,
    whose iOS-floor step compiles. Say what to run and let the user run it. Reading, grepping and
    editing are free; minutes of their machine are not.
13. **Follow the matching skill and name it before starting.** Skipping one of its steps means
    saying which step and why. If none fits, say that — a wrong skill is worse than none.
14. **Stop on a vague instruction.** If a request admits readings that lead to materially different
    work, settle it before doing anything — never pick silently, never ship a "safe subset". Ask for
    a **reference** (repo, file, Figma frame, doc URL, the existing thing it should resemble —
    building from the name of a thing produces something plausible and wrong), a **focused goal**
    ("first paint under 300 ms", not "improve this"), or **which reading**, listed, with your
    recommendation. Ask only what the user alone can answer; whatever the code, the docs or
    [DECISIONS.md](docs/DECISIONS.md) already settles, look up instead.

---

## 3. Architecture principles

**Protocol-oriented** — every capability is a protocol first, implementation second. Defaults in
protocol extensions, never base classes. Abstract on *capability*, not type (`ImageCaching`,
`TokenRefreshing`). Generics where they remove casting; `any P` at composition boundaries.

**Modular** — one responsibility per package; if it needs a `// MARK: - Unrelated`, split it.
Dependency direction is strictly downward, and **`Package.swift` enforces it, not repo walls** — a
local package still cannot import a sibling feature.

```
App shell (thin — @main, composition root, no logic)
  ↓  Features (never import each other)
  ↓  DesignSystem · Navigation
  ↓  Infrastructure (StorageKit, LocalizationKit, LoggingKit, NotificationKit, DIKit, Wrappers)
  ↓  Core (protocols, models, errors — zero dependencies)

GenericArch-NetworkKit · GenericArch-ImageCache — extracted, zero-dependency, mapped in at our
boundary like any vendor (§7)
```

**Inheritable** — a new feature gets standard behavior free and can override any piece, through a
**protocol + extension** supplying state handling, error mapping, retry, lifecycle. **No generic
base classes.** Prefer composition wherever both work.

**Scalable** — adding a feature edits zero other features: one local package, one line in the
composition root, one `Route` case. Use `/new-feature`.

---

## 4. Repository

### 4.1 Single repo, two extracted packages

Local packages wire with `.package(path:)` and carry **no version numbers** — git history is the
version. **The two extracted packages — `GenericArch-NetworkKit`, `GenericArch-ImageCache` — have
zero dependencies and neither imports `Core`;** they declare their own errors and protocols, and we
map at our boundary exactly as §7 treats a vendor. Layout, contents, versioning and local overrides:
[REPO.md](docs/REPO.md). Releasing one: [release-bump](docs/patterns/release-bump.md).

### 4.2 When to extract — all three must be true

1. **Product-independent** — no knowledge of this product's domain.
2. **Actually reused** — a second product consumes it, not "might one day".
3. **Stable** — its public API is not still being discovered.

Otherwise **keep it local**; local costs nothing and reversing an extraction doesn't. A package that
can't stand alone without `Core` was never product-independent. Extraction is a §0 question. **One
exception, closed and not growing by precedent:** the two seed packages —
[DECISIONS.md](docs/DECISIONS.md). Feature packages fail all three tests by definition.

---

## 5. Index

**Look it up before you read or search for it.** Three greps replace a table of contents:

```bash
grep -i navigation .claude/MAP.tsv     # which doc, note, pattern or skill covers a topic
grep -i lint .claude/SCRIPTS.tsv       # which script does this, and its contract
./Scripts/find.sh SmartLockHomeView    # where is this screen/route/endpoint/asset/token?
```

[`MAP.tsv`](.claude/MAP.tsv) indexes every doc, note, pattern and skill with its topics and when to
read it — and **read the module doc before touching a module.**
[`SCRIPTS.tsv`](.claude/SCRIPTS.tsv) is each script's contract: inputs, outputs, exit codes,
effects. **Never read a script's body to learn what it does** — the row is the contract; read the
body only when a call fails, then fix it in the same change. `find.sh` greps all nine inventories in
one call; a miss prints the code-search fallback, and you record the row you find in that change.

**What earlier sessions learned:** [`.claude/memory/INDEX.md`](.claude/memory/INDEX.md) — in-repo
and tracked, so it survives a clone. Never write to a machine-local store. What may be written, and
where **new** material belongs: [STRUCTURE.md](docs/STRUCTURE.md).

`.claude/notes/` is generated. **Edit the affected rows in the same change as every insertion or
deletion** — screen, route, API path, image, colour, font, token, scheme, target. A full rescan is
the user's **`/sync-app-notes`**; never start one yourself.

---

## 6. Concurrency

Assuming the strict-concurrency mode in [PROJECT.md](.claude/notes/PROJECT.md); on an older mode
these still hold, the compiler just stops enforcing them.

- UI types and view models are `@MainActor` — mark the type, not each method.
- Services are actors or `Sendable` structs. **Never `@MainActor` a network service.**
- Cross-boundary types are `Sendable`. Prefer value types.
- `async let` / `TaskGroup` for parallel work. Never a fire-and-forget `Task { }` that isn't stored
  and cancelled.
- Every long-running operation is **cancellable** and honors `Task.isCancelled`.
- `AsyncStream` / `AsyncSequence` for continuous data. No `NotificationCenter` for app-internal
  events.
- **Typed throws inside a package only.** Untyped `throws` at an extracted package's public boundary
  — widening a typed throw there is a major bump for a routine new error case.

---

## 7. External library wrapper policy

**No feature or infrastructure module imports a third-party module directly** — only its wrapper
does, and **swapping a vendor must touch exactly one target.**

Every wrapper ships: a protocol describing *our* need (in `Core` or `XWrapperInterface`) · one
implementation in `XWrapper`, the sole place the vendor is imported · **our** types at the boundary,
no vendor enums or errors leaking · a `NoOp` and a `Spy`/`Mock`. Split `XWrapperInterface` (no
vendor dep) from `XWrapper` (vendor dep) so features link only the interface. Each wrapper carries
its own `<Vendor>Wrapper.md` recording what we use it for and what we deliberately don't.

---

## 8. Multiplatform, accessibility, security

**Adaptivity** — branch on **size class and platform capability**, never device model or width
constants; navigation state is data → [Navigation.md](docs/modules/Navigation.md). iPad: keyboard
shortcuts, hover, drag & drop, multiple scenes, Slide Over. Mac: menu bar `Commands`, window
restoration, sidebar, toolbar, context menus. `#if os(...)` lives **inside DesignSystem
components**, not features.

**Accessibility — a requirement, not polish.** **Never encode meaning in color alone.** Mostly
guaranteed inside components → [DesignSystem.md](docs/modules/DesignSystem.md); what a screen must
still prove, and at which sizes, is the checklist in [DONE.md](docs/DONE.md).

**Security & privacy** — ATS enforced, no arbitrary loads. **Certificate pinning off by default**;
opt in per product only with a rotation plan and kill switch. No PII, tokens, or bodies in logs →
[LoggingKit.md](docs/modules/LoggingKit.md). Secrets to Keychain only →
[StorageKit.md](docs/modules/StorageKit.md). `PrivacyInfo.xcprivacy` current **per package**,
including required-reason APIs. Biometrics behind `BiometricAuthenticating`.

---

## 9. Testing

- Unit-test every view model, mapper, and service against protocol mocks. **No network** — enforced
  by mandatory `testValue` on every dependency key.
- **Snapshots are bounded** → [DesignSystem.md](docs/modules/DesignSystem.md)
- Contract tests per wrapper — real implementation and mock satisfy the same suite.
- Localization test: no `.xcstrings` key missing in any language, no view using a raw literal.
- **Every package builds and tests standalone** with `swift test`. That is what enforces the module
  boundaries.

---

## 10. Conventions

Naming, file layout, access control, and doc comments: [CONVENTIONS.md](docs/CONVENTIONS.md),
enforced by [`.swiftlint.yml`](.swiftlint.yml) and `./Scripts/check.sh`. Three that are rules, not
conventions:

- **`public` only what crosses a package boundary** — in an extracted package every `public` symbol
  is a semver commitment.
- **Every function or initialiser you write or change carries a `///` doc comment** stating what the
  signature cannot.
- **Doc comments, not meta comments.** No `//` that restates the code or narrates the edit; anything
  about the change belongs in the commit message.

---

## 11. Finishing a change

**Read [DONE.md](docs/DONE.md) before saying a change is done**, or run `/verify` to walk it against
the diff. Never declare completion from memory of the checklist — the items most often missed are
the ones that feel already handled. If something can't be checked here (device, VoiceOver, Mac
resize),
**say what was skipped**.

Build and test: `/build` — the sanctioned §2.12 exception; it resolves scheme and destination. A
package has no scheme: `swift build|test --package-path Packages/<Name>`, plus `--filter <Pattern>`
for a single test.

---

## 12. For Claude specifically

- **Never edit this file without explicit approval** — including when certain. Show the exact text
  and wait. Where new guidance belongs instead: [STRUCTURE.md](docs/STRUCTURE.md).
- Read the relevant `Package.swift` before adding a dependency edge. If it violates §3's direction,
  stop and say so rather than adding it.
- When asked for a feature, produce **protocol + mock + implementation + localized keys + every
  content state** — not just the happy path.
- If a requirement conflicts with a §2 rule, or §0 has no recorded answer, **raise it** — don't
  silently work around it, and don't choose the scope of a broad instruction yourself (§2.14).
