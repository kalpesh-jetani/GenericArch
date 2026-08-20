# Choosing the architecture — the notes to read before scaffolding

For a **new** repo. `Scripts/ga-scaffold.sh` asks these; this file is what the answers mean, so the
question is a decision rather than a guess. Each one is recorded in `docs/DECISIONS.md` and stops
being asked.

An existing repo answers none of this — it already has answers, and `/project-init` reconciles them.

---

## 1. Which layers exist on day one

Everything here can be added later; nothing here is free. A package that exists before it has content
is a directory people put things in because it is there.

| Group | Scaffold flag | Take it on day one when | Skip it when |
|---|---|---|---|
| **Core + DIKit** | always | — | never — this is the floor |
| **Navigation** | `--with navigation` | More than one screen, or any deep link | A single-screen tool |
| **DesignSystem** | `--with design` | Two screens will share a token, or you ship both iOS and Mac | Prototype with system styling |
| **Authentication** | `--with auth` | Sign-in is in the first release | Auth is later — the notes file is worth reading anyway |
| **Storage** | `--with storage` | Anything survives a launch | Read-only client |
| **Messaging** | `--with messaging` | You will show more than one alert | Genuinely no error surfaces yet |
| **Networking** | `--with networking` | Any remote call — brings the module doc, not code: `GenericArch-NetworkKit` is a versioned package you add to `Package.swift` | Fully local app |

**Recommended for a typical app:** `--with navigation,design,storage,messaging,networking`. Add
`auth` when sign-in is actually in scope.

## 2. Presentation pattern

Asked before *every* feature, not once — but the default is set here.

| Option | Take it when | Cost |
|---|---|---|
| **MVVM with `@Observable`** *(recommended)* | The screen has state worth testing without a UI | One extra type per screen |
| View-owned state | The screen is genuinely trivial — a static list, an about page | Grows into MVVM badly if it was the wrong call |
| Reducer / TCA | — | **Recorded as rejected** in this architecture: it moves the shape of every screen into a dependency (`docs/DECISIONS.md`) |

The rule that makes this matter: §3 promises a new feature gets standard behaviour free. That only
holds if screens share a shape.

## 3. Persistence engine

Only if something is stored. Behind a protocol either way, so the choice is reversible.

| Option | Take it when | Cost |
|---|---|---|
| **SwiftData** | New app, model-shaped data, and a floor recent enough for it — check yours, §5 | Migration story is younger than Core Data's |
| Core Data | You need mature migrations, or a team that knows it | More ceremony, more to get wrong |
| SQLite direct | Query-shaped work, or you already own the schema | You are writing the mapping layer yourself |
| Files / Codable | A handful of documents | Not a database; do not let it become one |

Secrets never go here — Keychain, through `SecretStoring`.

## 4. Caching and offline

Asked for any screen that fetches. Decide the shape once:

- **Network-only** — simplest, and honest for a dashboard. Every screen needs an offline state anyway.
- **Read-through cache with a TTL** *(recommended default)* — one policy in one place, features unaware.
- **Offline-first with a sync queue** — a product decision, not a technical one. It changes every
  write path in the app, so it is not something to discover halfway.

## 5. Deployment floors — nothing writes these for you

The scaffold writes **no `platforms:` line** unless this repo already answers the question, and it
never invents one. An SDK version is not a deployment floor: it says what you can build with, never
what you must support, so the machine cannot answer it either.

```bash
./Scripts/detect-toolchain.sh --markdown    # a `project` source is an answer; `machine` is not
```

- **Answered already** (a `Package.swift` carries `platforms:`) — every package the scaffold creates
  gets the same numbers, and `check.sh` fails when they drift apart.
- **Not answered** — the manifests carry a comment instead of a line, and `Packages/FLOORS.md`
  explains the asymmetry that decides the numbers. Choose, record with `/decide`, then delete it.
- **You already know** — pass them: `--ios 18 --macos 15.0`.

A floor a tool picked compiles today, fails on the first shared-code change, and by then reads as a
decision somebody made. That is why there is no default here.

## 6. Platforms on day one

| Choice | What it changes |
|---|---|
| **iOS only** | Nothing is gated. Adding Mac later means auditing every view for `#if os` gaps |
| iOS + macOS *(what this architecture is written for)* | Shared code compiles to the **iOS** floor; Mac-only APIs are gated inside DesignSystem components. Costs discipline from day one, and saves an audit later (CLAUDE.md §1.1) |

Mac Catalyst is not an option here — it is recorded as rejected.

---

## What the scaffold does not decide

- **Bundle ID, Team ID, product name** — asked by `/project-init`.
- **The languages you ship** — asked by `/project-init`; every string is a localized key from the
  first screen either way.
- **Your Xcode project file.** The scaffold creates packages, docs and shells. `.xcodeproj` is yours
  to create — SPM is the source of truth for dependencies, and nothing here generates project files
  (no Tuist, no XcodeGen — recorded).
