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

**Then reset the state you inherited.** A template copies this product's answers along with the
structure, and they are not yours:

```bash
./Scripts/detect-toolchain.sh   # your machine sets the baseline, not this repo's
```

- `docs/DECISIONS.md` — delete the per-product rows, keep the toolchain ones
- `docs/GAPS.md` — reset statuses to ▶ Open, then run `/gaps`
- `.claude/notes/*` — clear the table bodies; they describe *this* app's screens and assets
- `.claude/memory/` — delete every file except `INDEX.md`, **and empty its `## Index` table**;
  those memories are about this repo. Deleting the files while leaving their rows behind is the
  common mistake — `./Scripts/verify-memory.sh` reports it as `orphan-row` and exits 1

```bash
./Scripts/verify-memory.sh   # 0 once the store is yours; 1 lists exactly what is still inherited
```

`./Scripts/adopt.sh` (path C) does this reset for you — it scaffolds an empty index rather than
copying ours. Only the template path above needs the manual step.

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

> **Copy tag names; never reconstruct them.** Both prefixed and unprefixed forms exist here, and a
> version published under both names is *not* guaranteed to point at the same commit — so the `v`
> you guess can change which code you get. List them and copy one exactly:
>
> ```bash
> git ls-remote --tags --refs https://github.com/kalpesh-jetani/GenericArch.git
> ```
>
> The installer resolves the newest tag itself and warns when two names claim one version, so this
> only matters when you pin with `--ref`.

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
| `--ref <tag>` or `GA_REF=<tag>` | Pin a version instead of taking the newest tag |
| `GA_REPO=/path/to/checkout` | A local clone or your fork |

> **Do not pin `v0.1.0`.** It predates `docs/patterns/`, `.claude/memory/`, the script registry and
> every script added since, and it still ships six skills that were deleted from source. The
> installer no longer defaults to it — but `--ref v0.1.0` will still honour your request.

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

### Flags

| Flag | `install.sh` | `uninstall.sh` | What it does |
|---|:--:|:--:|---|
| `--dry-run`, `-n` | ✅ | ✅ | Print the full plan and exit. Writes nothing |
| `--yes`, `-y` | ✅ | ✅ | Skip the confirmation prompt (for CI) |
| `--target DIR` | ✅ | ✅ | The repo to act on. Defaults to the current directory |
| `--force`, `-f` | — | ✅ | Proceed when the requested version differs from the recorded one |
| `--base DIR` | — | ✅ | A GenericArch checkout to verify hashes against when there is no manifest |
| `--ref TAG` | `bootstrap.sh` | — | Pin which release to fetch |

Both scripts print the complete plan — every path, with the action it will take — **before**
touching the filesystem, and then ask.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Error — including a version mismatch, or no manifest and no reference checkout |
| `2` | Usage error — missing or unknown version, unknown flag, bad path |
| `3` | **Compatibility mismatch** — the target is not a macOS/Swift project. Nothing was written |
| `4` | Aborted at the confirmation prompt |

`3` is distinct so CI can tell "this repo is not a Swift project" (expected) from "the install
broke" (`1`) without parsing output.

### What "user-edited file preserved" means for you

This is the message operators ask about, so it is worth being precise. When `uninstall.sh` reports:

```
  KEPT — not deleted
    · .claude/MAP.tsv
        you edited it — content hash does not match the manifest
```

…it means the file's current sha256 differs from the hash recorded when it was installed. **Someone
changed it after install — so it is left exactly where it is, and nothing about it is modified.**

That is a deliberate refusal, not a failure. GenericArch deletes a file only when its content
*proves* the file is still the one GenericArch wrote. A hash that has drifted is the only evidence
available that the file now contains something you would not get back, so it is defended instead of
removed. Timestamps can corroborate ownership but never decide it — **a content mismatch always wins
and always protects the file.** A path the manifest never mentioned is never even read.

What that means in practice:

- **Nothing is lost.** Review the listed files and delete them by hand if you do want them gone.
- **`uninstall.sh` still exits `0`.** Preserved files are a reported outcome, not an error.
- **Directories holding a preserved file survive.** Everything else empty is pruned, so no hollow
  GenericArch folders are left behind.
- For an edited file that GenericArch only *appended* to (`.gitignore`), your edits are kept and
  **only the managed block is removed** — restoring the backup wholesale would discard your changes.

### If an install failed part-way

`install.sh` stages into a temp tree and commits from there, so a failure at any point rolls the
target back to exactly where it started — there is normally nothing to clean up. If a process was
killed hard enough to leave files but no manifest, `uninstall.sh` falls back to the known file list
for that version, verified against the blobs that release actually shipped:

```bash
./uninstall.sh v0.2.0 --target /path/to/repo --base /path/to/GenericArch
```

Without a reference checkout ownership cannot be proven, so **nothing is removed** and the script
tells you so. Files GenericArch *generates* rather than copies — the `.claude/notes/` inventories,
`docs/DECISIONS.md`, `docs/GAPS.md` — have no shipped blob to compare against, so a fallback
uninstall keeps them and lists them.

Full format reference: [docs/INSTALL-MANIFEST.md](docs/INSTALL-MANIFEST.md).

---

## Updating an install — you decide, per file

`install.sh` never overwrites. That is the right default and it has a cost: once you have adopted,
a fix upstream reaches you only if you go and get it, and *"0 collisions kept as-is"* tells you
nothing about whether the incoming file even changed.

`adopt-review.sh` is that missing half. It classifies every shipped path against your repo and
prints a numbered list — nothing is written:

```bash
./Scripts/adopt-review.sh /path/to/YourApp            # what differs, what is missing
./Scripts/adopt-review.sh /path/to/YourApp --diff 3   # with the actual diffs
```

```
n   state    path                          delta
1   differs  .claude/MAP.tsv               +0/-2 vs base
2   missing  Scripts/verify-memory.sh      not installed
3   differs  Scripts/find.sh               +0/-1 vs base
```

Identical files are not listed — they would bury the decisions. Then take only what you want:

```bash
./Scripts/adopt-review.sh /path/to/YourApp --take 2,3
```

Exit `0` means you match the base, `1` means decisions are pending — so it also works as a CI
staleness gate. **Claude reports this table and never passes `--take`:** overwriting a file in a
shipping repo is your call, and an approval never carries to the next run.

### CLAUDE.md gets the same treatment, one section at a time

`install.sh` refuses to touch `CLAUDE.md` at all, which protects your rules but means a genuinely
useful new rule can never reach a project that already adopted. `adopt-review.sh` compares it **by
numbered section** instead of as a file:

```
CLAUDE.md
  in the base, not in yours — candidates, none applied automatically:
    + 6. Concurrency
    + 12. For Claude specifically
  yours only — kept, never touched:
    - 4. Our release process
```

So the report is "you do not have section 6", not a whole-file diff nobody reads. `--take` refuses
`CLAUDE.md` on purpose — it loads into every session, so adopting a section goes through the
pipeline that edits it under a record, with its own approval gate
([docs/CLAUDE-TASKS.md](docs/CLAUDE-TASKS.md)).

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

The point is what the agent *stops* doing. **It never reads a script's body to find out what the
script does** — the row says, and the body would cost tokens the row already spent. It calls the
script and relies on the declared output instead of re-deriving the answer by reading files. The one
time the body gets opened is when a call fails; then it is fixed, in the same change, and the
registry regenerated.

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

There are deliberately few, because **anything expressible as a script is a script.** A skill costs
context every session through its description; a script costs nothing until it is called, and its
registry row is generated from its own header rather than written twice. A skill earns its place
only when it encodes judgement a script cannot — an order of operations, a decision about what to
do next — never when it is really a lookup table of which tool to reach for.

| Skill | Fires when | What it stops you doing |
|---|---|---|
| `new-feature` | Adding a feature, screen or package | Shipping a happy path — it requires every content state, a mock, and localized keys |
| `debug` | Something is broken, blank, or silently wrong | Reading the wrong file first; it narrows to a layer before opening anything |

**Both open with a script step, in a fixed order.** `new-feature` checks whether the screen
already exists before registering anything — if it does, the work is a change, not a scaffold —
and checks for an open task before starting a new one, because resuming beats restarting. `debug`
maps the symptom to the one scan that answers it (`scan-colors.py` for dark mode, `scan-fonts.py`
for a font rendering as system) rather than opening files. The sequences are ordered deliberately;
running them out of order is how you scaffold a package that already exists.

**Only two ship, deliberately.** A skill costs its description in context every session, and one
that cannot fire in an empty repo costs it for nothing. Six more are written and waiting as patterns
— `change`, `style-guide`, `dark-light-mode`, `rtl-support`, `release-bump`, `feature-complete`. Each
becomes a real skill via `/learn <name>` once your repo has the code it describes.

**A description is trigger phrases and nothing else.** Not a summary of the body — the body is
loaded only when the skill fires, but the description is paid for on every session that it
doesn't. Worse, a summary makes the skill fire on work it doesn't own: `new-feature` used to list
"layout, localized keys, every ContentState case, protocol+mock pairs" and so it claimed *"fix the
layout on this card"*, *"add a protocol and a mock"*, and *"handle one more content state"* — none
of which is scaffolding.

That is a testable property, so it is tested:

```bash
python3 Scripts/check-skill-triggers.py      # 29 prompts, each with the skill that should win
```

Run it after **any** description edit. It scores each prompt against every description, weighting a
term by how few skills claim it, and fails on three things: two skills tying, the wrong skill
winning, and a prompt leaking to a skill when it should match **none** — the last being what catches
a description that has quietly grown into a summary.

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

**macOS only.** These are written to a Mac, not hedged for portability: bash 3.2, BSD `sed`/`awk`,
`shasum`, and the Xcode command-line tools. `_common.sh` checks `uname` and exits 78 on anything
else — because the failures otherwise don't look like a platform problem. GNU `sed -i` takes no
argument, so `sed -i ''` silently eats the next one; BSD and GNU `awk` disagree on `length()`, so
a line-length rule reports different numbers on each. Both read as bad data rather than the wrong
machine.

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

**Don't memorise this table — grep the registry.** It is here for orientation.

| Script | Does |
|---|---|
| `./Scripts/check.sh` | Enforces the rules a linter cannot express, **and** typechecks every package at the iOS floor — `swift build` on a Mac does not |
| `./Scripts/detect-toolchain.sh` | Reports the stack; `--markdown` emits the `PROJECT.md` *Resolved stack* table, `--options` the valid choices |
| `./Scripts/adopt.sh` | Copies the base into another repo, refusing to copy this product's state — and refusing to run at all if a referenced doc isn't reachable at the pinned commit |
| `./Scripts/build-plugin.sh` | Generates the plugin from `.claude/` — never hand-edit the output |
| `./Scripts/check-skill-triggers.py` | 29 prompts vs every skill description — catches two skills competing for one phrasing, **and** a description claiming words it has no business claiming |
| `./Scripts/find.sh` | One-call lookup across every note; on a miss, routes through the map and tells you to record the row |
| `./Scripts/notes-staleness.sh` | Which notes are stale and why — reads **git** timestamps, not mtime, so a fresh clone doesn't read as fully stale |
| `./Scripts/scan-api-map.py` | API surface → screen. Finds the router **from the call sites**, not by filename |
| `./Scripts/scan-colors.py`, `scan-fonts.py`, `scan-unused-assets.py` | The scans behind `/sync-app-notes`; run standalone to check one inventory |
| `./Scripts/check-note-links.py` | Every path in every note resolves |
| `./Scripts/memory-add.py` | Writes a memory **and** its index row — the row is the half that gets forgotten |
| `./Scripts/verify-memory.sh` | The other half: every memory has a row, every row has a file, frontmatter is valid, no `type: user` was committed |
| `./Scripts/find-script.sh` | Intent phrase → the script that answers it, scored against `#@when`. Run it **before** writing a pipeline |
| `./Scripts/session-script.sh` | Stages an improvised pipeline per session; promotes to `Scripts/` only once a **second** session needs it |
| `./Scripts/adopt-review.sh` | What an update would change in a target, per file and per `CLAUDE.md` section — you pass `--take`, never the agent |
| `./Scripts/detect-capabilities.sh` | Evidence scan behind `/gaps` — analytics, crash reporting, StoreKit, biometrics… |
| `./Scripts/claude-utils/register-scripts.sh` | Regenerates `.claude/SCRIPTS.tsv` from every `#@` header; `--check` fails when one drifted |

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

Three phases are gated, and none of the gates can be turned off:

| Phase | Gate |
|---|---|
| **5 edit** | Refuses to write without `--approve`. It backs the file up first, applies all-or-nothing, and rejects a plan whose target changed since it was built |
| **7 test** | Extracts the document's code snippets and **prints** `xcrun swiftc -parse` and the project's real `xcodebuild test …` line. Runs nothing |
| **9 commit** | Composes a tagged commit message and **emits a script**. Never runs git |

Phase 4 is where a bad edit is meant to die: it rejects text that is absent, text that matches
more than once, and a section that does not exist — and warns when a delete would orphan anchor
links pointing at it. `rollback-claude.sh` undoes phase 5 from its own backup rather than from
git, because the file may have been dirty before the task started.

**Xcode, without building.** `init-claude-env.sh` reads your `.xcworkspace`/`.xcodeproj` and its
**shared** scheme names off the filesystem — `xcodebuild -list` would be authoritative and would
also be a build. Phase 7 emits `xcrun swiftc` rather than bare `swiftc`, since on a Mac with
several Xcodes those are different toolchains and a snippet can pass with one and fail in the IDE;
it names the active `xcode-select -p` for that reason. Findings print `xed -l <line> <file>`, so a
reported line opens in Xcode where it lives.

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
