---
name: new-feature
description: Scaffold a new screen, feature package or module from nothing. Fires on "create a new screen", "scaffold FeatureX", "new feature package", "start the settings module".
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

Offer `/learn <pattern>` if it is now worth promoting.

Creates a feature package that satisfies CLAUDE.md §3 *Scalable*: adding it edits **zero** other
features, one line in the composition root, and one case in `Route`.

## 0. Run the scripts first — in this order

**Every step below has a script. Call it; do not re-derive its answer by reading files.**
`.claude/SCRIPTS.tsv` is the contract — path, inputs, outputs, exit codes. Read a script's
*body* only when a call fails, then fix it in the same change.

```bash
grep -i -e feature -e lint -e audit .claude/SCRIPTS.tsv   # 1. which script covers this
./Scripts/find.sh <ScreenOrRoute>                         # 2. does it already exist?
./Scripts/claude-utils/init-claude-env.sh --list          # 3. is the project registered?
./Scripts/claude-workflows/run-task.sh <proj> <task> status  # 4. if installed: task already open?
```

Order matters: **2 before 3** (an existing screen means this is `change`, not scaffolding), and
**4 before any phase** (resuming beats restarting — the artifacts are already on disk).

If no script covers a step you end up doing by hand more than once, say so and offer
`/learn --script` — it captures the sequence as a registered script for next time.

## 1. Match an existing feature's shape

`FEATURES.md` gives the structure, state handling and file layout of every feature that already
exists; `CONVENTIONS.md` gives the naming. **Reuse the shape you find** — if one already handles the
same content states, follow it rather than inventing a second pattern.

On a miss, grep the codebase once and **record the row in `FEATURES.md` in this same change**. Why
that ordering pays: [PATTERN-SEARCH.md](../../../docs/PATTERN-SEARCH.md).

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

**Walk it as nine phases, and let the scripts hold them:**

```bash
./Scripts/claude-utils/init-claude-env.sh --list                    # once, per project
./Scripts/claude-workflows/run-task.sh <project> <task> 1 --text "<the request, verbatim>"
./Scripts/claude-workflows/run-task.sh <project> <task> status      # what ran, what is next
```

`Scripts/claude-workflows/` is optional — installed only with `adopt.sh --with-meta`. Absent, walk
the same nine phases by hand in the same order; the table below is the contract either way.

| Phase | Does | For a feature |
|---|---|---|
| 1 intake | classify, record the request verbatim | `--type feature --target <the doc you are writing>` |
| 2 locate | resolve the target, record git state | `Feature<Name>.md` (step 8), or CLAUDE.md for a rule |
| 3 audit | sections, symbols, links, duplicates | pair with `./Scripts/find.sh` and the notes (§1) |
| 4 plan | validate every edit, flag cross-refs | `04-outline.md` **is** the action list you show |
| 5 edit | apply — backed up, all-or-nothing | **refuses without `--approve`** |
| 6 verify | front matter, tables, links, lint | |
| 7 test | extract snippets, check symbols exist | prints `swift test …`, runs nothing (§2.12) |
| 8 present | diff, summarised per section | |
| 9 commit | compose a tagged message | emits a script; never commits (§2.11) |

**Approve · Improve · Auto** are the phase 4→5 gate: approve is `5 --approve`, improve is re-running
`4` with corrected `--edit` specs, auto is `all --approve`. Show `04-outline.md` before you ask.

Artifacts live in `.claude/claude-tasks/<project>/<task>/` — untracked working state, one
file per phase, deleted by `clean --yes` when the feature ships. Full reference:
[CLAUDE-TASKS.md](../../../docs/CLAUDE-TASKS.md).

The phases live in the scripts, not here. Steps 4–9 below are the Swift substance those phases
carry — the pipeline sequences the work, it does not replace it.

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

**Read [Packages/CLAUDE.md](../../../Packages/CLAUDE.md) once before the first package** — it carries
the scoped detail behind §4, §7 and §9 that the root file only summarises.

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
- Previews per screen covering every `ContentState`.
- Hand over `swift test --package-path Packages/Features/Feature<Name>` — the user runs it (§2.12).
  Standalone package tests are what enforce the module boundaries.

Snapshot scope and the rest of the bar: [DONE.md](../../../docs/DONE.md).

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

Run [DONE.md](../../../docs/DONE.md), or `/verify`. Missed most often here: every `ContentState`
implemented, the feature's `.md` written, and rows added to `FEATURES.md` and `NAVIGATION.md` —
targeted edits, never a `/sync-app-notes` run. Then `feature-complete` closes it out.
