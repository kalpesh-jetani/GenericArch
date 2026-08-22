# GenericArch

Reference architecture for building **iPhone / iPad / Mac** apps from one shared codebase, with
Claude Code as the thing that enforces it.

It ships **rules, docs and tooling — no Swift**. You install it into a repo that already has its
Xcode project; the packages live there. Every version, floor and setting is read from your project
or your machine, never written here.

**Contents** — [Install](#1-install) · [Commands](#2-commands) · [Skills](#3-skills) ·
[CLAUDE.md](#4-claudemd) · [Upgrade & migrate](#5-upgrade--migrate) ·
[Scripts and their usage](#6-scripts-and-their-usage) · [Reference](#7-reference)

---

## 1. Install

Everything from zero to `ready`, in the order it runs. Nothing here overwrites your `CLAUDE.md`,
your skills, or your commands.

### Usage

**A. One app — from inside your repo**

```bash
curl -fsSLO https://raw.githubusercontent.com/kalpesh-jetani/GenericArch/HEAD/bootstrap.sh
```
```bash
less bootstrap.sh
```
```bash
bash bootstrap.sh
```
```bash
bash bootstrap.sh --apply
```

Third line is a dry run listing what it would add; only the fourth writes anything. Already have a
checkout — skip the fetch and run the installer directly:

```bash
/path/to/GenericArch/install.sh /path/to/YourRepo
```

**B. Several repos — tooling only**

```
/plugin marketplace add kalpesh-jetani/genericarch-plugin
/plugin install genericarch
```

Skills and commands only — no rules, no docs, no code. Each product keeps its own `CLAUDE.md`, and
tooling fixes reach every repo by updating one plugin.

**Then, in this order — the order is enforced, not advisory**

```
install → /project-init → /gaps → /sync-app-notes → ready
```

```
/project-init
```
```
/gaps
```
```
/sync-app-notes
```

```bash
./Scripts/ga-step.sh show
```

Then, on your own machine:

```bash
./Scripts/check.sh
```

**Build settings as reviewable text** — writes `Configurations/{Base,DEV,TEST,BETA,PROD}.xcconfig`
plus `XCODE-SETUP.md`. Offered during install; to run it yourself, or again later:

```bash
./Scripts/ga-project-setup.sh .
```
```bash
./Scripts/ga-project-setup.sh . --product MyApp --bundle-id com.acme.myapp --targets ios,macos --ios 17 --macos 15 --apply
```

### Options

| Flag / variable | Effect |
|---|---|
| `--apply` | `bootstrap.sh` writes; without it, dry run |
| `--dry-run` · `--yes` | `install.sh`: print the plan and stop · skip the confirmation prompt |
| `--with-architecture` | Take the architecture layer up front — `new-feature`, `/review`, module and pattern rows |
| `--with-lint` · `--with-meta` | `.swiftlint.yml` + `.swiftformat` · `Scripts/claude-workflows/` |
| `--with-claude-md` | Take GenericArch's `CLAUDE.md`; yours is kept at `CLAUDE-BK.md`. Off by default |
| `--in-place` | Install over an existing install instead of uninstalling first |
| `--ref <tag>` or `GA_REF=<tag>` | Pin a version instead of taking the newest tag |
| `GA_REPO=/path/to/checkout` | A local clone or your fork |

Full flag list and exit codes are in each script's own header — `install.sh`, `bootstrap.sh`,
`uninstall.sh`. Exit codes: `0` ok · `1` error · `2` usage · `3` incompatible target ·
`4` declined · `6` uninstall first · `78` not macOS.

### What it adds, and what it does not

| | What | Why |
|---|---|---|
| **Copied** | skills · commands · `MAP.tsv` · `SCRIPTS.tsv` · `INDEX.md` · scan and lookup scripts · `ga-step`, `ga-remove`, `ga-reseal` · `ga-project-setup.sh` · `uninstall.sh` | They must be local to work |
| **Scaffolded empty** | `docs/DECISIONS.md` · `docs/GAPS.md` · `.claude/notes/` · `.claude/memory/` · `.claude/CANDIDATES.tsv` | The prose is ours, the answers are yours |
| **Fetched on demand** | `docs/modules/` · `docs/patterns/` · cross-cutting reference docs | A product should not carry docs for layers it does not have |
| **On consent** | `--with-architecture` → `new-feature`, `/review`, module and pattern rows | A surface that cannot fire is worse than a missing one |
| **Opt-in** | `--with-lint` · `--with-meta` | Lint enforces conventions a product may have declined |
| **Never** | `CLAUDE.md` · this repo's decisions, gaps, notes and memory · `install.sh`, `bootstrap.sh` · `README.md` · `.claude/settings.json` | Your rules are yours |

It does **not** add `Packages/`, `docs/modules/`, or any Swift. `Scripts/adopt.sh` owns this list
and `install.sh` drives it — one answer, not two.

### Notes

- The target repo must already have its Xcode project. An empty directory is refused — get the
  project and package layout from
  [GenericXCodeSetup](https://github.com/kalpesh-jetani/GenericXCodeSetup) first, then come back.
- Do not build your app inside a GenericArch checkout. `install.sh` refuses a target that is its own
  source, and a clone you work in inherits this product's decisions and floors.
- `install.sh` records every file it wrote, with a hash, in `.genericarch/manifest-v<version>.json`.
  That manifest is what makes the install reversible, re-sealable and updatable per file —
  `uninstall.sh` reads it and nothing else.
- There is no "start from the template" path. A copy no installer wrote has no manifest, so
  `uninstall.sh` refuses it and `ga-reseal.sh` has nothing to keep honest.
- When pasting a block with `#` comments, paste one line at a time. zsh — the macOS default — does
  not treat `#` as a comment when pasted; `setopt interactive_comments` fixes it.
- `bootstrap.sh` is the only part that touches the network, and all it does is fetch a pinned tag.
  Every decision — gate, plan, manifest, rollback — belongs to `install.sh` and runs offline.
- `./Scripts/check.sh` is expected to fail on an existing codebase. That is the point.
- Your rules win by default. For a hard conflict — CocoaPods vs SPM, UIKit vs SwiftUI — the usual
  answer is *adopt for new code only* ([docs/ADOPTION.md](docs/ADOPTION.md)).
- Out of order these commands would not fail, they would succeed against the wrong input. A step
  that genuinely does not apply is recorded as skipped, by you, never by Claude:
  `./Scripts/ga-step.sh record gaps "not applicable: docs-and-tooling adoption"`. Exit `5` means an
  earlier step has not run ([docs/SEQUENCE.md](docs/SEQUENCE.md)).
- `ga-project-setup.sh` never creates, opens or edits an `.xcodeproj`. Nothing is defaulted — bundle
  ID, Team ID and both floors are asked.

---

## 2. Commands

You type these. Anything that must **never** trigger by inference is a command, not a skill.

### Usage

| Command | Use it to |
|---|---|
| `/project-init` | Adopt this into an existing repo — reconciles conflicting rules with approval first |
| `/gaps` | Triage `docs/GAPS.md` — derived from the code on an existing repo, asked on a fresh one |
| `/sync-app-notes` | Rebuild the nine inventories from a scan — **incremental**, only what changed |
| `/find` | Look up a screen, route, endpoint, asset, colour, font, token or target — one call |
| `/decide` | Record a settled architecture decision in `docs/DECISIONS.md` |
| `/learn` | Record a resource or finished work — promote a pattern to a skill, or `--script` a repeated step |
| `/verify` | Walk the Definition of Done against your working diff — reports, never fixes |
| `/review` | Review someone else's diff or PR against the rules — reports, never edits |
| `/build` | Build, test or archive a scheme: `DEV`, `TEST`, `BETA`, `PROD` |
| `/upgrade-stack` | Reconcile project settings with your machine — asks twice before changing anything |
| `/sync-with-genericarch` | Bring an install up to date with the base, and promote patterns the code now justifies |
| `/clean-up-genericarch-extra-memory` | Apply removals `/project-init` only reported — asks per candidate |

### Notes

- The first three are lifecycle steps and run in the order above. The rest run in any order once
  the repo is `ready` — `/find` included, which is why it gates on `sync-app-notes` having finished.
- `/sync-app-notes` and `/build` are commands precisely because a full rescan or a build must never
  fire by inference.

---

## 3. Skills

You never type these — they activate from their description when what you're doing matches.

### Usage

| Skill | Fires when | What it stops you doing |
|---|---|---|
| `new-feature` | Adding a feature, screen or package | Shipping a happy path — it requires every content state, a mock, and localized keys |
| `debug` | Something is broken, blank, or silently wrong | Reading the wrong file first; it narrows to a layer before opening anything |

```bash
python3 Scripts/check-skill-triggers.py
```

Run that after any description edit — 29 prompts, each with the skill that should win.

### Notes

- Only two ship, deliberately. Anything expressible as a script is a script: a skill costs context
  every session through its description, a script costs nothing until called.
- Both open with a script step, in a fixed order. `new-feature` checks whether the screen already
  exists before registering anything — if it does, the work is a change, not a scaffold.
- Six of the seven docs in `docs/patterns/` wait to be promoted — `change`, `style-guide`,
  `dark-light-mode`, `rtl-support`, `release-bump`, `feature-complete`. `/learn <name>` promotes one
  once your repo has the code it describes. The seventh, `wrapper`, is what satisfies §7 rather than
  a procedure to promote.
- A description is trigger phrases, never a summary of the body. A summary makes the skill fire on
  work it does not own.

---

## 4. CLAUDE.md

`CLAUDE.md` is loaded in full on **every** session, so it holds only what binds while writing code.
Everything else is one lookup away.

| File | Loaded | Holds |
|---|---|---|
| `CLAUDE.md` | every session — ~4,000 tokens | §0–§12: ask-first decisions, the 15 unbreakable rules, the index, concurrency, conventions |
| `Packages/CLAUDE.md` | when you work in a package | §4 extraction, §7 wrappers, §9 package testing |
| `docs/BUILD-PROCESS.md` · `DEPLOYMENT-PROCESS.md` · `PROJECT-SETTINGS.md` | when the task is that | building a stage · shipping and rolling back · capabilities, floors, secrets, privacy |
| `docs/` reference · `.claude/notes/` | on lookup | the reasoning, and the code's own inventory |

### Usage

```bash
grep -i navigation .claude/MAP.tsv
```
```bash
awk -F'\t' '$2=="module"' .claude/MAP.tsv
```
```bash
./Scripts/find.sh SmartLockHomeView
```

`.claude/MAP.tsv` is one grep-able row per doc, note, pattern, skill and command — one grep instead
of a table of contents re-read every session. `.claude/notes/` holds nine inventories generated from
your code, meant to be **searched, never read**.

**Editing `CLAUDE.md` under a record** — `Scripts/claude-workflows/` is a nine-phase pipeline
(intake → locate → audit → plan → **edit** → verify → **test** → present → **commit**), opt-in with
`--with-meta`:

```bash
./Scripts/claude-utils/init-claude-env.sh --add myapp ~/code/myapp
```
```bash
./Scripts/claude-workflows/run-task.sh myapp task-1 all --approve --text "<the request>"
```
```bash
./Scripts/claude-workflows/run-task.sh myapp task-1 status
```

Three phases are gated and no gate can be turned off: **5 edit** refuses to write without
`--approve`, **7 test** prints the commands and runs nothing, **9 commit** emits a script and never
runs git. Contracts and undo: [docs/CLAUDE-TASKS.md](docs/CLAUDE-TASKS.md).

### Notes

- Every section heading stays in `CLAUDE.md` even when its detail moves out — roughly 450 `§N`
  citations repo-wide resolve against those headings, and no linter checks them.
- A `MAP.tsv` kind reading `module:remote` means *not on disk here, fetch it*. The map's `#
  FETCH-BASE:` line carries the exact commit you installed from.
- Never read a note in full. If you had to, the row was not self-contained — fix the row. Notes are
  maintained by inserting and deleting rows, in the change that adds or removes the thing.
- A note is never promoted to a skill, at any size —
  [docs/PATTERN-SEARCH.md](docs/PATTERN-SEARCH.md).
- Claude never edits `CLAUDE.md` without explicit approval, and never commits or pushes. The full
  list of what it does unasked is `CLAUDE.md` §2 and §12 — that file is the source of truth, not
  this one.

---

## 5. Upgrade & migrate

### Usage

**Upgrade — uninstall, then install.** `install.sh` refuses when the manifest records a different
version and exits `6`.

```bash
(cd /path/to/YourApp && ./uninstall.sh v0.5.0)
```
```bash
./install.sh /path/to/YourApp
```

**Uninstall.** The version argument is required.

```bash
./uninstall.sh v0.6.1
```
```bash
./uninstall.sh v0.6.1 --dry-run
```
```bash
./uninstall.sh v0.6.1 --yes
```

Supported: `v0.1.0` · `v0.2.0` · `v0.3.0` · `v0.4.0` · `v0.4.1` · `v0.4.2` · `v0.5.0` · `v0.6.0` ·
`v0.6.1` (latest). At the end it asks what becomes of any files it could not remove: `--upgrade`
leaves them for a re-install, `--final` retires them to `.genericarch/safetodelete/`.

**Take upstream fixes into an adopted repo.** `install.sh` never overwrites, so this is the other
half. Writes nothing.

```bash
./Scripts/adopt-review.sh /path/to/YourApp
```
```bash
./Scripts/adopt-review.sh /path/to/YourApp --diff 3
```
```bash
./Scripts/adopt-review.sh /path/to/YourApp --take 2,3
```

**Decline a file so it stays declined.** Never `rm` an installed file.

```bash
./Scripts/ga-remove.sh docs/modules/StorageKit.md --reason "no StorageKit here" --apply
```
```bash
./Scripts/ga-remove.sh --list
```
```bash
./Scripts/ga-remove.sh --revive docs/modules/StorageKit.md --apply
```

**Keep the install removable** after any command or hand edit rewrote an installed file:

```bash
./Scripts/ga-reseal.sh --apply
```

### Notes

- A file is removed only while its hash still proves it is GenericArch's — that contract is what
  stops `uninstall.sh` deleting something you wrote. It is also why rewriting an installed file
  breaks the match, and why `ga-reseal.sh` exists.
- Uninstall exit `0` means the repo is back to its pre-install state; exit `1` means files were left
  behind, listed in `safetodelete-after-migration-note.md` at the repo root, which the next
  `install.sh` reads.
- A v0.1.0 install predates the manifest, so `uninstall.sh` can only fall back to hashing against a
  reference checkout — which that machine may not have. `./uninstallv0.1.0.sh` carries the hashes
  inline instead and needs no manifest, no checkout and no network. It refuses to run against a repo
  carrying GenericArch's own release tags, and writes nothing without `--apply`.
- `ga-remove.sh` does four things in one operation — moves the file to `.genericarch/safetodelete/`,
  tombstones it so no later install re-creates it, prunes its `MAP.tsv` and `SCRIPTS.tsv` rows, and
  records the reason in `DECISIONS.md` *Do not re-propose*. Remaining prose references are reported
  with file and line, never rewritten.
- Absent from disk and never installed are the same state to an installer — that is why a hand
  deletion comes back on the next install.
- `adopt-review.sh` exit `0` means you match the base, `1` that decisions are pending, so it doubles
  as a CI staleness gate. Claude reports its table and never passes `--take`; `--take` refuses
  `CLAUDE.md` outright.
- `install.sh --with-claude-md` is the one way it writes your `CLAUDE.md` — yours moves to
  `CLAUDE-BK.md`, and `uninstall.sh` puts it back byte-for-byte.
- Flags, exit codes and recovering a part-way install: [docs/SHARING.md](docs/SHARING.md). Manifest
  format: [docs/INSTALL-MANIFEST.md](docs/INSTALL-MANIFEST.md).

---

## 6. Scripts and their usage

**There is deliberately no table of scripts here.** `.claude/SCRIPTS.tsv` is generated from each
script's own `#@` header — inputs, outputs, exit codes, side effects, and whether the agent may run
it at all — so it cannot drift. Listing them again by hand is the one place this file could.

### Usage

**Find the script before writing one:**

```bash
./Scripts/find-script.sh "are the notes out of date"
```
```bash
grep -i lint .claude/SCRIPTS.tsv
```
```bash
awk -F'\t' '$4!="call"' .claude/SCRIPTS.tsv
```

Exit `1` from `find-script.sh` is the only thing that justifies improvising one:

```bash
./Scripts/session-script.sh add --intent "..." --cmd '...'
```

**Offline checks — no Xcode, no network.** The `#@exit` header is the contract a gate branches on:

```bash
./Scripts/claude-utils/register-scripts.sh --check
```
```bash
./Scripts/verify-memory.sh
```
```bash
python3 Scripts/check-note-links.py
```
```bash
./Scripts/notes-staleness.sh
```

**Regenerate the inventories** — offline, no model:

```bash
./Scripts/sync-notes.sh --apply
```
```bash
./Scripts/sync-notes.sh --evidence
```
```bash
./Scripts/sync-notes.sh --check
```

**Build and enforce**, in the repo you installed into:

```bash
swift build --package-path Packages/Core
```
```bash
swift test --package-path Packages/Core
```
```bash
./Scripts/check.sh
```

**Before tagging a release:**

```bash
./Scripts/ga-roundtrip.sh
```

### The `claude` column

| Value | Means |
|---|---|
| `call` | run it |
| `emit-only` | it prints commands it deliberately does not run |
| `needs-approval` | it writes; needs an explicit `--approve` or `--yes` |
| `never:<reason>` | the agent must not run it. Nothing carries it today — `check.sh` became `call` once §2.12 made compiling the way a change gets validated |

### Notes

- macOS only. bash 3.2, BSD `sed`/`awk`, `shasum`, Xcode command-line tools. `_common.sh` checks
  `uname` and exits `78` on anything else.
- The `#@when` field carries the phrases someone would actually *ask*, and `find-script.sh` scores
  against those first — which is why "is the memory store consistent" reaches `verify-memory.sh`
  without knowing its name. `grep` only works if you guess the author's word.
- A staged script is session-local and gitignored. Promotion into `Scripts/` needs a *second,
  distinct session* with the same intent, and runs seven gates — refusing anything that invokes a
  compiler (§2.12) or touches the network.
- `register-scripts.sh` refuses a script with an incomplete header, so a script cannot be added
  without stating its contract. A row whose script is not installed is pruned at install time.
- The registry covers `Scripts/` only. The four installers at the repo root — `bootstrap.sh`,
  `install.sh`, `uninstall.sh`, `uninstallv0.1.0.sh` — carry the same `#@` header and are read
  directly, which is why no `SCRIPTS.tsv` row points at them.
- When a generator cannot handle your repo it writes a ~45-line report to `.genericarch/failures/`
  naming what it expected and what it found. That report is what the agent reads — never the
  scanner.
- Seven of the nine notes come from `sync-notes.sh` in two tiers — `FONTS`, `ASSETS-COLORS`,
  `PROJECT` outright; `ASSETS-IMAGES`, `API-MAP`, `NAVIGATION`, `SCHEMES` partial, with the caveat
  stated inside the generated block. `FEATURES` and `STYLE-GUIDE` need a reviewer
  ([docs/SCAN-TRAPS.md](docs/SCAN-TRAPS.md)).

---

## 7. Reference

### Start here

| You want to… | Read |
|---|---|
| Know what every file in here is for | [OPERATORS-GUIDE.md](OPERATORS-GUIDE.md) — written for a person, not the agent |
| Know the rules before writing code | [CLAUDE.md](CLAUDE.md) |
| Find the doc for a topic | `grep -i <topic> .claude/MAP.tsv` |
| Find *which script already does this* | `./Scripts/find-script.sh "<what you want>"` |
| Find *where something is* — screen, route, endpoint, asset | `/find <name>` |
| Know which command runs next, or why one refused | `./Scripts/ga-step.sh show` · [docs/SEQUENCE.md](docs/SEQUENCE.md) |
| Know the resolved stack — min OS, Xcode, Swift | [.claude/notes/PROJECT.md](.claude/notes/PROJECT.md) |
| Understand a specific layer | [docs/modules/](docs/modules/) — one doc per package |
| Know why something is the way it is | [docs/DECISIONS.md](docs/DECISIONS.md) |
| Know what's deliberately missing | [docs/GAPS.md](docs/GAPS.md) |
| Set up a machine, or ship | [docs/REPO.md](docs/REPO.md) · [docs/DELIVERY.md](docs/DELIVERY.md) |
| Know when a change is actually finished | [docs/DONE.md](docs/DONE.md), or `/verify` |
| Know where a new doc belongs | [docs/STRUCTURE.md](docs/STRUCTURE.md) |
| Know what earlier sessions learned | [.claude/memory/INDEX.md](.claude/memory/INDEX.md) — tracked, survives a clone |

### Layout

```
bootstrap.sh         fetches a pinned tag and hands off — the only part that touches the network
install.sh           the installer: gate, plan, manifest, rollback — all offline
uninstall.sh         reverses an install from its manifest; the version argument is required
uninstallv0.1.0.sh   removes a v0.1.0 install with the hashes inline — no manifest, no checkout
CLAUDE.md            session rules ONLY — no version numbers, no reference tables, no checklists
Packages/CLAUDE.md   scoped rules: extraction, wrappers, package testing
OPERATORS-GUIDE.md   every file in this repo and what a person does with it
CHANGELOG.md         the release history — a tag is what install.sh records in the manifest
.swiftlint.yml       the §2 conventions as config, with .swiftformat — OPTIONAL (--with-lint)
docs/                hand-written reasoning: module design + cross-cutting reference
docs/modules/        one doc per package
docs/patterns/       procedures not yet skills — /learn promotes one when it earns it
.claude/INDEX.md     what THIS product has — the repo's own router is MAP.tsv, not this
.claude/MAP.tsv      the router: every doc, note, pattern, skill and command, greppable
.claude/SCRIPTS.tsv  the script registry — GENERATED from each script's #@ header
.claude/CANDIDATES.tsv  cross-session recurrence ledger — what observes that a SECOND session
                     needed the same thing. Staged scripts themselves are not tracked
.claude/notes/       nine inventories generated from the code — grepped, never read
.claude/memory/      what earlier sessions learned — tracked, so it survives a clone
.claude/skills/      procedures Claude applies on its own
.claude/commands/    things you trigger
.claude/claude-tasks/ per-run pipeline artifacts — gitignored working state
.claude-plugin/      the plugin manifest — build-plugin.sh regenerates it into dist/
dist/                the generated plugin, gitignored — built, never hand-edited
.genericarch/        the install record: manifest-v<version>.json (what was written, hashed),
                     TOMBSTONES.tsv (declined and why), STEPS.tsv (which steps ran),
                     safetodelete/ (the declined files — the one directory you may delete)
Scripts/             the tooling — see .claude/SCRIPTS.tsv, not a list here
Scripts/claude-utils/      cross-phase utilities: lint, links, rollback, registry
Scripts/claude-workflows/  the nine numbered phases, plus run-task.sh — OPTIONAL (--with-meta)
```

**Note:** `GenericArch-NetworkKit` and `GenericArch-ImageCache` are **not in this repo**. They are
standalone, zero-dependency packages in their own repositories, added to `Package.swift` and
resolved by version — never copied into a consuming codebase ([docs/REPO.md](docs/REPO.md)).

### Status

The architecture is documented; most packages are specified rather than implemented, and
[docs/GAPS.md](docs/GAPS.md) tracks what is deliberately absent. The worked examples of `Core` and
`DIKit` live in [GenericXCodeSetup](https://github.com/kalpesh-jetani/GenericXCodeSetup) with the layout that places them, so `check.sh` here has no
package to typecheck — it does that work in the repo you install into.
