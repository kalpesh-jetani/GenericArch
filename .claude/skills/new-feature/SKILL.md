---
name: new-feature
description: Scaffold a new feature package in the GenericArch single-repo architecture (iOS 17 / macOS 26.6, SwiftUI, Swift 6 strict concurrency). Use when asked to add a feature, add a screen, create a new module or package, scaffold FeatureX, or "start the auth/home/settings feature". Enforces the ask-first decisions (presentation pattern, persistence engine, caching policy), the Packages/Features layout, localized keys, all ContentState cases, protocol+mock pairs, and the feature's own .md doc. Do NOT use for editing an existing feature, adding a single endpoint or view to one that already exists, or for infrastructure packages (NetworkKit, StorageKit, DesignSystem) — those follow their own module docs.
---

# New feature

Creates a feature package that satisfies CLAUDE.md §3 *Scalable*: adding it edits **zero** other
features, one line in the composition root, and one case in `Route`.

## 1. Ask before writing — do not skip

CLAUDE.md §0. Check `docs/DECISIONS.md` first; if the feature already has a row, follow it and
don't re-ask.

Otherwise ask, in one message, with recommendations:

| Question | Options |
|---|---|
| **Presentation pattern** | MVVM + `@Observable` *(default)* · View-owned state (trivial screens only) · Other |
| **Persistence** | Only if the feature stores data: SwiftData · Core Data · SQLite/GRDB · Other · **Skip** |
| **Caching / offline** | Only if it fetches: Network-only · Cache-then-network · Offline-first · Skip |

While the question is open, do the answer-independent work: domain models, protocol definitions,
localization keys. Do not write view models or views yet.

Record answers in `docs/DECISIONS.md` under *Per feature*.

## 2. Layout

A **local package** under `Packages/Features/Feature<Name>/` (CLAUDE.md §4.1). Not a repo — don't
propose extracting it; feature packages fail all three §4.2 tests by definition.

```
Packages/Features/Feature<Name>/
  Package.swift
  Feature<Name>.md              required — see step 6
  Sources/Feature<Name>/
    Models/                     domain types, Sendable value types
    Services/                   protocols + live impls (actors or Sendable structs)
    ViewModels/                 @MainActor, exposes ContentState<T>
    Views/                      SwiftUI only, zero raw values, zero raw strings
    Localization/               <Feature>.xcstrings + generated L10n accessors
    DI/                         <Name>Assembly.swift — the ONLY file seeing DIContainer
  Tests/Feature<Name>Tests/
```

`Package.swift`: `platforms: [.iOS(.v17), .macOS("26.6")]`. Wired with `.package(path:)` to `Core`,
`DesignSystem`, `Navigation`, and the infrastructure it actually uses. **Never on another feature**
(§2.1) — the manifest is what enforces that now, so get it right.

Register it in the app targets' package list ([PROJECT.md](../../notes/PROJECT.md)).

## 3. What to produce — not just the happy path

For every capability: **protocol + mock + live implementation**. The mock ships in the package,
for tests *and* previews.

For every screen:
- A view model exposing `ContentState<T>` from Core — no ad-hoc `isLoading` flags.
- All six states rendered via `ContentStateView` (DesignSystem.md): idle, loading (skeleton),
  loaded, empty, offline, failed.
- **Paged list?** `ContentState<Paged<Item>>`, and render the footer states too. A failed page must
  never blank the rows already loaded (Core.md).
- Empty and error copy as **localized keys**, `<feature>_<screen>_<element>_<role>`
  (LocalizationKit.md).
- Errors mapped to `AppError` with `isRetryable` set deliberately.

Messages, confirmations, and permission rationales go through `MessagePresenting`
(Messaging.md). Never `.alert`.

## 4. Wiring

```swift
// DI/<Name>Assembly.swift — the seam. Nothing else in the feature sees the container.
public struct AuthAssembly {
    public static func loginViewModel(_ c: DIContainer) -> LoginViewModel {
        LoginViewModel(auth: c[AuthenticatingKey.self],
                       presenter: c[MessagePresentingKey.self])
    }
}
```

Then: one `Route` case, one line in the shell's `navigationDestination` switch. That's the whole
integration surface.

## 5. Tests

- Every view model and mapper, against mocks. No network (DIKit.md `testValue`).
- Previews per screen covering every `ContentState`. **Snapshots are bounded** (CLAUDE.md §9):
  screens snapshot `loaded` + one failure state; the full light/dark × RTL × XXXL matrix belongs to
  DesignSystem components, which every screen inherits.
- Package builds and tests **standalone** — `swift test --package-path Packages/Features/Feature<Name>`,
  no app. Repo walls no longer enforce boundaries; this does.

## 6. The feature's own doc — required

`Feature<Name>.md` in the package directory (CLAUDE.md §5), opening with the standard three lines:

```markdown
# Feature<Name>

- **Package:** `Packages/Features/Feature<Name>` (local)
- **Used by:** the app shell only (features never import each other)
- **When to read this:** <the specific screens/flows this owns>
```

Then: screens and their routes, services and their protocols, decisions taken (link the
`DECISIONS.md` rows), and anything non-obvious about the flow. **No CLAUDE.md edit** — the module
index gets one row, nothing more.

## 7. Before calling it done

Run DONE. The ones missed most often here: every `ContentState` implemented, no raw
string literal in a view, mocks provided, the feature's `.md` written, and the new rows added to
`.claude/notes/FEATURES.md` and `NAVIGATION.md` — targeted edits, not a `sync-app-notes` run.
