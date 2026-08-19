# GenericArch

Reference architecture for building **iPhone / iPad / Mac** apps using CLAUDE from one shared codebase.

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
| An existing app | **`bootstrap.sh`** → `install.sh` | Rules, docs and tooling — your code and your rules untouched, reversible with `uninstall.sh` |
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

**Then reset the state you inherited** — a template copies this product's answers along with the
structure: the per-product rows in `docs/DECISIONS.md`, the statuses in `docs/GAPS.md` (then
`/gaps`), the `.claude/notes/` table bodies, and every `.claude/memory/` file except `INDEX.md`
— **and empty its `## Index` table**, because deleting the files while leaving their rows behind is
the common mistake.

```bash
./Scripts/detect-toolchain.sh   # your machine sets the baseline, not this repo's
./Scripts/verify-memory.sh      # 0 once the store is yours; 1 lists what is still inherited
```

`./Scripts/adopt.sh` (path C) does this reset for you. Only the template path needs the manual step.

### B. Existing project — from inside your repo

```bash
curl -fsSLO https://raw.githubusercontent.com/kalpesh-jetani/GenericArch/HEAD/bootstrap.sh
less bootstrap.sh        # short, and it tells you what it will do
bash bootstrap.sh        # dry run — lists every file it would add
bash bootstrap.sh --apply
```

`bootstrap.sh` is the only part of this that touches the network, and all it does is fetch: it
resolves the **newest semver tag** on the remote, clones it, and hands over to that clone's
`install.sh`, which runs entirely offline. Every decision about what lands in your repo — the
compatibility gate, the plan, the confirmation, the manifest, the rollback — belongs to
`install.sh`. Pin a specific tag with `--ref`:

```bash
bash bootstrap.sh --apply --ref <tag>
```

Already have a checkout? Skip the fetch and run the installer directly — same behaviour, no network:

```bash
/path/to/GenericArch/install.sh /path/to/YourRepo
```

<details>
<summary>One-liner, if you already trust the source</summary>

```bash
curl -fsSL https://raw.githubusercontent.com/kalpesh-jetani/GenericArch/HEAD/bootstrap.sh | bash -s -- --apply
```
</details>

It pins to a tag, records every file it installed in `.genericarch/manifest-v<version>.json`,
reports every collision instead of resolving it, and **never writes `CLAUDE.md`**. Because that
manifest hashes what it wrote, the install is fully reversible — see
[Uninstalling](#uninstalling-and-what-it-refuses-to-delete). Then:

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
| `--ref <tag>` or `GA_REF=<tag>` | Pin a version instead of taking the newest tag. Copy tag names from `git ls-remote --tags --refs <repo>` rather than reconstructing them — prefixed and unprefixed forms both exist and are not guaranteed to be the same commit. Don't pin `v0.1.0`: it predates the script registry, `docs/patterns/` and `.claude/memory/` |
| `GA_REPO=/path/to/checkout` | A local clone or your fork — also the way in when the repo is private and `curl` cannot reach it |

### C. Several repos — just the tooling

```
/plugin marketplace add kalpesh-jetani/genericarch-plugin
/plugin install genericarch
```

Skills and commands only. No rules, no docs, no code — so each product keeps its own `CLAUDE.md`,
and tooling fixes reach every repo by updating one plugin.

---

## Uninstalling, and what it refuses to delete

`install.sh` records every path it wrote, with a hash, in
`.genericarch/manifest-v<version>.json`. `uninstall.sh` reads that manifest and nothing else — so
removal is a verified operation, not a guess at which files were probably ours.

```bash
./uninstall.sh v0.2.0              # plan, then ask
./uninstall.sh v0.2.0 --dry-run    # print the plan and stop
./uninstall.sh v0.2.0 --yes        # skip the confirmation prompt
```

**The version argument is required.** Supported: `v0.1.0`, `v0.2.0` (latest). Defaulting it would
mean guessing which release's footprint to delete, and a wrong guess deletes the wrong files.

Flags, exit codes, what *user-edited file preserved* means, and recovering an install that failed
part-way: [docs/SHARING.md](docs/SHARING.md). Manifest format:
[docs/INSTALL-MANIFEST.md](docs/INSTALL-MANIFEST.md).

---

## Updating an install

`install.sh` never overwrites, so an upstream fix reaches an adopted repo only when you go and get
it. `adopt-review.sh` is that missing half: it classifies every shipped path against your repo — and
`CLAUDE.md` by numbered section rather than as a file — and writes nothing.

```bash
./Scripts/adopt-review.sh /path/to/YourApp            # what differs, what is missing
./Scripts/adopt-review.sh /path/to/YourApp --diff 3   # with the actual diffs
./Scripts/adopt-review.sh /path/to/YourApp --take 2,3 # take only what you chose
```

Exit `0` means you match the base, `1` that decisions are pending — so it doubles as a CI staleness
gate. **Claude reports this table and never passes `--take`**, and `--take` refuses `CLAUDE.md`
outright. Details: [docs/SHARING.md](docs/SHARING.md).

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

### The script registry — the agent calls scripts instead of rewriting them

`.claude/SCRIPTS.tsv` is one row per script: its inputs, outputs, exit codes, side effects, and
whether the agent is allowed to run it at all. Every script declares its own contract in a `#@`
header and the registry is **generated** from those headers — so it cannot drift from the scripts it
describes.

```bash
./Scripts/find-script.sh "are the notes stale"  # which script answers this question
grep -i lint .claude/SCRIPTS.tsv                # which script covers this word
awk -F'\t' '$4!="call"' .claude/SCRIPTS.tsv     # what the agent must not simply run
./Scripts/claude-utils/register-scripts.sh --check   # CI: fail if a header changed
```

`grep` only works if you guess the word the author used. The optional `#@when` field carries the
trigger phrases someone would actually *ask*, and `find-script.sh` scores against those first —
which is why "is the memory store consistent" reaches `verify-memory.sh` without knowing its name.

The `claude` column is what makes that safe:

| Value | Means |
|---|---|
| `call` | run it |
| `emit-only` | it prints commands it deliberately does not run |
| `needs-approval` | it writes; needs an explicit `--approve` or `--yes` |
| `never:<reason>` | the agent must not run it — `check.sh` compiles the iOS floor |

`register-scripts.sh` refuses to register a script with an incomplete header, so a script cannot be
added without stating its contract. A script with no row is a script the agent will never call.

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

**Only two ship, and there are deliberately few, because anything expressible as a script is a
script.** A skill costs context every session through its description, so one that cannot fire in an
empty repo costs it for nothing; a script costs nothing until called. A skill earns its place only
when it encodes judgement a script cannot — an order of operations, a decision about what to do next
— never when it is really a lookup table of which tool to reach for.

| Skill | Fires when | What it stops you doing |
|---|---|---|
| `new-feature` | Adding a feature, screen or package | Shipping a happy path — it requires every content state, a mock, and localized keys |
| `debug` | Something is broken, blank, or silently wrong | Reading the wrong file first; it narrows to a layer before opening anything |

**Both open with a script step, in a fixed order.** `new-feature` checks whether the screen already
exists before registering anything — if it does, the work is a change, not a scaffold. `debug` maps
the symptom to the one scan that answers it rather than opening files. Running the steps out of
order is how you scaffold a package that already exists.

Six more are written and waiting as patterns — `change`, `style-guide`, `dark-light-mode`,
`rtl-support`, `release-bump`, `feature-complete`. Each becomes a real skill via `/learn <name>` once
your repo has the code it describes.

**A description is trigger phrases, never a summary of the body.** A summary makes the skill fire on
work it doesn't own, and that is a testable property, so it is tested — run it after any description
edit:

```bash
python3 Scripts/check-skill-triggers.py      # 29 prompts, each with the skill that should win
```

### Commands — you type these

| Command | Use it to |
|---|---|
| `/project-init` | Set up a fresh repo, or adopt this into an existing one |
| `/verify` | Walk the Definition of Done against your working diff — reports, never fixes |
| `/review` | Review someone else's diff or PR against the rules — reports, never edits |
| `/learn` | Turn a resource (sample repo, Figma frame, vendor docs) or finished work into a note — promote a pattern to a skill, or `--script` a twice-repeated manual operation into a registered script |
| `/gaps` | Decide what this architecture should and should not cover for your product |
| `/decide` | Record a settled decision so it is not re-argued |
| `/find` | Look up where a screen, route, endpoint, asset, colour or target is — one call, no note opened |
| `/upgrade-stack` | Reconcile project settings with your machine — asks twice before changing anything |
| `/sync-app-notes` | Rebuild the inventories from a filesystem scan — **incremental**: it scans only the notes whose sources changed |
| `/build` | Build, test or archive a stage: `DEV`, `TEST`, `BETA`, `PROD` |

Anything that must **never** trigger by inference is a command, not a skill — which is why the full
inventory rescan is `/sync-app-notes` and why builds are `/build`.

### Scripts — run these yourself or in CI

**macOS only.** Written to a Mac, not hedged for portability: bash 3.2, BSD `sed`/`awk`, `shasum`,
and the Xcode command-line tools. `_common.sh` checks `uname` and exits 78 on anything else, because
a GNU/BSD difference otherwise reads as bad data rather than the wrong machine
([docs/CLAUDE-TASKS.md](docs/CLAUDE-TASKS.md)).

**Reuse before you write.** `find-script.sh` scores an intent against every script's `#@when`
trigger phrases, so "is the memory store consistent" finds `verify-memory.sh` without you knowing
its name. A registry hit costs about 20 tokens; re-deriving the same pipeline costs thousands and
comes out slightly different each time.

```bash
./Scripts/find-script.sh "are the notes out of date"    # 0 = a script already does this
./Scripts/session-script.sh add --intent "..." --cmd '...'   # only when that exits 1
```

A staged script is **session-local and gitignored**. It is promoted into `Scripts/` only when a
*second, distinct session* needs the same intent — one session repeating itself is a one-off, not
a capability. Promotion runs seven gates, refuses anything that invokes a compiler (§2.12) or
touches the network, then writes a real `#@` header and regenerates the registry. The registry row
is what puts it in front of the agent, so no skill prose is ever hand-written.

**The exit code is the contract.** Every `#@exit` header in the registry is what a gate branches
on, so these four compose into a check that needs no Xcode and no network — unlike
`check.sh`, which compiles:

```bash
./Scripts/claude-utils/register-scripts.sh --check   # a #@ header drifted from the registry
./Scripts/verify-memory.sh                           # the memory store lost its bijection
python3 Scripts/check-note-links.py                  # a note points at a file that is gone
./Scripts/notes-staleness.sh                         # an inventory is older than its code
```

**There is deliberately no table of scripts here.** The registry is generated from each script's own
`#@` header, so listing them again by hand is the one place this README could drift from the code.
Ask it instead — `./Scripts/find-script.sh "<what you want>"`, or `grep` `.claude/SCRIPTS.tsv`.

#### The CLAUDE.md task pipeline

`Scripts/claude-workflows/` is a nine-phase pipeline for editing a markdown document — usually a
`CLAUDE.md` — under a record, with `Scripts/claude-utils/` holding the cross-phase utilities. Full
reference: [docs/CLAUDE-TASKS.md](docs/CLAUDE-TASKS.md).

```bash
./Scripts/claude-utils/init-claude-env.sh --add myapp ~/code/myapp
./Scripts/claude-workflows/run-task.sh myapp task-1 all --approve --text "<the request>"
./Scripts/claude-workflows/run-task.sh myapp task-1 status
```

intake → locate → audit → plan → **edit** → verify → **test** → present → **commit**. Each phase
writes one artifact under `.claude/claude-tasks/`, so the next phase greps a row instead of
re-parsing the document, and you can read what happened without re-running anything.

Three phases are gated and none of the gates can be turned off: **5 edit** refuses to write without
`--approve`, **7 test** prints the compile and test commands and runs nothing, **9 commit** emits a
script and never runs git. Phase 4 is where a bad edit dies — absent text, text matching more than
once, a section that does not exist. Gates, phase contracts, Xcode resolution and undo:
[docs/CLAUDE-TASKS.md](docs/CLAUDE-TASKS.md).

### Six rules the agent follows without being asked

- **`CLAUDE.md` is never edited without your explicit approval** — it loads into every session, so a
  change there alters every future response.
- **It never commits or pushes.** Work is left in the working tree; you decide when it's done.
- **It never builds, runs, or tests** — including `./Scripts/check.sh`, which compiles. It tells you
  what to run.
- **The note inventories are updated row by row** as part of a change; a full rescan only happens
  when you type `/sync-app-notes`, and even then it scans only what changed.
- **It calls a script rather than reading it.** `.claude/SCRIPTS.tsv` states each script's inputs
  and outputs, so the agent relies on the result instead of opening the body or re-deriving the
  answer. It reads a script only when a call fails — and then it fixes it.
- **It looks for a script before writing one.** `find-script.sh` runs first; only on a miss does it
  improvise, and then the pipeline is staged for that session alone. A second session needing the
  same thing is what promotes it into `Scripts/` — one session repeating itself is a one-off, not a
  capability.

---

## Start here

| You want to… | Read |
|---|---|
| Know the rules before writing code | [CLAUDE.md](CLAUDE.md) |
| Find the doc for a topic | `grep -i <topic> .claude/MAP.tsv` |
| Find *which script already does this* | `./Scripts/find-script.sh "<what you want>"` |
| Find *where something is* — a screen, route, endpoint, asset | `/find <name>` |
| Edit a `CLAUDE.md` under a record | [docs/CLAUDE-TASKS.md](docs/CLAUDE-TASKS.md) |
| Know why a scan is written the way it is | [docs/SCAN-TRAPS.md](docs/SCAN-TRAPS.md) |
| Know the resolved stack — min OS, Xcode, Swift | [.claude/notes/PROJECT.md](.claude/notes/PROJECT.md) |
| Understand a specific layer | [docs/modules/](docs/modules/) — one doc per package |
| Know why something is the way it is | [docs/DECISIONS.md](docs/DECISIONS.md) |
| Know what's deliberately missing | [docs/GAPS.md](docs/GAPS.md) |
| Set up a machine, or ship | [docs/REPO.md](docs/REPO.md), [docs/DELIVERY.md](docs/DELIVERY.md) |
| Know when a change is actually finished | [docs/DONE.md](docs/DONE.md), or `/verify` |
| Know where a new doc belongs | [docs/STRUCTURE.md](docs/STRUCTURE.md) |

## Layout

```
CLAUDE.md            always-on rules ONLY — no version numbers, no reference tables, no
                     checklists. Those live in docs/ and are read when a task needs them
Packages/            local Swift packages — Core, DIKit, DesignSystem, Features/…
App/                 thin iOS + macOS shells: @main, composition root, no logic
docs/                hand-written reasoning: module design + cross-cutting reference
docs/modules/        one doc per package
docs/patterns/       procedures not yet skills — /learn promotes one when it earns it
docs/SCAN-TRAPS.md   why each scan is shaped as it is — read only to change one
docs/CLAUDE-TASKS.md the nine-phase pipeline: contracts, gates, and how to add a phase
.claude/MAP.tsv      the router: every doc, note, pattern, skill and command, greppable
.claude/SCRIPTS.tsv  the script registry: inputs, outputs, exit codes, trigger phrases — GENERATED
.claude/CANDIDATES.tsv  cross-session recurrence ledger — tracked, because it is what observes that
                     a SECOND session needed the same thing. Staged scripts themselves are not
.claude/notes/       nine inventories generated from the code (features, routes, API map, images,
                     colours, fonts, tokens, schemes, targets) — grepped, never read
.claude/memory/      what earlier sessions learned — in-repo and tracked, so it survives a clone
.claude/skills/      procedures Claude applies on its own
.claude/commands/    things you trigger, listed above
.claude/claude-tasks/ per-run pipeline artifacts — gitignored working state, not a record to keep
Scripts/check.sh     enforces the rules a linter can't express
Scripts/claude-workflows/  the nine numbered phases, plus run-task.sh
Scripts/claude-utils/      cross-phase utilities: lint, links, rollback, registry — macOS only
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
