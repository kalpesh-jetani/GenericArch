---
name: new-feature
description: Scaffold a new screen or feature package from nothing. Fires on "create a new screen", "scaffold FeatureX", "new feature package", "start the settings module". Enforces the ask-first decisions, the Packages/Features layout, localized keys, every ContentState case, protocol+mock pairs, and the package doc. For editing something that already exists, see docs/patterns/change.md.
---

# New feature

**Check this is really scaffolding before you start.** Six neighbouring concerns live in
`docs/patterns/` and are not promoted to skills in this repo yet — if the request is one of them,
say so and read the pattern instead of improvising:

| If it is really about | Read |
|---|---|
| Editing something that exists | [change](../../../docs/patterns/change.md) |
| Spacing, radius, tokens | [style-guide](../../../docs/patterns/style-guide.md) |
| Light vs dark | [dark-light-mode](../../../docs/patterns/dark-light-mode.md) |
| Mirroring or a locale | [rtl-support](../../../docs/patterns/rtl-support.md) |
| Tagging a package | [release-bump](../../../docs/patterns/release-bump.md) |
| Closing finished work | [feature-complete](../../../docs/patterns/feature-complete.md) |

Offer `/learn <pattern>` if it is now worth promoting. Scaffolding a package for a one-field change
is the mis-fire this table exists to catch.

Creates a feature package that satisfies CLAUDE.md §3 *Scalable*: adding it edits **zero** other
features, one line in the composition root, and one case in `Route`.

## 1. Search the notes first — token efficiency

**Before grepping the codebase, grep `.claude/MAP.tsv`, then read the note it points at:**

1. **FEATURES.md** — What features exist? What's their structure, state handling, and content-state pattern?
   - If a feature already handles similar states (loading, empty, error, loaded), use its pattern
   - Check the file paths — the naming, folder depth, and View/ViewModel/Model colocation
   - Zero grep if found in notes

2. **CONVENTIONS.md** — What's the naming pattern? (FeatureName, Feature<Name>, or other?)
   - How are View, ViewModel, and Models named?
   - File layout inside `Sources/Feature<Name>/`?

3. **If NOT found in notes** → grep for existing features, then record the pattern in FEATURES.md
   in the same commit as the new feature.

See [PATTERN-SEARCH.md](../../../docs/PATTERN-SEARCH.md) for the full token-efficiency approach.

## 2. Is there already a pattern for this?

A finished feature may have left a **derived skill** — a recorded sequence for building this kind of
thing (`feature-complete`). Check before scaffolding from scratch:

```bash
grep -l "Derived from" .claude/skills/*/SKILL.md
grep -H "^description:" $(grep -l "Derived from" .claude/skills/*/SKILL.md 2>/dev/null) 2>/dev/null
```

If one matches the work at hand, **offer it rather than assuming it applies**:

> `auth-screen-flow` was derived from FeatureAuth — pre-prompt → keychain write → route swap. This
> looks like the same shape. Follow it, or scaffold fresh?

Two cautions:

- **A derived skill records what was done once, not what is correct forever.** If it contradicts a
  rule in CLAUDE.md §2 or a module doc, the rule wins and the skill is stale — say so.
- If it half-fits, take the sequence and say which steps you are dropping. Silently deviating from a
  pattern you announced is worse than not offering it.

## 3. Ask before writing — do not skip

**Walk it as stages, and let the script hold them:**

```bash
python3 Scripts/feature-workflow.py start "<the feature>"
python3 Scripts/feature-workflow.py status     # the stage, what to gather, which tools to use
```

Input → Requirements → Resources *(skippable)* → Approaches → a bulleted action list → **Approve ·
Improve · Auto**. Each `status` names the tools for that stage; `record`, `skip --reason` and
`advance` move it on. The state file under `.claude/workflow/` shows what was decided versus what
was defaulted — which is the point of `--auto`. Delete it when the feature ships.

The stages live in the script, not here, so this file stays readable. Steps 3–9 below are what the
`requirements` and `approaches` stages draw on.

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

## 4. Layout

A **local package** under `Packages/Features/Feature<Name>/` (CLAUDE.md §4.1). Not a repo — don't
propose extracting it; feature packages fail all three §4.2 tests by definition.

```
Packages/Features/Feature<Name>/
  Package.swift
  Feature<Name>.md              required — see step 8
  Sources/Feature<Name>/
    Models/                     domain types, Sendable value types
    Services/                   protocols + live impls (actors or Sendable structs)
    ViewModels/                 @MainActor, exposes ContentState<T>
    Views/                      SwiftUI only, zero raw values, zero raw strings
    Localization/               <Feature>.xcstrings + generated L10n accessors
    DI/                         <Name>Assembly.swift — the ONLY file seeing DIContainer
  Tests/Feature<Name>Tests/
```

`Package.swift`: copy the `platforms:` line from a sibling package — never type a version from
memory (CLAUDE.md §1.1). Wired with `.package(path:)` to `Core`,
`DesignSystem`, `Navigation`, and the infrastructure it actually uses. **Never on another feature**
(§2.1) — the manifest is what enforces that now, so get it right.

Register it in the app targets' package list ([PROJECT.md](../../notes/PROJECT.md)).

## 5. What to produce — not just the happy path

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

## 6. Wiring

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

## 7. Tests

- Every view model and mapper, against mocks. No network (DIKit.md `testValue`).
- Previews per screen covering every `ContentState`. **Snapshots are bounded** (CLAUDE.md §9):
  screens snapshot `loaded` + one failure state; the full light/dark × RTL × XXXL matrix belongs to
  DesignSystem components, which every screen inherits.
- Package builds and tests **standalone** — hand over
  `swift test --package-path Packages/Features/Feature<Name>`; the user runs it (§2.12). Repo walls
  no longer enforce boundaries; this test does.

## 8. The feature's own doc — required

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

## 9. Before calling it done

Run [DONE.md](../../../docs/DONE.md). The ones missed most often here: every `ContentState` implemented, no raw
string literal in a view, mocks provided, the feature's `.md` written, and the new rows added to
`.claude/notes/FEATURES.md` and `NAVIGATION.md` — targeted edits, not a `/sync-app-notes` run.

Then `feature-complete` closes it out — and decides whether this build left a pattern worth keeping
as a skill, or just a note.
