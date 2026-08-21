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

Four ways in. Pick the row that matches what you have — all of them are non-destructive:
**nothing overwrites your `CLAUDE.md`, your skills, or your commands.**

| You have | Use | You get |
|---|---|---|
| Nothing yet, and you want to choose your layers | **Empty directory** → `install.sh` + `ga-scaffold.sh` — path **B** below | Rules, docs, tooling, and only the layers you pick. **No deployment floor is written for you** — the §0 default |
| Nothing yet, and you want everything at once | **Template repo** — path **A** below | The same, plus every layer this repo has — and this product's answers, which you then reset (including its floors) |
| An existing app | **`bootstrap.sh`** → `install.sh` | Skills, commands, indexes and tooling — your code and your rules untouched, every file hashed, fully reversible with `uninstall.sh` |
| Several repos | **Plugin** | Only the skills and commands, updated centrally |

**Do not build your app inside a GenericArch checkout.** `install.sh` refuses a target that is its
own source, and a clone you work in directly inherits this product's decisions — floors included —
while looking like a fresh start. Clone it anywhere, install *out* of it into your repo.

Reference docs are fetched on demand rather than copied, and two groups are **opt-in** — see
[What travels](#what-travels-and-what-does-not) below.

---

### A. New project — from the template

```bash
gh repo create <you>/MyApp --template kalpesh-jetani/GenericArch --private --clone
cd MyApp
./Scripts/detect-toolchain.sh --mismatches   # do this BEFORE /project-init
```

**Clear any `BLOCKING` row first.** `/project-init` refuses to do anything while one stands — a
deployment floor above your installed SDK cannot build, and reconciling rules onto a repo that does
not build wastes the session. On this path the usual offender is an inherited floor; see the reset
below, and `/upgrade-stack` if you would rather be walked through it.

Then, in Claude Code:

```
/project-init MyApp
```

It asks for what it cannot infer — bundle ID, Team ID, the languages you ship at v1, which rules you
want as *hard* vs *base*, and which permissions to allow. Nothing is written before you answer.

**Then reset the state you inherited** — a template copies this product's answers along with the
structure: the per-product rows in `docs/DECISIONS.md`, the statuses in `docs/GAPS.md` (then
`/gaps`), the `.claude/notes/` table bodies, and every `.claude/memory/` file except `INDEX.md` —
**including its `## Index` table**, since deleting the files and leaving their rows is the usual
slip.

```bash
./Scripts/detect-toolchain.sh              # your machine sets the baseline, not this repo's
./Scripts/detect-toolchain.sh --mismatches # BLOCKING rows first — see the floors note below
./Scripts/verify-memory.sh                 # 0 once the store is yours; 1 lists what is still inherited
```

**Reset the deployment floors too — this is the one inherited answer that stops the build, not just
misleads.** The template carries this product's floors in code, in the two seed manifests:

```bash
grep -rn 'platforms:' Packages/Core/Package.swift Packages/DIKit/Package.swift
```

They read `.macOS("26.6")`, which is *this* repo's answer to a question your product has not been
asked ([docs/DECISIONS.md](docs/DECISIONS.md)). If your Xcode ships an older macOS SDK, an app target
refuses that floor outright — `--mismatches` reports it as
`BLOCKING|macos-target-above-sdk`, and `/project-init` stops on it before doing anything else. Fix it
in three places, or the next reader takes it for a decision somebody made: both `platforms:` lines,
the *Deployment targets* row in `docs/DECISIONS.md`, and `/decide` to record what you chose instead.
Nothing here defaults a floor for you — that is CLAUDE.md §0, and it applies to an inherited number
exactly as it applies to a blank one.

Two more things the template path does differently from an install:

- **`scaffold` is recorded *not applicable* automatically.** A template copy already has the
  structure `ga-scaffold.sh` would create — `ga-step.sh` derives that from the checkout itself, so
  `/project-init` clears its gate without an operator override.
- **You inherit the layer set, not a choice of one.** Every layer this repo has arrives whether your
  product needs it or not. If that is not what you want, take path B instead and pick.

`./Scripts/adopt.sh` (path D) does this reset for you. Only the template path needs the manual step.

### B. New project — from an empty directory *(recommended for a genuinely new app)*

The template hands you this product's answers; an empty directory hands you none. For a new app that
is the difference that matters, because **no floor is written for you** — the generated manifests
carry a comment where the `platforms:` line would be, which is what CLAUDE.md §0 asks for.

```bash
mkdir MyApp && cd MyApp && git init
/path/to/GenericArch/install.sh .            # dry run first — it prints every file
/path/to/GenericArch/install.sh . --yes
./Scripts/ga-scaffold.sh . --list            # the layers on offer
./Scripts/ga-scaffold.sh . --with navigation,design --apply
```

Then `/project-init` in Claude Code. Nothing to reset: the decisions, gaps, notes and memory arrive
empty, and the floors arrive unset.

**The install offers to set up the Xcode project first.** On an empty directory it checks the Xcode
toolchain, asks what the project needs, and writes the four `.xcconfig` files —
`Configurations/{Base,DEV,TEST,BETA,PROD}.xcconfig` exactly as
[SCHEMES.md](.claude/notes/SCHEMES.md) specifies them — plus an `XCODE-SETUP.md` checklist. It stops
before the `.xcodeproj` itself, because nothing here generates one. You do the two minutes of
File > New > Project, following the checklist.

To run it yourself, or re-run it later — without `--apply` it prints the plan and writes nothing:

```bash
./Scripts/ga-project-setup.sh .                       # dry run, prompts for anything not given
./Scripts/ga-project-setup.sh . --product MyApp --bundle-id com.acme.myapp \
    --targets ios,macos --ios 17 --macos 26.5 --apply
```

**If the Command Line Tools are missing it stops and says so, before writing anything.** Only full
Xcode can create a project, so a Command-Line-Tools-only machine is also a stop in prepare mode —
being handed a checklist you cannot follow is worse than being told why.

Nothing is defaulted: the bundle ID, the Team ID and both floors are asked, and a Team ID you do not
have stays blank rather than invented. With no terminal to ask on — CI, a pipe — the step is skipped
and the install continues; pass every answer as a flag to run it there.

#### Already created the project in Xcode?

That works too, and the order does not matter — but **pass `--mode new`**:

```bash
/path/to/GenericArch/install.sh . --mode new
```

An `.xcodeproj` is an Apple marker, so the compatibility gate reads the directory as an *existing*
repo and would skip `Scaffold/` and `ga-scaffold.sh` — the package layer you have not written yet.
The install now spots this case (a project, but no `Packages/`), says so, and offers the correction
rather than quietly installing half. `ga-project-setup.sh` switches to `--adopt`: it writes the
`.xcconfig` files for your existing project and never opens or edits the `.xcodeproj`.

### C. Existing project — from inside your repo

```bash
curl -fsSLO https://raw.githubusercontent.com/kalpesh-jetani/GenericArch/HEAD/bootstrap.sh
less bootstrap.sh        # short, and it tells you what it will do
bash bootstrap.sh        # dry run — lists every file it would add
bash bootstrap.sh --apply
```

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

| Override | Effect |
|---|---|
| `--ref <tag>` or `GA_REF=<tag>` | Pin a version instead of taking the newest tag. Copy tag names from `git ls-remote --tags --refs <repo>` rather than reconstructing them — prefixed and unprefixed forms both exist and are not guaranteed to be the same commit. Don't pin `v0.1.0`: it predates the script registry, `docs/patterns/` and `.claude/memory/` |
| `GA_REPO=/path/to/checkout` | A local clone or your fork — also the way in when the repo is private and `curl` cannot reach it |

### D. Several repos — just the tooling

```
/plugin marketplace add kalpesh-jetani/genericarch-plugin
/plugin install genericarch
```

Skills and commands only. No rules, no docs, no code — so each product keeps its own `CLAUDE.md`,
and tooling fixes reach every repo by updating one plugin.

---

## Two installs, one difference

`install.sh` runs in one of two modes, derived from the compatibility gate and overridable with
`--mode existing|new`. They differ in exactly one thing: **whether the target gets the predefined
module material.**

| | Existing repo | New repo |
|---|---|---|
| Detected by | any Apple/Swift marker | nothing identifies the repo yet |
| Gets | skills, commands, indexes, tooling | the same, **plus** `Scaffold/` and `ga-scaffold.sh` |
| `Packages/`, `docs/modules/` | **never** — the repo has its own shape, and a module doc for a layer it lacks is a dead lookup forever | the scaffold creates the layers you choose and brings each one's doc |
| The architecture layer — `new-feature`, `/review`, the module and pattern index rows | **not installed.** Both enforce §2/§3: in a repo with no `Packages/`, `new-feature` scaffolds something the app cannot consume and `/review` reports rules the product declined. `/project-init` offers it once the rule-conflict table is settled, or `--with-architecture` takes it up front | included — starting from this base *is* the decision to use it |
| `scaffold` step | recorded *not applicable* at install time, so nothing waits on it | pending until you run it |

Imposing a layout on a codebase that already has one is the adoption mistake `/project-init` exists
to avoid — so the existing-repo install has nothing to impose.

### The new-repo scaffold

```bash
./Scripts/ga-scaffold.sh . --list                       # the layers on offer
./Scripts/ga-scaffold.sh . --with navigation,design     # dry run — the plan
./Scripts/ga-scaffold.sh . --with navigation,design --apply
./Scripts/ga-scaffold.sh . --with navigation,design --apply --yes   # CI, or any run with no tty
```

`--apply` asks before writing. With no terminal to ask on — CI, a pipe, an agent — it stops instead
of guessing; add `--yes` (or `GA_ASSUME_YES=1`) to confirm up front.

It creates the app shells, copies `Core` and `DIKit` in as real tested packages, adds only the
layers
you ask for, brings each one's module doc, and records what you chose in `docs/DECISIONS.md`. Layers
can be added later with the same command. What each choice costs:
[Scaffold/ARCHITECTURE-OPTIONS.md](Scaffold/ARCHITECTURE-OPTIONS.md).

**It writes no version numbers.** Deployment floors come from `detect-toolchain.sh` reading your
repo's own manifests, or from `--ios`/`--macos`. With neither, the generated manifests carry a
comment
instead of a `platforms:` line and `Packages/FLOORS.md` explains how to choose — because a floor a
tool picked compiles today, breaks on the first shared-code change, and by then reads as a decision
somebody made.

## What travels, and what does not

`Scripts/adopt.sh` owns the list, and `install.sh` drives it — so there is one answer, not two.

| | What | Why |
|---|---|---|
| **Copied** | skills · commands · `MAP.tsv` · `SCRIPTS.tsv` · `INDEX.md` · the scan and lookup scripts · the lifecycle tools (`ga-step`, `ga-remove`, `ga-reseal`) · `uninstall.sh` | They must be local to work |
| **Scaffolded empty** | `docs/DECISIONS.md` · `docs/GAPS.md` · `.claude/notes/` · `.claude/memory/` · `.claude/CANDIDATES.tsv` | The prose is ours, the answers are yours |
| **Fetched on demand** | `docs/modules/` · `docs/patterns/` · the cross-cutting reference docs | A product should not carry docs for layers it does not have. `genericarch.installation.md` indexes them; a missing `docs/…` link is a fetch instruction |
| **New repos only** | `Scaffold/` · `Scripts/ga-scaffold.sh` · `Scripts/ga-project-setup.sh` · the `Core`/`DIKit` seed under `Scaffold/seed/` | Decided by what the target *is*, not by preference — see above. An existing repo already has its project and its build settings, so a tool that prepares them is a lookup that never fires |
| **On consent** | `--with-architecture` → the `new-feature` skill, `/review`, and the module and pattern rows in `MAP.tsv` | A surface that cannot fire is worse than a missing one: it is grepped, offered and trusted. Implied by a new-repo install |
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
install → scaffold* → /project-init → /gaps → /sync-app-notes → ready
                                                    * new repos only
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
./uninstall.sh v0.3.0              # plan, then ask
./uninstall.sh v0.3.0 --dry-run    # print the plan and stop
./uninstall.sh v0.3.0 --yes        # skip the confirmation prompt
```

**The version argument is required.** Supported: `v0.1.0`, `v0.2.0`, `v0.3.0` (latest). Defaulting it would
mean guessing which release's footprint to delete, and a wrong guess deletes the wrong files.

**Exit 0 means the repo is back to its pre-install state; exit 1 means files were left behind** —
listed in `.genericarch/orphans-<version>.txt`, which outlives the terminal. A partial removal that
reported success is how one repo ended up half-installed with nobody aware of it.

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
to read it. It replaces a table of contents that used to be re-read every session.

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

```bash
swift build --package-path Packages/Core     # any package, standalone
swift test  --package-path Packages/Core
./Scripts/check.sh                           # rule enforcement
```

Apps build per stage — DEV / TEST / BETA / PROD
([.claude/notes/SCHEMES.md](.claude/notes/SCHEMES.md)),
or via `/build`, which picks the scheme and destination for you.

## Status

The architecture is documented and a vertical slice (`Core`, `DIKit`) builds and tests clean. Most
packages are specified but not yet implemented; [docs/GAPS.md](docs/GAPS.md) tracks what is
deliberately absent.

`./Scripts/check.sh` is currently red on one item: the recorded minimum macOS is above the installed
macOS SDK. `/upgrade-stack` reviews that and asks before changing anything.

The install lifecycle has its own gate, and it is green: `./Scripts/ga-roundtrip.sh` — six cases,
each against a repo built from nothing. Run it before tagging a release; a lifecycle that cannot
round-trip is how an adoption ends up half-installed with nobody aware of it.
