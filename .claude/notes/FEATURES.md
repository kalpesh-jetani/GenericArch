# Features & Screens

Inventory of every feature package and the screens it owns.

- **Maintained by:** targeted edit on every insertion or deletion.
  A full rescan is the `/sync-app-notes` **command** — it runs only when you type it.
- **Read this when:** deciding where a screen belongs, checking whether a feature already exists,
  or tracing which package owns a route.
- **Source of truth:** the code. If this file and the code disagree, the code wins and this file
  is stale — fix it in the same change.

> Empty until the first feature package exists. `/sync-app-notes` populates it by scanning
> `Sources/Feature*/Views/` and each feature's `Route` cases.

---

## Features

**Every row carries the path.** This note is an index — `grep` a feature or screen here and you get
the file, without opening the project.

| Feature | Package path — *what's there* | Screens | Route cases | Presentation pattern |
|---|---|---|---|---|
| — | — | — | — | — |

<!-- Example rows, delete when the first real feature lands:
| Auth | `Packages/Features/FeatureAuth` — sign-in, OTP, password reset; doc at `FeatureAuth.md` | 3 | `.authLogin`, `.authForgot`, `.authOTP` | MVVM + @Observable |
| Home | `Packages/Features/FeatureHome` — paged feed and item detail; doc at `FeatureHome.md` | 2 | `.homeFeed`, `.itemDetail(id:)` | MVVM + @Observable |
-->

## Screens

One row per screen. `States` records which `ContentState` cases the screen actually renders —
a screen missing one is a CLAUDE.md §2.5 violation, and this table is where that shows up.

| Screen | View file — *what's there* | View model file — *what's there* | Route | States implemented | L10n prefix |
|---|---|---|---|---|---|
| — | — | — | — | — | — |

<!--
| LoginView | `Packages/Features/FeatureAuth/Sources/FeatureAuth/Views/LoginView.swift` — email/password form, owns field state | `Packages/Features/FeatureAuth/Sources/FeatureAuth/ViewModels/LoginViewModel.swift` — validation + sign-in call | `.authLogin` | idle, loading, loaded, failed | `auth_login_` |
| FeedView | `Packages/Features/FeatureHome/Sources/FeatureHome/Views/FeedView.swift` — paged list, pull-to-refresh | `Packages/Features/FeatureHome/Sources/FeatureHome/ViewModels/FeedViewModel.swift` — exposes ContentState<Paged<Item>> | `.homeFeed` | **all six + paging** | `home_feed_` |
-->

**Never write a bare path.** Each path carries a clause saying what is there — otherwise a reader
has to open every hit to find the one they want. Write paths in full: grep must resolve each to
exactly one file, so no `.../` abbreviations.

## Using this as an index

```bash
# a screen → its view, its view model, and a note on each
grep -n "LoginView" .claude/notes/FEATURES.md

# every Swift file this feature set owns, deduped — a refactor's blast radius
grep -o 'Packages/[A-Za-z/]*\.swift' .claude/notes/FEATURES.md | sort -u

# screens against the states they implement — the missing-state audit, without opening Xcode
awk -F'|' 'NF>5 {print $2, "→", $6}' .claude/notes/FEATURES.md
```

Cross-reference with [NAVIGATION.md](NAVIGATION.md): a screen here with no route there is
unreachable, and a route there with no screen here is dead.

A path in this file that does not exist on disk means the note is stale — that is a `Gaps` row.

## Orphans & gaps

Things `/sync-app-notes` flags rather than silently omitting:

- Screens with no `Route` case (unreachable except by direct construction).
- `Route` cases with no screen (dead deep links).
- Screens missing an `empty` or `offline` state.
- Features with no `Feature<Name>.md` (CLAUDE.md §5).

| Finding | Where | Noted |
|---|---|---|
| — | — | — |
