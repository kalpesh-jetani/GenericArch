# Navigation Flow

Every `Route` case, what presents it, and how the user gets there.

**Read it when** adding a screen, wiring a deep link, or checking whether a flow is
  reachable.
- **Design rules:** [Navigation.md](../../docs/modules/Navigation.md). This file is the
  *inventory*; that file is the *rules*.

> Empty until `Packages/Navigation` and the first feature exist. `/sync-app-notes` populates it
> from the `Route` enum and the shell's `navigationDestination` switch.

---

## Route inventory

**Every row carries the path to the file.** These notes are an index — `grep` a route case here and
you get the file that defines it and the file that renders it, without opening the project.

| Route case | Payload | Defined in — *what's there* | Rendered by — *what's there* | Entry points | Deep link |
|---|---|---|---|---|---|
| — | — | — | — | — | — |

<!--
| `.authLogin` | — | `Packages/Navigation/Sources/Navigation/Route.swift:12` — the case declaration | `Packages/Features/FeatureAuth/Sources/FeatureAuth/Views/LoginView.swift` — email/password form, owns field state | cold launch (signed out), sign-out | `app://auth/login` |
| `.itemDetail(id:)` | `Item.ID` | `Packages/Navigation/Sources/Navigation/Route.swift:15` — the case, payload is the item id | `Packages/Features/FeatureHome/Sources/FeatureHome/Views/DetailView.swift` — detail screen, loads by id, all six states | feed tap, push, Spotlight | `app://item/{id}` |
-->

**Never write a bare path.** Every path carries a short note saying what is there — a path answers
*where*, not *what*, and without the note a reader has to open every hit to find the right one.
One clause is enough.

Paths are repo-relative and unquoted-greppable. A `:line` suffix on `Defined in` points at the
`case` itself; omit it rather than let it go stale — a wrong line number is worse than none.

`Entry points` matters more than it looks: a route with exactly one entry point is a candidate for
inlining; a route with none is dead code.

## Flow

Node ids are the route cases. **Each node carries a `click` target — the file that renders it, plus a
tooltip saying what that file is.** That makes the diagram greppable text rather than a picture, and
keeps the path from appearing without an explanation.

```mermaid
graph TD
    Launch --> AuthCheck{Signed in?}
    AuthCheck -- no --> authLogin[".authLogin"]
    AuthCheck -- yes --> homeFeed[".homeFeed"]
    authLogin --> homeFeed
    homeFeed --> itemDetail[".itemDetail(id:)"]
    homeFeed --> settings[".settings(section:)"]

    click authLogin  "../../Packages/Features/FeatureAuth/Sources/FeatureAuth/Views/LoginView.swift" "Login form — email/password, owns field state"
    click homeFeed   "../../Packages/Features/FeatureHome/Sources/FeatureHome/Views/FeedView.swift" "Paged feed — ContentState<Paged<Item>>"
    click itemDetail "../../Packages/Features/FeatureHome/Sources/FeatureHome/Views/DetailView.swift" "Item detail — loads by id"
    click settings   "../../Packages/Features/FeatureSettings/Sources/FeatureSettings/Views/SettingsView.swift" "Settings — sectioned, no remote data"
```

<!-- The example above is illustrative; replace it wholesale on the first real route.
     Regenerate whenever a route is added or removed, and keep every `click` line — they are what
     make the graph findable by grep. Real edges only; an aspirational flow chart is worse than none. -->

## Container structure

| Size class | Container | Root selection |
|---|---|---|
| Compact (iPhone, Slide Over) | `NavigationStack(path:)` | — |
| Regular (iPad, Mac) | `NavigationSplitView` | sidebar `selectedRoot` |

Branching is on **size class only** — never device model, never width constants
([Navigation.md](../../docs/modules/Navigation.md)).

## Deep links

| URL pattern | Parses to | Parser — *what's there* | Requires auth | Fallback if unauthorized |
|---|---|---|---|---|
| — | — | — | — | — |

<!--
| `app://item/{id}` | `[.homeFeed, .itemDetail(id:)]` | `Packages/Navigation/Sources/Navigation/DeepLinkParser.swift:34` — the pattern match; pure, no side effects | yes | `.authLogin` |
-->

Parsing is pure and total; authorization is checked after, in the shell. An unparseable link lands
on a sensible root — never a blank screen, never a system alert.

## Scenes & windows

| Scene | Platform | Declared in — *what's there* | Owns its own Router | Restoration |
|---|---|---|---|---|
| — | — | — | — | — |

<!--
| Main | iOS | `App/GenericArch-iOS/GenericArchApp.swift:18` — the WindowGroup and composition root | yes | `@SceneStorage("nav.path")` |
-->

Each scene owns its own `Router` — a shared one makes two windows fight over one path.

## Using this as an index

```bash
# a route case → the file that declares it and the file that renders it, each with its note
grep -n "itemDetail" .claude/notes/NAVIGATION.md

# every file the graph touches, deduped — for a refactor's blast radius
grep -o '[A-Za-z/]*\.swift' .claude/notes/NAVIGATION.md | sort -u

# the whole node → file map, tooltips included, so each path arrives explained
grep -n "click " .claude/notes/NAVIGATION.md
```

If a path in here does not exist, the note is stale — that is a `Gaps` row, not something to ignore.

## Gaps

| Finding | Where | Noted |
|---|---|---|
| — | — | — |

`/sync-app-notes` flags: routes with no `navigationDestination` case, screens reachable only by
direct construction, deep links with no matching route, and any feature constructing another
feature's view (CLAUDE.md §2.1).
