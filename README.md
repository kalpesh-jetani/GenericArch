# GenericArch

Reference architecture for building **iPhone / iPad / Mac** apps from one shared codebase.

This repo is the blueprint. Every package in it is meant to be reusable, replaceable, and droppable
into a new product with minimal change.

**The stack is acquired, not imposed.** `./Scripts/detect-toolchain.sh` reads it from your project's
settings where they exist, falls back to your machine, and `/project-init` asks about the rest with
options derived from your installed Xcode — recommending the latest, never assuming it. This repo's
own resolved answers are SwiftUI, Swift 6 language mode and SPM; yours can differ, and
`/project-init` will tell you which rules that changes.

---

## Install

Three ways in. Pick the row that matches what you have — all of them are non-destructive:
**nothing overwrites your `CLAUDE.md`, your skills, or your commands.**

| You have | Use | You get |
|---|---|---|
| Nothing yet | **Template repo** | Everything: rules, docs, tooling, starter packages |
| An existing app | **`install.sh`** | Rules, docs and tooling — your code and your rules untouched |
| Several repos | **Plugin** | Only the skills and commands, updated centrally |

---

### A. New project — from the template

```bash
gh repo create <you>/MyApp --template kalpesh-jetani/GenericArch --private --clone
cd MyApp
```

Then, in Claude Code:

```
/project-init MyApp
```

It asks for what it cannot infer — bundle ID, Team ID, the languages you ship at v1, which rules you
want as *hard* vs *base*, and which permissions to allow. Nothing is written before you answer.

**Then reset the state you inherited.** A template copies this product's answers along with the
structure, and they are not yours:

```bash
./Scripts/detect-toolchain.sh   # your machine sets the baseline, not this repo's
```

- `docs/DECISIONS.md` — delete the per-product rows, keep the toolchain ones
- `docs/GAPS.md` — reset statuses to ▶ Open, then run `/gaps`
- `.claude/notes/*` — clear the table bodies; they describe *this* app's screens and assets

### B. Existing project — from inside your repo

```bash
curl -fsSLO https://raw.githubusercontent.com/kalpesh-jetani/GenericArch/v0.1.0/install.sh
less install.sh          # short, and it tells you what it will do
bash install.sh          # dry run — lists every file it would add
bash install.sh --apply
```

<details>
<summary>One-liner, if you already trust the source</summary>

```bash
curl -fsSL https://raw.githubusercontent.com/kalpesh-jetani/GenericArch/v0.1.0/install.sh | bash -s -- --apply
```
</details>

It pins to a tag, records what it installed in `.genericarch-version`, reports every collision
instead of resolving it, and **never writes `CLAUDE.md`**. Then:

```
/project-init          # reads YOUR CLAUDE.md, lists rule conflicts, asks one by one
/gaps                  # works out what you already have from your code, without asking
./Scripts/check.sh     # expect failures on an existing codebase — that is the point
```

Your rules win by default. For a hard conflict — CocoaPods vs SPM, UIKit vs SwiftUI — the usual
answer is *adopt for new code only*, because a codebase that already violates a rule cannot adopt it
by editing a doc ([docs/ADOPTION.md](docs/ADOPTION.md)).

| Override | Effect |
|---|---|
| `GA_REF=v0.2.0` | A different version |
| `GA_REPO=/path/to/checkout` | A local clone or your fork |

> If the repo is private, `curl` cannot reach it. Clone it once over SSH and run
> `./Scripts/adopt.sh /path/to/YourApp --apply` instead.

### C. Several repos — just the tooling

```
/plugin marketplace add kalpesh-jetani/genericarch-plugin
/plugin install genericarch
```

Skills and commands only. No rules, no docs, no code — so each product keeps its own `CLAUDE.md`,
and tooling fixes reach every repo by updating one plugin.

---

## What you just installed

### Skills — these fire on their own when the situation matches

You never type these. They activate from their description when what you are doing matches.

| Skill | Fires when | What it stops you doing |
|---|---|---|
| `new-feature` | Adding a feature or package | Shipping a happy path — it requires every content state, a mock, and localized keys |
| `style-guide` | Any spacing, radius, shadow or duration is about to be written | Adding a near-duplicate token; it proposes the existing one first |
| `dark-light-mode` | A colour or asset changes, or something looks wrong in dark | Shipping a colorset with no dark appearance, or elevation that vanishes on black |
| `rtl-support` | Adding a locale, or checking mirroring | `.left`/`.right` and `chevron.right`, which do not flip |
| `release-bump` | Releasing NetworkKit or ImageCache | Tagging in the wrong order, or misjudging the semver level |
| `feature-complete` | Work is called done | Closing without deciding whether the pattern is worth keeping |

### Commands — you type these

| Command | Use it to |
|---|---|
| `/project-init` | Set up a fresh repo, or adopt this into an existing one |
| `/verify` | Walk the Definition of Done against your working diff — reports, never fixes |
| `/gaps` | Decide what this architecture should and should not cover for your product |
| `/decide` | Record a settled decision so it is not re-argued |
| `/upgrade-stack` | Reconcile project settings with your machine — asks twice before changing anything |
| `/sync-app-notes` | Rebuild the inventories from a filesystem scan |
| `/build` | Build, test or archive a stage: `DEV`, `TEST`, `BETA`, `PROD` |

### Scripts — run these yourself or in CI

| Script | Does |
|---|---|
| `./Scripts/check.sh` | Enforces the rules a linter cannot express, **and** typechecks every package at the iOS floor — `swift build` on a Mac does not |
| `./Scripts/detect-toolchain.sh` | Reports the stack; `--markdown` emits the §1 table, `--options` the valid choices |
| `./Scripts/adopt.sh` | Copies the base into another repo, refusing to copy this product's state |
| `./Scripts/build-plugin.sh` | Generates the plugin from `.claude/` — never hand-edit the output |
| `./Scripts/check-skill-triggers.py` | Catches two skills competing for the same phrasing |

### Two rules the agent follows without being asked

- **`CLAUDE.md` is never edited without your explicit approval** — it loads into every session, so a
  change there alters every future response.
- **The note inventories are updated row by row** as part of a change; a full rescan only happens
  when you type `/sync-app-notes`.

---

## Start here

| You want to… | Read |
|---|---|
| Know the rules before writing code | [CLAUDE.md](CLAUDE.md) — rules, and the resolved stack |
| Understand a specific layer | [docs/modules/](docs/modules/) — one doc per package |
| Know why something is the way it is | [docs/DECISIONS.md](docs/DECISIONS.md) |
| Know what's deliberately missing | [docs/GAPS.md](docs/GAPS.md) |
| Set up a machine, or ship | [docs/REPO.md](docs/REPO.md), [docs/DELIVERY.md](docs/DELIVERY.md) |
| Know where a new doc belongs | [docs/STRUCTURE.md](docs/STRUCTURE.md) |

## Layout

```
CLAUDE.md            always-on rules (kept deliberately small)
Packages/            local Swift packages — Core, DIKit, DesignSystem, Features/…
App/                 thin iOS + macOS shells: @main, composition root, no logic
docs/                hand-written reasoning: module design + cross-cutting reference
docs/modules/        one doc per package
.claude/notes/       inventories generated from the code (features, routes, assets, fonts, schemes)
.claude/skills/      procedures Claude applies on its own
.claude/commands/    things you trigger: /project-init /verify /gaps /decide
                     /upgrade-stack /sync-app-notes /build
Scripts/check.sh     enforces the rules a linter can't express
```

Two packages are **not in this repo at all**. `GenericArch-NetworkKit` and `GenericArch-ImageCache`
are standalone, zero-dependency packages in their own repositories — add them to `Package.swift` when
a product needs them, and they resolve by version. Their source is never copied into a consuming
codebase ([docs/REPO.md](docs/REPO.md)).

## Build

```bash
swift build --package-path Packages/Core     # any package, standalone
swift test  --package-path Packages/Core
./Scripts/check.sh                           # rule enforcement
```

Apps build per stage — DEV / TEST / BETA / PROD ([.claude/notes/SCHEMES.md](.claude/notes/SCHEMES.md)):

```bash
xcodebuild -scheme GenericArch-DEV -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Working with Claude Code

The `.claude/` directory is set up so an agent gets the architecture without being told each time.
Four commands:

| Command | Does |
|---|---|
| `/project-init` | Initialize a fresh repo, or adopt this structure into an existing one — reconciles conflicting rules with approval first |
| `/verify` | Walk the Definition of Done against the working diff |
| `/gaps` | Triage [docs/GAPS.md](docs/GAPS.md) — derives status from code on an existing repo, asks on a fresh one |
| `/decide` | Record a settled decision in the log |
| `/upgrade-stack` | Reconcile project settings with the machine — asks twice before changing anything |
| `/sync-app-notes` | Rebuild the seven inventories from a filesystem scan |
| `/build` | Build, test, or archive a stage |

Skills fire on their own when the situation matches — `new-feature`, `style-guide`,
`dark-light-mode`, `rtl-support`, `release-bump`, `feature-complete`. That last one closes finished
work and can distil what it taught into a new skill, which then surfaces the next time similar work
starts. Commands only run when you type them. Anything that must **never**
trigger by inference is a command, which is why the full inventory rescan is `/sync-app-notes` and
not a skill.

Two standing rules the agent follows: **CLAUDE.md is never edited without explicit approval**, and
the note inventories are updated by targeted edit — never by an unrequested full rescan.

## Status

The architecture is documented and a vertical slice (`Core`, `DIKit`) builds and tests clean. Most
packages are specified but not yet implemented; [docs/GAPS.md](docs/GAPS.md) tracks what is
deliberately absent.
