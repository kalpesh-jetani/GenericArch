# CLAUDE.md — Generic Apple Platform App Architecture

Reference architecture for **iPhone / iPad / Mac** from one codebase. Every package must be
reusable, replaceable, and droppable into a new product with minimal change.

**Session material only.** Setup, build, ship, project settings, packages — none of it is here.
**Before any task that is not writing code, grep the map** (§5): it routes all of them, and a topic
missing there is one to ask about, not improvise. A failed script writes its own report to
`.genericarch/failures/` — read that, never the script.

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
| **Extracting a package to a repo** | Only when all three §4 tests pass |
| **Deployment floors** | Before writing any `platforms:` line — never defaulted (§1.1) |

Ask **once per feature**, not once per file. Say so in the question if the answer would change the
module graph or a §2 rule. Don't start while the question is open — do the answer-independent work
first (models, protocols, localization keys), then ask.

---

## 1. Stack

**Never quote a version from memory or from this file.** Every version is acquired, never assumed:
min iOS, min macOS, Xcode, Swift and language mode live in
[PROJECT.md](.claude/notes/PROJECT.md), and how they are resolved and set is
[PROJECT-SETTINGS.md](docs/PROJECT-SETTINGS.md).

Fixed by **choice**, not detection — a divergent answer changes what §2 and the module docs apply
to, and `/project-init` names what it invalidates:

- **SwiftUI.** UIKit/AppKit only behind a `Representable`, only where SwiftUI genuinely cannot.
- **macOS is a native SwiftUI target. No Mac Catalyst.**
- **SPM for dependencies and project files** — nothing else, and no checked-in binary framework
  ([PROJECT-SETTINGS.md](docs/PROJECT-SETTINGS.md)).
- **async/await + structured concurrency.** No completion handlers, no Combine in new code, no
  `DispatchQueue` hopping.
- **Swift Testing** (`import Testing`). XCTest only for UI tests.

### 1.1 The asymmetric baseline — read before writing shared code

The Mac floor sits many OS generations above the iPhone floor. **Shared code compiles against the
lower one**, so a newer API breaks the iOS build even where the Mac target would accept it.

- Reach a newer API with `#if os(macOS)` or `if #available` **plus a working fallback**. Never both
  silently, and **never by raising a floor** — gate it or don't ship it.
- The gate lives **inside a DesignSystem component or an infrastructure wrapper**. A feature must
not
  know which OS it is on.
- Until the cross-floor look-and-feel question ([DECISIONS.md](docs/DECISIONS.md) *Open*) is
  answered, DesignSystem tokens stay platform-neutral.

Where the floors come from, and why "no `platforms:` line" means unanswered rather than missing:
[PROJECT-SETTINGS.md](docs/PROJECT-SETTINGS.md).

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
15. **Never delete an installed file with `rm`.** `./Scripts/ga-remove.sh <path> --reason "…"`
    records the tombstone that stops the next install re-creating it and the DECISIONS row that
    stops it being re-proposed. Any command that rewrites installed files closes with
    `./Scripts/ga-reseal.sh --apply`.

---

## 3. Architecture principles

**Protocol-oriented** — every capability is a protocol first, implementation second. Defaults in
protocol extensions, never base classes. Abstract on *capability*, not type (`ImageCaching`,
`TokenRefreshing`). Generics where they remove casting; `any P` at composition boundaries.

**Modular** — one responsibility per package; if it needs a `// MARK: - Unrelated`, split it.
Dependency direction is strictly downward, and **`Package.swift` enforces it, not repo walls** — a
local package still cannot import a sibling feature.

Downward is: app shell (thin) → features (never each other) → DesignSystem · Navigation →
infrastructure → `Core` (zero dependencies). The two extracted packages —
`GenericArch-NetworkKit`, `GenericArch-ImageCache` — sit outside it and map in at our boundary like
any vendor (§7).

**Inheritable** — a new feature gets standard behavior free and can override any piece, through a
**protocol + extension** supplying state handling, error mapping, retry, lifecycle. **No generic
base classes.** Prefer composition wherever both work.

**Scalable** — adding a feature edits zero other features: one local package, one line in the
composition root, one `Route` case. Use `/new-feature`.

---

## 4. Repository

### 4.1 Single repo, two extracted packages

Local packages wire with `.package(path:)` and carry **no version numbers**. The two extracted
packages have zero dependencies and neither imports `Core`.

### 4.2 When to extract — all three must be true

**Product-independent · actually reused · stable API.** Otherwise keep it local. It is a §0
question.

Both in full — and `Package.swift` as the enforcement, not convention:
[Packages/CLAUDE.md](Packages/CLAUDE.md).

---

## 5. Index

**Look it up before you read or search for it.** Three greps replace a table of contents:

```bash
grep -i navigation .claude/MAP.tsv     # which doc, note, pattern or skill covers a topic
grep -i lint .claude/SCRIPTS.tsv       # which script does this, and its contract
./Scripts/find.sh SmartLockHomeView    # where is this screen/route/endpoint/asset/token?
./Scripts/ga-step.sh show              # which step is next, and why a command refused
```

Commands run in a fixed order — install → `/project-init` → `/gaps` → `/sync-app-notes` → ready —
enforced by each command's first step. Exit 5 means an earlier one has not run →
[SEQUENCE.md](docs/SEQUENCE.md).

[`MAP.tsv`](.claude/MAP.tsv) carries every doc, note, pattern and skill; **read the module doc
before
touching a module.** [`SCRIPTS.tsv`](.claude/SCRIPTS.tsv) is each script's contract — **never read a
script's body to learn what it does**; read it only when a call fails, then fix it in the same
change.

**What earlier sessions learned:** [`.claude/memory/INDEX.md`](.claude/memory/INDEX.md) — in-repo
and tracked, so it survives a clone. Never write to a machine-local store. What may be written, and
where **new** material belongs: [STRUCTURE.md](docs/STRUCTURE.md).

Both indexes are pruned per install, so **a row that is not here may still exist upstream** —
declined, or a layer this product did not take. Check `.genericarch/TOMBSTONES.tsv` before
concluding
something does not exist ([INSTALL-MANIFEST.md](docs/INSTALL-MANIFEST.md)).

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
does, and **swapping a vendor must touch exactly one target.** **Our** types at the boundary; no
vendor enum or error crosses it.

What a wrapper ships and how to remove one: [Packages/CLAUDE.md](Packages/CLAUDE.md) §7,
[wrapper](docs/patterns/wrapper.md).

---

## 8. Multiplatform, accessibility, security

**Adaptivity** — branch on **size class and platform capability**, never device model or width
constants; navigation state is data → [Navigation.md](docs/modules/Navigation.md). `#if os(...)`
lives **inside DesignSystem components**, not features. Which iPad and Mac affordances a screen must
prove: [DONE.md](docs/DONE.md).

**Accessibility — a requirement, not polish.** **Never encode meaning in color alone.** Mostly
guaranteed inside components → [DesignSystem.md](docs/modules/DesignSystem.md); what a screen must
still prove, and at which sizes, is the checklist in [DONE.md](docs/DONE.md).

**Security & privacy** — two rules apply while writing code: **no PII, tokens or response bodies in
logs** → [LoggingKit.md](docs/modules/LoggingKit.md), and **secrets to the Keychain only**, behind a
protocol → [StorageKit.md](docs/modules/StorageKit.md). Everything else here is configuration — ATS,
pinning, `PrivacyInfo.xcprivacy`, biometrics, capabilities:
[PROJECT-SETTINGS.md](docs/PROJECT-SETTINGS.md).

---

## 9. Testing

**No network in tests** — enforced by the mandatory `testValue` on every dependency key. **Every
package builds and tests standalone**; that is what enforces the module boundaries.

Mocks, contract tests, snapshot bounds, the localization test:
[Packages/CLAUDE.md](Packages/CLAUDE.md) §9.

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
resize), **say what was skipped**.

Building it is a separate process with its own rules about who runs what:
[BUILD-PROCESS.md](docs/BUILD-PROCESS.md).

---

## 12. For Claude specifically

- **Never edit this file without explicit approval** — including when certain. Show the exact text
  and wait. Where new guidance belongs instead: [STRUCTURE.md](docs/STRUCTURE.md).
- **An existing repo's structure wins.** Never propose this layout for a repo that has one, and
  never install the architecture layer on your own initiative — in a repo that has not adopted
  §2/§3,
  `new-feature` scaffolds what the app cannot consume and `/review` reports rules it declined.
  `/project-init` offers them once the conflict table is settled.
- Read the relevant `Package.swift` before adding a dependency edge. If it violates §3's direction,
  stop and say so rather than adding it.
- When asked for a feature, produce **protocol + mock + implementation + localized keys + every
  content state** — not just the happy path.
- If a requirement conflicts with a §2 rule, or §0 has no recorded answer, **raise it** — don't
  silently work around it, and don't choose the scope of a broad instruction yourself (§2.14).
