# GenericArch

Reference architecture for building **iPhone / iPad / Mac** apps from one shared codebase — SwiftUI,
Swift 6 strict concurrency, SPM only.

This repo is the blueprint. Every package in it is meant to be reusable, replaceable, and droppable
into a new product with minimal change.

---

## Install it into your project

Pick the row that matches what you have. All three are non-destructive — **nothing overwrites your
`CLAUDE.md`, your skills, or your commands.**

### New project

```bash
gh repo create <org>/MyApp --template <org>/GenericArch --private --clone && cd MyApp
```

Then `/project-init MyApp` in Claude Code. Reset the inherited state it warns you about
(`docs/DECISIONS.md`, `docs/GAPS.md`, `.claude/notes/`), and run
`./Scripts/detect-toolchain.sh` — a fresh repo takes its baseline from **your** machine, not from
this one.

### Existing project

From inside your repo:

```bash
curl -fsSLO https://raw.githubusercontent.com/<org>/GenericArch/v0.1.0/install.sh
less install.sh && bash install.sh          # dry run — shows exactly what it would add
bash install.sh --apply
```

<details>
<summary>One-liner, if you already trust the source</summary>

```bash
curl -fsSL https://raw.githubusercontent.com/<org>/GenericArch/v0.1.0/install.sh | bash -s -- --apply
```
Read it first. It is short, and it tells you what it will do before it does it.
</details>

It pins to a tag (not `main`), records what it installed in `.genericarch-version`, reports every
collision instead of resolving it, and **never writes `CLAUDE.md`** — `/project-init` reconciles your
rules with these instead.

| Override | Effect |
|---|---|
| `GA_REF=v0.2.0` | Install a different version |
| `GA_REPO=/path/to/checkout` | Install from a local clone or a fork |

### Just the Claude Code tooling, in many repos

Skills and commands only — no rules, no docs, no code. Central updates reach every repo:

```
/plugin marketplace add <org>/genericarch-plugin
/plugin install genericarch
```

---

## Start here

| You want to… | Read |
|---|---|
| Know the rules before writing code | [CLAUDE.md](CLAUDE.md) — the non-negotiables |
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
.claude/commands/    things you trigger: /build /verify /decide /gaps /project-init
Scripts/check.sh     enforces the rules a linter can't express
```

Two packages live in **their own repositories** and are consumed by version:
`GenericArch-NetworkKit` and `GenericArch-ImageCache` ([docs/REPO.md](docs/REPO.md)).

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
| `/build` | Build, test, or archive a stage |

Two standing rules the agent follows: **CLAUDE.md is never edited without explicit approval**, and
the note inventories are updated by targeted edit — never by an unrequested full rescan.

## Status

The architecture is documented and a vertical slice (`Core`, `DIKit`) builds and tests clean. Most
packages are specified but not yet implemented; [docs/GAPS.md](docs/GAPS.md) tracks what is
deliberately absent.
