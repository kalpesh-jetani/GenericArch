# GenericArch

Reference architecture for building **iPhone / iPad / Mac** apps from one shared codebase, with
Claude Code as the thing that enforces it.

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

**This repo is not a project you build in — it is a setup process, and `install.sh` or
`bootstrap.sh` is how it runs.** Everything the install promises follows from that one act: it
records every file it wrote with a hash in `.genericarch/manifest-v<version>.json`, which is what
makes the install reversible, re-sealable and updatable per file. A copy of this tree that no
installer wrote has none of that.

**This installs into a repo that already has its Xcode project.** That is the only shape it
supports: it reconciles rules against what is already true in your repo, and records a manifest of
every file it wrote so the install stays reversible. Neither means anything in an empty directory —
`install.sh` refuses one and points you at [GenericXCodeSetup](https://github.com/kalpesh-jetani/GenericXCodeSetup), which creates the project and the
package layout. Come back here afterwards.

Two ways in, both non-destructive: **nothing overwrites your `CLAUDE.md`, your skills, or your
commands.**

| You have | Use | You get |
|---|---|---|
| An existing app | **`bootstrap.sh`** → `install.sh` — path **A** below | Skills, commands, indexes and tooling — your code and your rules untouched, every file hashed, fully reversible with `uninstall.sh` |
| Several repos | **Plugin** — path **B** below | Only the skills and commands, updated centrally |

**Do not build your app inside a GenericArch checkout.** `install.sh` refuses a target that is its
own source, and a clone you work in directly inherits this product's decisions — floors included —
while looking like a fresh start. Clone it anywhere, install *out* of it into your repo.

**There is deliberately no "start from the template" path.** GitHub's template feature copies the
tracked tree, which means no installer ran — and with no manifest, `uninstall.sh` refuses the repo
outright (*"no manifest — treating this as an incomplete install"*) because nothing can prove which
files were ours. `ga-reseal.sh` likewise has nothing to keep honest. A copy also arrives holding this
product's decisions, gaps, notes, memory and **deployment floors** as if they were its own. The
template flag on the repo is off for that reason. Already holding a copy made while it was on? It is
a fork, not an install, and it is usable as one — reset the inherited state
([docs/SHARING.md](docs/SHARING.md)) and take the package layout from
[GenericXCodeSetup](https://github.com/kalpesh-jetani/GenericXCodeSetup). [Updating an install](#updating-an-install) still works for you:
`adopt-review.sh` compares content against a base checkout and never reads a manifest.

Reference docs are fetched on demand rather than copied, and two groups are **opt-in** — see
[What travels](#what-travels-and-what-does-not) below.

---

### A. Existing project — from inside your repo

```bash
curl -fsSLO https://raw.githubusercontent.com/kalpesh-jetani/GenericArch/HEAD/bootstrap.sh
less bootstrap.sh
bash bootstrap.sh
bash bootstrap.sh --apply
```

Read it, then run it: the third line is a **dry run** that lists every file it would add, and only
the fourth writes anything.

> **Paste one line at a time, or strip the comments.** Every other block here annotates its commands
> with `#`, and **zsh — the macOS default — does not treat `#` as a comment when you paste it**
> (`interactive_comments` is off). A pasted `bash bootstrap.sh   # dry run` arrives as
> `bash bootstrap.sh '#' dry run`, which is not a dry run. The scripts here name that specific
> mistake when they see it; `setopt interactive_comments` fixes it for good.

`bootstrap.sh` is the only part of this that touches the network, and all it does is fetch: it
resolves the **newest semver tag** on the remote, clones it, and hands over to that clone's
`install.sh`. Every decision about what lands in your repo — the compatibility gate, the plan, the
confirmation, the manifest, the rollback — belongs to it, and runs offline. Already have a checkout?
Skip the fetch and run the installer directly:

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
/sync-app-notes        # builds the inventories every later lookup reads instead of searching
```

`/project-init` starts from evidence the installer already gathered:
`.claude/notes/.evidence/INIT-SCAN.md` — the mode, one row per rule conflict with counts and example
paths, the name collisions, and whether every `MAP.tsv` row resolves. Offline, no model. What is
*not* in it is any verdict: a count is not a severity, so the asking is unchanged
(`./Scripts/ga-init-scan.sh . --write` regenerates it).

**In that order — it is enforced**, not advisory ([the order](#the-commands-run-in-order)). Then, on
your own machine, `./Scripts/check.sh`: expect failures on an existing codebase, that is the point.

Your rules win by default. For a hard conflict — CocoaPods vs SPM, UIKit vs SwiftUI — the usual
answer is *adopt for new code only*, because a codebase that already violates a rule cannot adopt it
by editing a doc ([docs/ADOPTION.md](docs/ADOPTION.md)).

#### Build settings as reviewable text

Settings held inside an `.xcodeproj` are a diff nobody reads. The install offers to write the five
`.xcconfig` files your project should reference instead — `Configurations/{Base,DEV,TEST,BETA,PROD}`
exactly as [SCHEMES.md](.claude/notes/SCHEMES.md) specifies them — plus `XCODE-SETUP.md`, the four
steps only you can take: point each configuration at its file, add the `AppEnvironment` key, add the
packages, check it. To run it yourself, or again later:

```bash
./Scripts/ga-project-setup.sh .                       # dry run, prompts for anything not given
./Scripts/ga-project-setup.sh . --product MyApp --bundle-id com.acme.myapp \
    --targets ios,macos --ios 17 --macos 15 --apply
```

**It never creates, opens or edits an `.xcodeproj`** — no project of yours is touched, and a repo
with no project at all is refused with a pointer to [GenericXCodeSetup](https://github.com/kalpesh-jetani/GenericXCodeSetup). Nothing is defaulted:
the bundle ID, the Team ID and both floors are asked, and a Team ID you do not have stays blank
rather than invented.

| Override | Effect |
|---|---|
| `--ref <tag>` or `GA_REF=<tag>` | Pin a version instead of taking the newest tag. Copy tag names from `git ls-remote --tags --refs <repo>` rather than reconstructing them — prefixed and unprefixed forms both exist and are not guaranteed to be the same commit. Don't pin `v0.1.0`: it predates the script registry, `docs/patterns/` and `.claude/memory/` |
| `GA_REPO=/path/to/checkout` | A local clone or your fork — also the way in when the repo is private and `curl` cannot reach it |

### B. Several repos — just the tooling

```
/plugin marketplace add kalpesh-jetani/genericarch-plugin
/plugin install genericarch
```

Skills and commands only. No rules, no docs, no code — so each product keeps its own `CLAUDE.md`,
and tooling fixes reach every repo by updating one plugin.

---

## What the install does and does not add

It adds the tooling and the lookup layer: skills, commands, the indexes, the scan and lifecycle
scripts, `uninstall.sh`. It does **not** add `Packages/`, `docs/modules/`, or any Swift — your repo
has its own shape, and a module doc for a layer you do not have is a dead lookup forever.

The **architecture layer** — the `new-feature` skill, `/review`, and the module and pattern rows in
`MAP.tsv` — is held back by default. Both enforce §2/§3: in a repo that has not adopted them,
`new-feature` produces a package the app cannot consume and `/review` reports rules the product
declined. `/project-init` offers the layer once the rule-conflict table is settled, or
`--with-architecture` takes it up front.

Imposing a layout on a codebase that already has one is the adoption mistake `/project-init` exists
to avoid — so the install has nothing to impose. The layout for a repo with no shape yet lives in
[GenericXCodeSetup](https://github.com/kalpesh-jetani/GenericXCodeSetup), which writes it and stops.

## What travels, and what does not

`Scripts/adopt.sh` owns the list, and `install.sh` drives it — so there is one answer, not two.

| | What | Why |
|---|---|---|
| **Copied** | skills · commands · `MAP.tsv` · `SCRIPTS.tsv` · `INDEX.md` · the scan and lookup scripts · the lifecycle tools (`ga-step`, `ga-remove`, `ga-reseal`) · `ga-project-setup.sh` · `uninstall.sh` | They must be local to work |
| **Scaffolded empty** | `docs/DECISIONS.md` · `docs/GAPS.md` · `.claude/notes/` · `.claude/memory/` · `.claude/CANDIDATES.tsv` | The prose is ours, the answers are yours |
| **Fetched on demand** | `docs/modules/` · `docs/patterns/` · the cross-cutting reference docs | A product should not carry docs for layers it does not have. `genericarch.installation.md` indexes them; a missing `docs/…` link is a fetch instruction |
| **On consent** | `--with-architecture` → the `new-feature` skill, `/review`, and the module and pattern rows in `MAP.tsv` | A surface that cannot fire is worse than a missing one: it is grepped, offered and trusted |
| **Opt-in** | `--with-lint` → `.swiftlint.yml`, `.swiftformat` · `--with-meta` → `Scripts/claude-workflows/` | Lint enforces conventions a product may have declined; the pipeline authors `CLAUDE.md` files rather than building apps |
| **Never** | `CLAUDE.md` · this repo's decisions, gaps, notes and memory · `install.sh`, `bootstrap.sh` · `README.md` · `.claude/settings.json` | Your rules are yours; re-installing means fetching again |

At install time the indexes are made true for *your* repo: `MAP.tsv` rows whose file is not on disk
are marked `:remote` so a grep hit says "fetch me", and `SCRIPTS.tsv` rows for scripts you did not
install are pruned outright — a registry row leading nowhere is read on every lookup.

---

## The commands run in order

Each command leaves the repo in the state the next one assumes, and the order is **enforced**, not
just documented — `Scripts/ga-step.sh` is every command's first step, and an out-of-order run
exits 5
without writing anything.

```
install → /project-init → /gaps → /sync-app-notes → ready
```

```bash
./Scripts/ga-step.sh show     # where am I, what runs next
```

After `ready`, the skills and `/find`, `/decide`, `/learn`, `/review`, `/verify`, `/build` run in
any
order — they are the work, not steps.

Out of order, these commands would not fail; they would succeed against the wrong input. `/gaps`
before `/project-init` triages capabilities against rules nobody has accepted; `/sync-app-notes`
before either scans a tree still being agreed. That is why it is a gate and not a paragraph. A step
that
genuinely does not apply is **recorded as skipped, with a reason** — by you, never by Claude:

```bash
./Scripts/ga-step.sh record gaps "not applicable: docs-and-tooling adoption"
```

Why each position matters, and how to add a command: [docs/SEQUENCE.md](docs/SEQUENCE.md).

## Declining a file so it stays declined

A file GenericArch ships that your product does not want is **not** deleted with `rm`. Absent from
disk and never installed are the same state to an installer, so a hand deletion comes back on the
next install:

```bash
./Scripts/ga-remove.sh docs/modules/StorageKit.md --reason "no StorageKit here" --apply
```

One command, four effects:

1. **moves** the file to `.genericarch/safetodelete/` — nothing is destroyed, so reversing costs
   nothing. The name is the contract: deleting that directory loses only the ability to revive;
2. **tombstones** it, so no later install re-creates it;
3. **de-references** it — rows pruned from `MAP.tsv` and `SCRIPTS.tsv`, and every remaining prose
   reference reported with file and line rather than rewritten, because only a reader of the
   sentence can tell whether it should go, change, or point elsewhere;
4. **records** the reason in `DECISIONS.md` *Do not re-propose*.

`--list` shows what is declined; `--revive <path> --apply` moves the file back byte-identical.

## Keeping an install removable

`uninstall.sh` removes a file only while its hash still matches the manifest — that contract is what
stops it deleting something you wrote. The catch: any command that *rewrites* an installed file
breaks the match, silently turning that file into something no uninstall can remove. So
`/project-init`, `/gaps` and `/sync-app-notes` close with:

```bash
./Scripts/ga-reseal.sh --apply     # without --apply: says what drifted, writes nothing
```

Run it yourself after editing an installed file by hand.

---

## Uninstalling, and what it refuses to delete

`install.sh` records every path it wrote, with a hash, in
`.genericarch/manifest-v<version>.json`. `uninstall.sh` reads that manifest and nothing else — so
removal is a verified operation, not a guess at which files were probably ours.

```bash
./uninstall.sh v0.5.0              # plan, then ask
./uninstall.sh v0.5.0 --dry-run    # print the plan and stop
./uninstall.sh v0.5.0 --yes        # skip the confirmation prompt
```

**The version argument is required.** Supported: `v0.1.0`, `v0.2.0`, `v0.3.0`, `v0.4.0`, `v0.4.1`, `v0.4.2`, `v0.5.0` (latest). Defaulting it would
mean guessing which release's footprint to delete, and a wrong guess deletes the wrong files.

**Exit 0 means the repo is back to its pre-install state; exit 1 means files were left behind** —
listed in `.genericarch/orphans-<version>.txt`, which outlives the terminal. A partial removal that
reported success leaves a repo half-installed with nobody aware of it.

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

### Where the rules live — and what each costs per session

`CLAUDE.md` is loaded in full on **every** session, so it holds only what binds while writing code.
Everything else is one lookup away, and linked from there so it is never lost:

| File | Loaded | Holds |
|---|---|---|
| `CLAUDE.md` | every session — ~3,700 tokens | §0–§12: the ask-first decisions, the 15 unbreakable rules, the index, concurrency, conventions |
| `Packages/CLAUDE.md` | when you work in a package | the detail behind §4 extraction, §7 wrappers, §9 package testing |
| `docs/BUILD-PROCESS.md` · `DEPLOYMENT-PROCESS.md` · `PROJECT-SETTINGS.md` | when the task is that | building a stage · shipping and rolling back · capabilities, floors, secrets, privacy |
| `docs/` reference, `.claude/notes/` | on lookup | the reasoning, and the code's own inventory |

Every section heading stays in `CLAUDE.md` even when its detail moves out — roughly 380 `§N`
citations across the docs, skills and scripts resolve against those headings, and no linter checks
them.

### The map — how the agent finds anything

`.claude/MAP.tsv` is one grep-able row per doc, note, pattern, skill and command: its topics and
when
to read it — one grep instead of a table of contents re-read every session.

```bash
grep -i navigation .claude/MAP.tsv           # what covers this topic
awk -F'\t' '$2=="module"' .claude/MAP.tsv    # every module doc
```

Reference docs are **not copied** into your repo — they are fetched when a task needs them. Those
rows are marked at install time: a kind reading `module:remote` means *not on disk here, fetch it*,
and the map's `# FETCH-BASE:` line carries the exact commit you installed from. Without the mark,
every reader had to stat the file to find out — 22 of 60 rows in one real adoption, each costing a
lookup and sometimes a fetch of a doc for a layer the product does not have.

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
added without stating its contract. A script with no row is a script the agent will never call — and
the reverse is worse, so a row whose script is not installed here is **pruned at install time**
rather than left to be grepped forever.

### The notes — a grep index, not documents

**Seven of the nine come from a script**, in two tiers — because a note needing judgement rarely
means every *column* does:

| Tier | Notes | Who writes it |
|---|---|---|
| Generated | FONTS · ASSETS-COLORS · PROJECT | the script, outright |
| Partial | ASSETS-IMAGES · API-MAP · NAVIGATION · SCHEMES | the script writes what it can prove and states, in the note, what it did not |
| Hand-written | FEATURES · STYLE-GUIDE | a reviewer, from candidates |


```bash
./Scripts/sync-notes.sh --apply       # writes those three, between managed markers
./Scripts/sync-notes.sh --evidence    # candidates for the six that need judgement
./Scripts/sync-notes.sh --check       # CI gate: exit 1 when one has drifted
```

Offline, no model. A partial note carries its caveat **inside** the generated block — "the 110 rows
above are parsed from the tree; what this scan does not establish is which screen calls each
endpoint" — so it can never be mistaken for a complete one. The remainder goes to
`.claude/notes/.evidence/<NOTE>.tsv`, and `/sync-app-notes` resolves a named list instead of running
a scan. Why the last two resist automation at all: [SCAN-TRAPS.md](docs/SCAN-TRAPS.md).

When a generator cannot handle your repo it writes a ~45-line report to `.genericarch/failures/`
naming what it expected and what it found, and **that** is what the agent reads — not the 175-line
scanner. It fixes the script, so the next run is mechanical again.


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
`rtl-support`, `release-bump`, `feature-complete`. Each becomes a real skill via `/learn <name>`
once
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

A staged script is **session-local and gitignored**, promoted into `Scripts/` only when a *second,
distinct session* needs the same intent. Promotion runs seven gates, refuses anything that invokes a
compiler (§2.12) or touches the network, then writes a real `#@` header and regenerates the
registry.

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

**Opt-in**: eleven scripts that author this layer rather than build an app with it, so they install
only with `adopt.sh --with-meta`. Without them the same nine phases are walked by hand, in the same
order.

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

### Ten rules the agent follows without being asked

- **`CLAUDE.md` is never edited without your explicit approval** — it loads into every session, so a
  change there alters every future response.
- **It never commits or pushes.** Work is left in the working tree; you decide when it's done.
- **It never deletes an installed file with `rm`** — it retires it through `ga-remove.sh`, which
  moves, tombstones, de-references and records in one operation. A hand deletion would come back.
- **It runs the commands in order**, and stops when the gate refuses rather than passing `--force`.
- **It greps the map before any task that is not writing code.** Setup, build, ship and settings are
  not in `CLAUDE.md`; a topic it cannot find is one to ask about, not to improvise.
- **It reads a failed script's report, not the script.** ~45 lines naming what the script expected
  and what your repo has, instead of 175 lines to re-derive.
- **It builds to validate, and asks before running or testing** — `./Scripts/check.sh` compiles the
  iOS floor and it runs that itself; the app, a simulator and the test suite wait for your yes.
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
| Know what every file in here is for | [OPERATORS-GUIDE.md](OPERATORS-GUIDE.md) — written for a person, not the agent |
| Know the rules before writing code | [CLAUDE.md](CLAUDE.md) |
| Find the doc for a topic | `grep -i <topic> .claude/MAP.tsv` |
| Find *which script already does this* | `./Scripts/find-script.sh "<what you want>"` |
| Find *where something is* — a screen, route, endpoint, asset | `/find <name>` |
| Edit a `CLAUDE.md` under a record | [docs/CLAUDE-TASKS.md](docs/CLAUDE-TASKS.md) |
| Know why a scan is written the way it is | [docs/SCAN-TRAPS.md](docs/SCAN-TRAPS.md) |
| Know which command runs next, or why one refused | `./Scripts/ga-step.sh show` · [docs/SEQUENCE.md](docs/SEQUENCE.md) |
| Decline a file GenericArch ships | `./Scripts/ga-remove.sh <path> --reason "…"` |
| Find a file this thing retired | `.genericarch/safetodelete/` · `./Scripts/ga-remove.sh --list` |
| Know the resolved stack — min OS, Xcode, Swift | [.claude/notes/PROJECT.md](.claude/notes/PROJECT.md) |
| Understand a specific layer | [docs/modules/](docs/modules/) — one doc per package |
| Know why something is the way it is | [docs/DECISIONS.md](docs/DECISIONS.md) |
| Know what's deliberately missing | [docs/GAPS.md](docs/GAPS.md) |
| Set up a machine, or ship | [docs/REPO.md](docs/REPO.md), [docs/DELIVERY.md](docs/DELIVERY.md) |
| Know when a change is actually finished | [docs/DONE.md](docs/DONE.md), or `/verify` |
| Know where a new doc belongs | [docs/STRUCTURE.md](docs/STRUCTURE.md) |
| Know what earlier sessions learned about this repo | [.claude/memory/INDEX.md](.claude/memory/INDEX.md) — tracked, so it survives a clone |
| Regenerate the inventories without spending a session | `./Scripts/sync-notes.sh --apply` |

## Layout

```
CLAUDE.md            session rules ONLY — no version numbers, no reference tables, no checklists,
                     no setup/build/ship material. Those live in docs/ and are read per task
Packages/CLAUDE.md   scoped rules: extraction, wrappers, package testing — loaded where they bind
OPERATORS-GUIDE.md   every file in this repo and what a person does with it
docs/BUILD-PROCESS.md      building a stage: who runs what, and what a failure means
docs/DEPLOYMENT-PROCESS.md tag → soak → submit → roll back, and who owns each gate
docs/PROJECT-SETTINGS.md   capabilities, entitlements, floors, secrets, privacy, localization
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
.genericarch/        the install record: manifest-<version>.json (what was written, hashed),
                     TOMBSTONES.tsv (what was declined and why), STEPS.tsv (which steps ran),
                     safetodelete/ (the declined files themselves — the one directory you may
                     delete), orphans-<version>.txt (what an uninstall could not remove)
docs/SEQUENCE.md     the command order, what each step must leave behind, and how to add one
Scripts/ga-step.sh   the sequence gate — show · next · require · after · record
Scripts/sync-notes.sh    regenerate seven of the nine notes offline — no model, no network
Scripts/ga-init-scan.sh  the offline half of /project-init: mode, conflict evidence, collisions
Scripts/ga-handoff.sh    a failing script's bounded diagnosis, so the agent fixes it from that
Scripts/ga-remove.sh retire a file: move, tombstone, de-reference, record
Scripts/ga-reseal.sh keep files the commands edited removable
Scripts/ga-roundtrip.sh  proves install → uninstall still round-trips
Scripts/check.sh     enforces the rules a linter can't express — compiles, so it is yours to run
Scripts/claude-utils/      cross-phase utilities: lint, links, rollback, registry — macOS only
Scripts/claude-workflows/  the nine numbered phases, plus run-task.sh — OPTIONAL (--with-meta)
```

Two packages are **not in this repo at all**. `GenericArch-NetworkKit` and `GenericArch-ImageCache`
are standalone, zero-dependency packages in their own repositories — add them to `Package.swift`
when
a product needs them, and they resolve by version. Their source is never copied into a consuming
codebase ([docs/REPO.md](docs/REPO.md)).

## Build

**There is no Swift in this repo.** It ships rules, docs and tooling; the packages live in the repo
you install into, and the reference implementations of `Core` and `DIKit` live in
[GenericXCodeSetup](https://github.com/kalpesh-jetani/GenericXCodeSetup), which copies them into a product. In your own repo:

```bash
swift build --package-path Packages/Core     # any package, standalone
swift test  --package-path Packages/Core
./Scripts/check.sh                           # rule enforcement, and the iOS floor
```

Apps build per stage — DEV / TEST / BETA / PROD
([.claude/notes/SCHEMES.md](.claude/notes/SCHEMES.md)),
or via `/build`, which picks the scheme and destination for you.

## Status

The architecture is documented; most packages are specified rather than implemented, and
[docs/GAPS.md](docs/GAPS.md) tracks what is deliberately absent. The worked examples of `Core` and
`DIKit` moved to [GenericXCodeSetup](https://github.com/kalpesh-jetani/GenericXCodeSetup) with the layout that places them, so `check.sh` here has no
package to typecheck — it does that work in the repo you install into.

The install lifecycle has its own gate: `./Scripts/ga-roundtrip.sh`, each case against a repo built
from nothing. **Run it before tagging a release** — a lifecycle that cannot round-trip leaves an
adoption half-installed with nobody aware of it.
