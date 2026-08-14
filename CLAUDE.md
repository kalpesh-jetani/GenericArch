# CLAUDE.md — Generic Apple Platform App Architecture

Reference architecture for **iPhone / iPad / Mac** from one shared codebase. Every package must be
reusable, replaceable, and droppable into a new product with minimal change.

---

## 0. Decisions Claude must ASK about, never assume

**Do not pick one silently.** Present the options with a recommendation, wait, then record it —
`/decide`. Check [DECISIONS.md](docs/DECISIONS.md) first; if a row already answers it, follow it
without re-asking.

| Decision | When to ask |
|---|---|
| **Presentation pattern** | **Before every new feature or screen** |
| **Persistence engine** | Only **if** the feature stores data |
| **Caching / offline policy** | Any screen that fetches remote data |
| **New external dependency** | Always, before adding it |
| **Extracting a package to a repo** | Only when all three §4.2 tests pass |

The options to offer per decision, and the trade-offs behind them: the `new-feature` skill.

- Ask **once per feature**, not once per file.
- Always give your recommendation and reason, plus **Other** and (where meaningful) **Skip**.
- Say so in the question if the answer would change the module graph or a §2 rule.
- Don't start the feature while the question is open. Do the answer-independent work first —
  models, protocols, localization keys — then ask.

---

## 1. Stack

**The stack is acquired, never assumed** — `./Scripts/detect-toolchain.sh`. The project wins, the
machine fills the gaps, the rest is asked at init and recorded with `/decide`.

This repo's **resolved values** — min iOS, min macOS, Xcode, Swift, language mode — live in
[PROJECT.md](.claude/notes/PROJECT.md). Read them before anything version-dependent; never quote
them from memory. Refresh with `--markdown`; `./Scripts/check.sh` fails when they drift.

Fixed by **choice**, not detection. These are rules — a divergent answer changes what §2 and the
module docs apply to, and `/project-init` names what it invalidates:

- **SwiftUI.** UIKit/AppKit only behind a `Representable`, only where SwiftUI genuinely cannot.
- **macOS is a native SwiftUI target. No Mac Catalyst.**
- **SPM for both dependencies and project files.** No CocoaPods, Carthage, Tuist, XcodeGen, or a
  checked-in `.framework`/`.xcframework` — [REPO.md](docs/REPO.md).
- **async/await + structured concurrency.** No completion handlers, no Combine in new code, no
  `DispatchQueue` hopping.
- **Swift Testing** (`import Testing`). XCTest only for UI tests.

### 1.1 The asymmetric baseline — read before writing shared code

The Mac floor sits many OS generations above the iPhone floor, and shared code must satisfy the
lower one.

**Never type either floor from memory or from this file.** Take them from the project — the
`platforms:` line in any `Package.swift` — or from the machine with
`./Scripts/detect-toolchain.sh`. [PROJECT.md](.claude/notes/PROJECT.md) records what they resolved
to; the manifest is what the compiler actually obeys.

- **Shared code compiles against the iOS floor.** An API newer than it breaks the iOS build even
  where the Mac target would accept it.
- Newer APIs only via `#if os(macOS)` (platform-exclusive) or `if #available` (with a working
  fallback). Never both silently.
- **Never raise a floor to reach an API.** Gate it or don't ship it.
- Every gate lives **inside a DesignSystem component or an infrastructure wrapper**. A feature must
  not know which OS it is on.

The cross-floor look-and-feel question is **open** ([DECISIONS.md](docs/DECISIONS.md)); until it's
answered, DesignSystem tokens stay platform-neutral.

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
11. **Never `commit` or `push`.** Not at the end of a change, not to "save progress", not because
    the work looks finished. Leave everything in the working tree and say what changed; the user
    commits when *they* decide the work is done. Only act on an explicit "commit" or "push" — and
    a release or `/project-init` run is not that instruction either.
12. **Never build, run, or test the app.** No `swift build`, `swift test`, `xcodebuild`, no
    launching a simulator or device, and nothing that invokes the compiler — including
    `./Scripts/check.sh`, whose iOS-floor step compiles. Say what to run and let the user run it.
    Reading, grepping, and editing files need no permission; spending minutes of their machine and
    acting on the result does.
13. **Follow the skill that matches, and say which one.** Name it before starting. If you skip one
    of its steps, say which step and why — silently deviating from a skill you invoked is worse than
    not invoking it. If no skill fits, say that too; a wrong skill is worse than none.
14. **Stop on a vague instruction — ask for a reference or a focused goal.** If a request admits
    more than one reading and those readings lead to materially different work, do nothing until it
    is settled. Do not pick silently, and do not do a "safe subset" and hope. Ask for whichever
    resolves it:
    - **A reference** — the sample repo, file, Figma frame, doc URL, or the existing thing it
      should resemble. Building from the name of a thing produces something plausible and wrong.
    - **A focused goal** — what success looks like, concretely. "Improve this" is not a goal;
      "make the first paint under 300 ms" is.
    - **Which reading**, listed, with your recommendation — when the ambiguity is scope, not input.

    Ask only what the user alone can answer. Anything the code, the docs or
    [DECISIONS.md](docs/DECISIONS.md) already settles, look up instead of asking.

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

Local packages wire with `.package(path:)` and carry **no version numbers** — git history is the
version. **The two extracted packages — `GenericArch-NetworkKit`, `GenericArch-ImageCache` — have
zero dependencies and neither imports `Core`;** they declare their own errors and protocols, and we
map at our boundary exactly as §7 treats a vendor.

Layout, what each extracted package contains, versioning and local overrides:
[REPO.md](docs/REPO.md). Releasing one: [release-bump](docs/patterns/release-bump.md).

### 4.2 When to extract — all three must be true

1. **Product-independent** — no knowledge of this product's domain.
2. **Actually reused** — a second product consumes it, not "might one day".
3. **Stable** — its public API is not still being discovered.

Otherwise **keep it local**; local costs nothing and reversing an extraction doesn't. A package that
can't stand alone without `Core` was never product-independent. Extraction is a §0 question.

**One exception, closed and not growing by precedent:** the two seed packages, designated at
inception before any second product could satisfy test 2 — reasoning in
[DECISIONS.md](docs/DECISIONS.md). Feature packages fail all three tests by definition.

---

## 5. Index

**Grep the map before reading anything** — [`.claude/MAP.tsv`](.claude/MAP.tsv) carries every module
doc, cross-cutting doc, note, pattern and skill with its topics and when to read it. One grep costs a
fraction of the table of contents it replaces.

```bash
grep -i navigation .claude/MAP.tsv          # what covers this topic
awk -F'\t' '$2=="module"' .claude/MAP.tsv   # every module doc
./Scripts/find.sh SmartLockHomeView         # where is this screen/route/endpoint/asset?
```

**Call the script before writing the code** — [`.claude/SCRIPTS.tsv`](.claude/SCRIPTS.tsv)
registers every script with its inputs, outputs, exit codes and side effects. Grep it,
call the script, rely on the result. **Never read a script's body to learn what it
does** — the row is the contract, and the body costs tokens the row already spent.
Read the body only when a call fails; then fix it, in the same change.

```bash
grep -i lint .claude/SCRIPTS.tsv              # which script covers this
awk -F'\t' '$3=="macos"' .claude/SCRIPTS.tsv  # what needs a Mac
```

**Read the module doc before touching a module.** It holds that module's rules and code shapes.

**Look it up before you search for it** — `./Scripts/find.sh <thing>` greps all nine inventories in
one call and prints the row without opening a note. A miss prints the code-search fallback; record
the row when you find it, in the same change.

**What earlier sessions learned** is in [`.claude/memory/INDEX.md`](.claude/memory/INDEX.md) —
in-repo and tracked, so it survives a clone. Write memories there, never to a machine-local store.
What may and may not be written: [STRUCTURE.md](docs/STRUCTURE.md).

Where **new** material belongs: [STRUCTURE.md](docs/STRUCTURE.md).

The `.claude/notes/` inventories are generated. **Edit the affected rows in the same change as every
insertion or deletion** — screen, route, API path, image, colour, font, token, scheme, target. A full
rescan is the user's **`/sync-app-notes`** command; never start one yourself.

## 6. Concurrency

These rules assume the strict-concurrency language mode recorded in
[PROJECT.md](.claude/notes/PROJECT.md). On an older mode they still hold; the compiler just stops
enforcing them for you.

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

**Accessibility — a requirement, not polish.** **Never encode meaning in color alone.** Mostly
guaranteed inside components → [DesignSystem.md](docs/modules/DesignSystem.md); what a screen must
still prove, and the sizes to prove it at, is the checklist in [DONE.md](docs/DONE.md).

**Security & privacy** — ATS enforced, no arbitrary loads. **Certificate pinning off by default**;
opt in per product only with a rotation plan and kill switch. No PII, tokens, or bodies in logs →
[LoggingKit.md](docs/modules/LoggingKit.md). Secrets to Keychain only →
[StorageKit.md](docs/modules/StorageKit.md). `PrivacyInfo.xcprivacy` current **per package**,
including required-reason APIs. Biometrics behind `BiometricAuthenticating`.

---

## 9. Testing

- Unit-test every view model, mapper, and service against protocol mocks. **No network** — enforced
  by mandatory `testValue` on every dependency key.
- **Snapshots are bounded on purpose:** full matrix for DesignSystem components; screens get
  `loaded` + one failure state → [DesignSystem.md](docs/modules/DesignSystem.md)
- Contract tests per wrapper — real implementation and mock satisfy the same suite.
- Localization test: no `.xcstrings` key missing in any language, no view using a raw literal.
- **Every package builds and tests standalone** with `swift test`. That is what keeps boundaries
  honest now that repo walls don't.

---

## 10. Conventions

Naming, file layout, access control, and doc comments: [CONVENTIONS.md](docs/CONVENTIONS.md),
enforced by [`.swiftlint.yml`](.swiftlint.yml) and `./Scripts/check.sh`.

Three that are rules, not conventions:

- **`public` only what crosses a package boundary** — in an extracted package every `public` symbol
  is a semver commitment.
- **Every function or initialiser you write or change carries a `///` doc comment** stating what
  the signature cannot.
- **Doc comments, not meta comments.** No `//` that restates the code or narrates the edit; anything
  about the change belongs in the commit message.

---

## 11. Finishing a change

**Read [DONE.md](docs/DONE.md) before saying a change is done**, or run `/verify` to walk it against
the diff. Do not declare completion from memory of the checklist — the items most often missed are
the ones that feel already handled.

If something can't be checked here (device, VoiceOver, Mac resize), **say what was skipped**.
Silently omitting it is the failure that checklist exists to prevent. Build and test: `/build`.

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
