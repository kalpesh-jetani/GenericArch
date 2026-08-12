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

| Feature | Repo | Screens | Route cases | Presentation pattern | Decision row |
|---|---|---|---|---|---|
| — | — | — | — | — | — |

<!-- Example row, delete when the first real feature lands:
| Auth | `GenericArch-FeatureAuth` | LoginView, ForgotPasswordView, OTPView | `.authLogin`, `.authForgot`, `.authOTP` | MVVM + @Observable | DECISIONS.md 2026-08-12 |
-->

## Screens

One row per screen. `States` records which `ContentState` cases the screen actually renders —
a screen missing one is a CLAUDE.md §2.5 violation, and this table is where that shows up.

| Screen | Feature | Route | View model | States implemented | Localization prefix |
|---|---|---|---|---|---|
| — | — | — | — | — | — |

<!--
| LoginView | Auth | `.authLogin` | LoginViewModel | idle, loading, loaded, failed | `auth_login_` |
-->

## Orphans & gaps

Things `/sync-app-notes` flags rather than silently omitting:

- Screens with no `Route` case (unreachable except by direct construction).
- `Route` cases with no screen (dead deep links).
- Screens missing an `empty` or `offline` state.
- Features with no `Feature<Name>.md` (CLAUDE.md §5).

| Finding | Where | Noted |
|---|---|---|
| — | — | — |
