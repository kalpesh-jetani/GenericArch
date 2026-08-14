# GenericArch

Reference architecture for building **iPhone / iPad / Mac** apps usoing CLAUDE from one shared codebase.

This repo is the blueprint. Every package in it is meant to be reusable, replaceable, and droppable
into a new product with minimal change.

**The stack is acquired, not imposed.** `./Scripts/detect-toolchain.sh` reads it from your project's
settings where they exist, falls back to your machine, and `/project-init` asks about the rest with
options derived from your installed Xcode — recommending the latest, never assuming it. No version
number is written in `CLAUDE.md`: the floors live in each `Package.swift`, and
`.claude/notes/PROJECT.md` records what they resolved to. Your answers can differ from this repo's,
and `/project-init` tells you which rules that changes.

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
- `.claude/memory/` — delete every file except `INDEX.md`; those memories are about this repo

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

> **`v0.1.0` predates `docs/patterns/` and `docs/PATTERN-SEARCH.md`**, so those seven files 404 when
> fetched at that tag. The installer detects this and refuses to `--apply` rather than produce a
> half-resolving install. Until a newer tag exists, install from a checkout with
> `./Scripts/adopt.sh /path/to/YourApp --apply`.

> If the repo is private, `curl` cannot reach it. Clone it once over SSH and use `adopt.sh` the same
> way.

### C. Several repos — just the tooling

```
/plugin marketplace add kalpesh-jetani/genericarch-plugin
/plugin install genericarch
```

Skills and commands only. No rules, no docs, no code — so each product keeps its own `CLAUDE.md`,
and tooling fixes reach every repo by updating one plugin.

---

## What you just installed

### The map — how the agent finds anything

`.claude/MAP.tsv` is one grep-able row per doc, note, pattern, skill and command: its topics and when
to read it. It replaces a table of contents that used to be re-read every session.

```bash
grep -i navigation .claude/MAP.tsv           # what covers this topic
awk -F'\t' '$2=="module"' .claude/MAP.tsv    # every module doc
```

Reference docs are **not copied** into your repo — they are fetched when a task needs them. A
`docs/…` row that isn't on disk is a fetch instruction, not a broken link; the map's `# FETCH-BASE:`
line, stamped at install time with the exact commit you installed from, says where to get it.
`/project-init` verifies every row resolves before reporting success.

### The notes — a grep index, not documents

`.claude/notes/` holds nine inventories generated from your code: features and screens, routes, the
API map, images, colours, fonts, design tokens, schemes, targets. They exist to be **searched, never
read** — one grep returns the row, the row answers the question, and the file never enters context.

```bash
./Scripts/find.sh SmartLockHomeView      # or /find — every inventory, one call
```

Three rules follow, and they are what keeps the saving real
([docs/PATTERN-SEARCH.md](docs/PATTERN-SEARCH.md)):

- **Never read a note in full.** If you had to, the row wasn't self-contained — fix the row.
- **A note is never promoted to a skill**, at any size. A skill loads its whole body when it fires
  and its description every session; a note is hit once for one line.
- **Maintained by inserting and deleting rows**, in the change that adds or removes the thing.

Rows are dense on purpose — no link syntax, root declared once in the header, no filename restated
three times. On a real app that is **−21% across the nine notes, −47% on `FEATURES.md`**.

### Skills — these fire on their own when the situation matches

You never type these. They activate from their description when what you're doing matches.

| Skill | Fires when | What it stops you doing |
|---|---|---|
| `new-feature` | Adding a feature, screen or package | Shipping a happy path — it requires every content state, a mock, and localized keys |
| `debug` | Something is broken, blank, or silently wrong | Reading the wrong file first; it narrows to a layer before opening anything |

**Only two ship, deliberately.** A skill costs its description in context every session, and one
that cannot fire in an empty repo costs it for nothing. Six more are written and waiting as patterns
— `change`, `style-guide`, `dark-light-mode`, `rtl-support`, `release-bump`, `feature-complete`. Each
becomes a real skill via `/learn <name>` once your repo has the code it describes.

### Commands — you type these

| Command | Use it to |
|---|---|
| `/project-init` | Set up a fresh repo, or adopt this into an existing one |
| `/verify` | Walk the Definition of Done against your working diff — reports, never fixes |
| `/review` | Review someone else's diff or PR against the rules — reports, never edits |
| `/learn` | Turn a resource (sample repo, Figma frame, vendor docs) or finished work into a note — and promote a pattern to a skill when it has earned it |
| `/gaps` | Decide what this architecture should and should not cover for your product |
| `/decide` | Record a settled decision so it is not re-argued |
| `/find` | Look up where a screen, route, endpoint, asset, colour or target is — one call, no note opened |
| `/upgrade-stack` | Reconcile project settings with your machine — asks twice before changing anything |
| `/sync-app-notes` | Rebuild the inventories from a filesystem scan — **incremental**: it scans only the notes whose sources changed |
| `/build` | Build, test or archive a stage: `DEV`, `TEST`, `BETA`, `PROD` |

Anything that must **never** trigger by inference is a command, not a skill — which is why the full
inventory rescan is `/sync-app-notes` and why builds are `/build`.

### Scripts — run these yourself or in CI

| Script | Does |
|---|---|
| `./Scripts/check.sh` | Enforces the rules a linter cannot express, **and** typechecks every package at the iOS floor — `swift build` on a Mac does not |
| `./Scripts/detect-toolchain.sh` | Reports the stack; `--markdown` emits the `PROJECT.md` *Resolved stack* table, `--options` the valid choices |
| `./Scripts/adopt.sh` | Copies the base into another repo, refusing to copy this product's state — and refusing to run at all if a referenced doc isn't reachable at the pinned commit |
| `./Scripts/build-plugin.sh` | Generates the plugin from `.claude/` — never hand-edit the output |
| `./Scripts/check-skill-triggers.py` | Catches two skills competing for the same phrasing |
| `./Scripts/find.sh` | One-call lookup across every note; on a miss, routes through the map and tells you to record the row |
| `./Scripts/notes-staleness.sh` | Which notes are stale and why — reads **git** timestamps, not mtime, so a fresh clone doesn't read as fully stale |
| `./Scripts/scan-api-map.py` | API surface → screen. Finds the router **from the call sites**, not by filename |
| `./Scripts/scan-colors.py`, `scan-fonts.py`, `scan-unused-assets.py` | The scans behind `/sync-app-notes`; run standalone to check one inventory |
| `./Scripts/check-note-links.py` | Every path in every note resolves |
| `./Scripts/detect-capabilities.sh` | Evidence scan behind `/gaps` — analytics, crash reporting, StoreKit, biometrics… |

### Four rules the agent follows without being asked

- **`CLAUDE.md` is never edited without your explicit approval** — it loads into every session, so a
  change there alters every future response.
- **It never commits or pushes.** Work is left in the working tree; you decide when it's done.
- **It never builds, runs, or tests** — including `./Scripts/check.sh`, which compiles. It tells you
  what to run.
- **The note inventories are updated row by row** as part of a change; a full rescan only happens
  when you type `/sync-app-notes`, and even then it scans only what changed.

---

## Start here

| You want to… | Read |
|---|---|
| Know the rules before writing code | [CLAUDE.md](CLAUDE.md) |
| Find the doc for a topic | `grep -i <topic> .claude/MAP.tsv` |
| Find *where something is* — a screen, route, endpoint, asset | `/find <name>` |
| Know why a scan is written the way it is | [docs/SCAN-TRAPS.md](docs/SCAN-TRAPS.md) |
| Know the resolved stack — min OS, Xcode, Swift | [.claude/notes/PROJECT.md](.claude/notes/PROJECT.md) |
| Understand a specific layer | [docs/modules/](docs/modules/) — one doc per package |
| Know why something is the way it is | [docs/DECISIONS.md](docs/DECISIONS.md) |
| Know what's deliberately missing | [docs/GAPS.md](docs/GAPS.md) |
| Set up a machine, or ship | [docs/REPO.md](docs/REPO.md), [docs/DELIVERY.md](docs/DELIVERY.md) |
| Know where a new doc belongs | [docs/STRUCTURE.md](docs/STRUCTURE.md) |

## Layout

```
CLAUDE.md            always-on rules (kept deliberately small — no version numbers)
Packages/            local Swift packages — Core, DIKit, DesignSystem, Features/…
App/                 thin iOS + macOS shells: @main, composition root, no logic
docs/                hand-written reasoning: module design + cross-cutting reference
docs/modules/        one doc per package
docs/patterns/       procedures not yet skills — /learn promotes one when it earns it
docs/SCAN-TRAPS.md   why each scan is shaped as it is — read only to change one
.claude/MAP.tsv      the router: every doc, note, pattern, skill and command, greppable
.claude/notes/       nine inventories generated from the code (features, routes, API map, images,
                     colours, fonts, tokens, schemes, targets) — grepped, never read
.claude/memory/      what earlier sessions learned — in-repo and tracked, so it survives a clone
.claude/skills/      procedures Claude applies on its own
.claude/commands/    things you trigger, listed above
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

Apps build per stage — DEV / TEST / BETA / PROD ([.claude/notes/SCHEMES.md](.claude/notes/SCHEMES.md)),
or via `/build`, which picks the scheme and destination for you.

## Status

The architecture is documented and a vertical slice (`Core`, `DIKit`) builds and tests clean. Most
packages are specified but not yet implemented; [docs/GAPS.md](docs/GAPS.md) tracks what is
deliberately absent.

`./Scripts/check.sh` is currently red on one item: the recorded minimum macOS is above the installed
macOS SDK. `/upgrade-stack` reviews that and asks before changing anything.
