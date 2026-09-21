# Operator's guide

**Who this is for:** you, the person operating this repo. Not Claude — nothing here is instructions
for the assistant. It is a map of what you run, what you own, what you read, and what to leave
alone.

The name is the scope: an *operator* installs it, chooses what it may do, runs the scripts, and owns
every decision it records. Claude's own rules live in [CLAUDE.md](CLAUDE.md) and are deliberately a
different document.

---

## 1. The eight rules that matter most

1. **Commands run in a fixed order.** `install → /declare-profile → /project-init → /sync-app-notes → ready`.
   Run `./Scripts/ga-step.sh show` any time
   to see where you are. Out of order, a command refuses with exit 5 and writes nothing — because the
   failure it prevents is the silent one: it would otherwise succeed against the wrong input.
2. **Never delete an installed file with `rm`.** Use `./Scripts/ga-remove.sh <path> --reason "…"`.
   A plain delete comes back on the next install, because "absent" and "never installed" look
   identical to an installer. Nothing is destroyed: the file **moves** to
   `.genericarch/safetodelete/`, its index rows are pruned, and `--revive` puts it back
   byte-identical. If you want the disk space, delete that directory — the name is the promise.
3. **One install per checkout, at one root.** Two live copies duplicate every command and only one
   of them can ever be uninstalled. The installer now refuses the second one.
4. **Claude never commits and never pushes. It builds to validate, but never runs or tests unasked.**
   Changes are left in the working tree. If you want a commit, or the app or test suite actually
   run, say so explicitly.
5. **`CLAUDE.md` is session material only, and never edited without your yes** — including by
   you-via-Claude. It is the one file loaded on every session, so every line in it is a permanent
   cost: setup, build, ship, settings and the stack's own rules live in their own files, because they
   are not needed in a session where someone is writing code. Anything Claude might need is *linked*
   from there — a file nothing links to is one it never learns exists.
6. **Nothing under `docs/` or `.claude/notes/` is in Claude's context automatically.** It gets
   looked up. That is the whole design: cheap by default, detailed on demand.
7. **A decision is only recorded when it is in two places** — the thing that enforces it, and
   `docs/DECISIONS.md` so nobody re-proposes it.
8. **Scripts do the work; Claude reviews.** The inventories a profile can derive are generated
   offline. When a script cannot handle your repo it writes a short diagnosis, not a guess.

---

## 2. Files you run

All of these are safe to run yourself. Every one prints what it will do before doing it; the ones
that write anything need `--apply` or a confirmation.

### Lifecycle — installing, ordering, removing

| Run this | When you want to |
|---|---|
| `./bootstrap.sh --apply` | Install into a repo when you have no local checkout (fetches from GitHub) |
| `./install.sh <target>` | Install into a repo from this checkout. `--dry-run` for the plan, `--root-ok` to force a second root |
| `./Scripts/ga-step.sh show` | See which step is next, and what has already run |
| `./Scripts/ga-remove.sh <path> --reason "…" --apply` | Retire a file: moves it to `.genericarch/safetodelete/`, tombstones it, prunes its index rows, records the reason. `--list` shows what is declined, `--revive <path>` puts it back |
| `./Scripts/ga-reseal.sh --apply` | After a command rewrote installed files — keeps them removable |
| `./Scripts/adopt-review.sh <target>` | See what an upstream update would change in an installed repo |
| `./uninstall.sh <version>` | Remove an install. **Exit 0 = repo is clean. Exit 1 = files left behind**, listed in `.genericarch/orphans-<version>.txt` |
| `./Scripts/ga-roundtrip.sh` | Prove install→uninstall still round-trips. Run before releasing a version |

### Finding things without reading files

| Run this | Answers |
|---|---|
| `./Scripts/find.sh <name>` | Where is this screen, route, endpoint, asset or token? |
| `./Scripts/find-script.sh "<what you want>"` | Which script already does this? |
| `grep -i <topic> .claude/MAP.tsv` | Which doc, note or skill covers this topic |
| `grep -i <topic> .claude/SCRIPTS.tsv` | A script's full contract: inputs, outputs, exit codes, effects |

### Checking the project

| Run this | Answers |
|---|---|
| `./Scripts/detect-toolchain.sh` | The stack the active profile declares. Never trust a version quoted from a doc — this reads the profile, and a profile may wire a machine probe on top |
| `./Scripts/notes-staleness.sh` | Which inventories are out of date. `--stamp` records a content hash so the next check is instant |
| `./Scripts/sync-notes.sh` | **Rebuild the profile's mechanical notes without Claude.** `--check` for CI (exit 1 on drift), `--apply` to write them, `--evidence` for the remainder. Offline, no model, no network. A partial note writes the provable rows and says in the note what it could not establish. With no profile declared there is nothing to rebuild |
| `./Scripts/ga-init-scan.sh` | **The offline half of `/project-init`.** Mode, rule-conflict evidence for every `docs/ADOPTION.md` §A2 row, name collisions, whether every `MAP.tsv` row resolves, and which module docs have no code. `install.sh` runs it for you and writes `.claude/notes/.evidence/INIT-SCAN.md`; `--check` is the CI gate. Read-only — it decides nothing, writes no rule, and records no step |
| `./Scripts/ga-handoff.sh` | Not run by hand — a failing script calls it and writes a short diagnosis to `.genericarch/failures/`. Hand *that file* to Claude, not the script |
| `./Scripts/check.sh` | The full rule check — the profile-agnostic gate plus whatever the active profile declares. It may compile, and compiling is how a change is validated (§2.8), so this one is `call`: Claude may run it too |
| `./Scripts/build-plugin.sh` | Package the skills and commands as a distributable Claude Code plugin |

### Slash commands (typed to Claude, not in a terminal)

| Command | Does | Position |
|---|---|---|
| `/project-init` | Reconciles your rules with the layer and declares the stack profile, asks per conflict | step 2 |
| `/sync-app-notes` | Rebuilds the inventories the active profile declares from a filesystem scan | step 3 |
| `/find <name>` | Same as `find.sh`, from the chat | any time after step 3 |
| `/decide <what>` | Records a settled decision in `docs/DECISIONS.md` | any time |
| `/learn <thing>` | Turns a resource, a shipped feature or a repeated manual step into repo knowledge | after step 3 |
| `/review [PR]` | Reviews someone else's diff against the rules. Reports, never edits | after step 2 |
| `/verify` | Walks the active profile's Definition of Done against your current changes | after step 2 |
| `/build [stage]` | The one sanctioned way to build or test, through the profile's declared commands | any time |
| `/upgrade-stack` | Reconciles the declared stack with your machine. Asks twice before changing anything | after step 2 |

---

## 2b. What the install adds

You get the tooling and the lookup layer: skills, commands, the indexes, the scan and lifecycle
scripts, `uninstall.sh`, and the `profiles/` mechanism. You do **not** get a stack — no source tree,
no language, no build files. Your structure is yours, and a doc for a layer you do not have is a dead
lookup.

**The stack is a profile you author, not something the layer ships.** No profile ships by default
([profiles/](profiles/CLAUDE.md)) — the layer is deliberately tech-stack-agnostic. `/project-init` is
where you declare one: it asks, records the answers under `profiles/<name>/`, and until then every
stack-specific script no-ops rather than guessing. A command that fires against a stack the project
never declared is worse than a missing one — it still gets grepped, offered and believed.

**No version number is ever written for you.** Stack versions are the profile's to state and
`.claude/notes/PROJECT.md`'s to record; nothing here quotes one from memory. With no tty an
interactive step is skipped and the install continues. From CI or a pipe pass `--yes`, or set
`GA_ASSUME_YES=1`, which every tool here honours.

**A repo *copied* from this one rather than installed into** inherits this repo's own decisions,
notes and memory in its tree — the withdrawn GitHub-template path ([docs/SHARING.md](docs/SHARING.md)),
or any fork made by hand. Nothing was reconciled against your project and there is no manifest to make
it reversible, so clear the inherited decisions, notes and memory before treating them as the new
project's answers.

## 3. Files you own and edit

These are yours. Claude asks before touching any of them.

| File | What it holds | Who writes it |
|---|---|---|
| `CLAUDE.md` | The rules. Loaded on every session, so keep it short and make every line a rule, not a description | You, deliberately, with approval |
| `profiles/<name>/` | Your stack profile — language, build system, test framework, the stack's own rules and its definition of done | You, via `/project-init` |
| `docs/DECISIONS.md` | Settled decisions, open questions, and *Do not re-propose* | `/decide`, and `ga-remove.sh` for declines |
| `.claude/settings.json` | Which commands Claude may run without asking. Per-machine consent — never copied between repos | You |
| `.gitignore` | Standard, plus one delimited managed block the installer adds and the uninstaller removes | Both |

---

## 3b. Where knowledge lives — four stores, four costs

The single most useful thing to understand about this repo. Each store has a different price, and a
fact in the wrong one is either invisible or paid for forever.

| Store | Loaded | Holds | Cost |
|---|---|---|---|
| `CLAUDE.md` | **every session, in full** | rules that bind while writing code | small — the reason it is kept lean |
| `profiles/<name>/` | when a task is stack-specific | the declared stack and its own rules | one lookup, when the stack matters |
| `docs/`, `.claude/notes/` | **never automatically** | reference, and the code's own inventory | one lookup, when a task needs it |
| `.claude/memory/` | read at the start of work | what earlier sessions learned about *this repo* | one index line per fact |

Claude also keeps a **machine-local** store outside this repo for facts about *you* — preferences,
how you like decisions made. Those are per-person, so they are never committed here, and this repo's
`.claude/memory/` explicitly refuses that type.

**The routing rule:** changes behaviour every session → `CLAUDE.md` · specific to the declared stack →
`profiles/<name>/` · a fact about this repo learned the hard way → `.claude/memory/` · an inventory
of the code → `.claude/notes/`, generated · everything else → a doc, with a `MAP.tsv` row.

Why it is worth caring: a note in `.claude/memory/` caught a real regression this repo made — 21
references to a `CLAUDE.md` heading that had been deleted, which no linter checks.

## 4. Files you read when you need them

Nothing here is loaded automatically. Open one when the situation calls for it — or let
`grep -i <topic> .claude/MAP.tsv` point you at the right one.

### Start here

| Doc | Read it when |
|---|---|
| `README.md` | First time in the repo, or installing it somewhere |
| `OPERATORS-GUIDE.md` | This file — what everything is for. Describes *this* repo; an installed repo gets `genericarch.installation.md` instead, listing what was installed and what is fetched on demand |
| `docs/SEQUENCE.md` | A command refused as out of order, or you are adding a command |
| `docs/ADOPTION.md` | Adopting this into a repo that already has its own rules |

### Working rules

| Doc | Read it when |
|---|---|
| `docs/STRUCTURE.md` | You are about to write a new doc, skill or command and need to know where it belongs |
| `profiles/<name>/` | The declared stack's rules, conventions, build and ship steps, and definition of done — whatever the active profile states |
| `docs/PATTERN-SEARCH.md` | Before grepping the codebase for an existing pattern |

### Reference — the machinery

| Doc | Read it when |
|---|---|
| `docs/INSTALL-MANIFEST.md` | Inspecting what an install did, or changing `install.sh` / `uninstall.sh` |
| `docs/SHARING.md` | Publishing this base for someone else; installer flags and exit codes in full |
| `docs/SCAN-TRAPS.md` | A scan result surprised you, or you are changing a scan script |
| `docs/CLAUDE-TASKS.md` | Editing a `CLAUDE.md` through the recorded nine-phase pipeline |

---

## 5. Files you look at, but never edit by hand

| File | What it is | Why not by hand |
|---|---|---|
| `.claude/notes/*.md` | The inventories the active profile declares, generated from the project. The mechanical ones come from `sync-notes.sh`; a partial one states in the note what its scan did *not* establish | Rows between the `GA:ROWS` markers are regenerated; everything outside them, including your prose, is never touched. Hand-edit a row only in the same change as the code it describes |
| `.claude/notes/.evidence/*.tsv` | Candidates for the parts no scan can settle — unused assets, which screen calls an endpoint | Regenerable and gitignored. Review them; do not treat a candidate as a row |
| `.claude/MAP.tsv` | Topic → which doc covers it. A kind marked `:remote` means "not on disk here, fetch it" | Add a row when you add a doc; otherwise leave it |
| `.claude/SCRIPTS.tsv` | Every script's contract, generated from the `#@` header inside each script | Change the header in the script, then run `register-scripts.sh` |
| `.claude/INDEX.md` | What your *product* has: features, vendors, resources | Small, hand-maintained, one row per thing |
| `.claude/CANDIDATES.tsv` | Things repeated once, watched to see if they repeat again | `/learn` writes it |
| `.claude/memory/` | What earlier sessions learned about this repo. In-repo so it survives a clone | `Scripts/memory-add.py` |
| `.genericarch/` | The install record: `manifest-<version>.json`, `TOMBSTONES.tsv` (which files were declined and why), `STEPS.tsv` (which steps ran), `orphans-*.txt` (what an uninstall could not remove) | Tooling owns all of it. Deleting the manifest makes a clean uninstall impossible |
| `.genericarch/safetodelete/` | The declined files themselves, at their original relative paths | **The one exception — this you may delete.** That is what the name means: it costs only the ability to `--revive`. Restore a file with `ga-remove.sh --revive <path> --apply`, not by moving it back by hand, or the tombstone will still be blocking it. It is **tracked**, so a teammate can see what was declined and reverse it; add it to `.gitignore` if you would rather keep retired files local |

---

## 6. Files that are not for you

Not secret — just not useful to a human, and not worth reading to understand the repo.

| Path | What it is |
|---|---|
| `.claude/skills/*/SKILL.md` | Procedures Claude follows. `tool-profile` in this repo |
| `.claude/commands/*.md` | The slash-command definitions from §2 |
| `Scripts/ga-lifecycle.sh`, `Scripts/claude-utils/_common.sh` | Shared libraries. Sourced by other scripts, never run directly |
| `Scripts/claude-workflows/01…09*.sh`, `run-task.sh` | The nine-phase pipeline for editing `CLAUDE.md` files under a record. **Optional** — only installed with `adopt.sh --with-meta` |
| `Scripts/*.py`, `Scripts/check-*.py` | Scanners and checkers that `/sync-app-notes` and `check.sh` drive |
| `Scripts/claude-utils/*.sh` | Cross-phase helpers: linting, link validation, registry generation, rollback |
| `Scripts/session-script.sh` | Stages a throwaway script for one session; promotes it only if a second session needs it |
| `Scripts/adopt.sh` | The copy engine. `install.sh` drives it — call it directly only to see what travels |
| `uninstallv0.1.0.sh` | Removes a pre-manifest v0.1.0 install. Keep it until no v0.1.0 installs remain |
| `.claude-plugin/plugin.json` | Plugin metadata for `build-plugin.sh` |

---

## 6b. When a script fails

Scripts are meant to run **as-is** — offline, with no model involved. When one cannot handle your
repo, it does not guess and it does not half-finish: it writes a bounded report to
`.genericarch/failures/<script>-N.md` naming what it expected, what it found instead, and your
machine's versions.

Give **that file** to Claude. It is about 45 lines; the script it describes is far longer. Claude
fixes the script so the next run is mechanical again, and deletes the report in the same change.

The shape of it: a scanner that expects one router enum whose `path` property switches over its cases
will find nothing in a project that registers its routes some other way — and it says exactly that,
with the numbers, instead of writing an empty table that would have looked complete.

## 7. Recipes

**Install into a project**

```bash
./install.sh /path/to/YourApp --dry-run     # read the plan first
./install.sh /path/to/YourApp
```

Then, in that repo, type `/project-init` → `/sync-app-notes` to Claude, in that order.

**A command said "cannot run yet"**

```bash
./Scripts/ga-step.sh show
```

Run the missing step. If it genuinely does not apply to your product, record that instead — with a
reason, so the next person knows why it was skipped:

```bash
./Scripts/ga-step.sh record sync-app-notes "not applicable: no code to inventory yet"
```

**Get rid of a file this thing installed**

```bash
./Scripts/ga-remove.sh docs/OPENSPEC.md --reason "not using OpenSpec here" --apply
./Scripts/ga-remove.sh --list          # what is declined
```

It prints what it did: where the file went, how many index rows it pruned, and every prose reference
still pointing at it — those it deliberately does not rewrite, because only you can tell whether the
sentence should go, change, or point somewhere else.

**Changed your mind**

```bash
./Scripts/ga-remove.sh --revive docs/OPENSPEC.md --apply
```

The file comes back byte-identical from `.genericarch/safetodelete/`. Two things it leaves to you:
the `DECISIONS.md` row (a reversal should read as one, not vanish) and the index rows —
`register-scripts.sh` regenerates them for a script, `MAP.tsv` needs the row re-added by hand.

**A file keeps coming back after you delete it** — you deleted it with `rm`. Decline it properly
with the command above, and it will not.

**Reclaiming the space**

```bash
rm -rf .genericarch/safetodelete/
```

Safe by design. You lose only `--revive`; the tombstones stay, so nothing comes back.

**Uninstall left files behind**

```bash
cat .genericarch/orphans-<version>.txt
```

Each line says why. They are files you edited, so the tooling will not delete them — keep or remove
them by hand.

**Rebuild the notes without spending a session**

```bash
./Scripts/sync-notes.sh --apply       # the profile's mechanical inventories — written outright
./Scripts/sync-notes.sh --evidence    # candidates for the ones that need a human or Claude
./Scripts/sync-notes.sh --check       # CI: exit 1 if a mechanical note drifted from the code
```

First run on an existing set of notes needs `--init-markers` once — it puts two HTML comments around
each generated table so nothing outside them is ever touched.

**Check nothing is broken after changing the installer**

```bash
./Scripts/ga-roundtrip.sh
```

**Update an installed repo to a newer version**

```bash
./Scripts/adopt-review.sh /path/to/YourApp            # what would change
./Scripts/adopt-review.sh /path/to/YourApp --take 1,4 # take only the ones you chose
```

---

## 8. What costs you tokens, and what does not

Worth knowing, because it drives most of the design decisions above.

| Loaded every session | Loaded only when used | Never loaded unless read |
|---|---|---|
| `CLAUDE.md` | A skill or command body, when it fires | Every `.sh` and `.py` file |
| Skill and command descriptions | A doc or note, when looked up | `docs/`, `.claude/notes/`, `profiles/` and the source tree |
| | A `MAP.tsv` / `SCRIPTS.tsv` row, when grepped | the active profile, until a task is stack-specific |

So: the scripts cost nothing until something reads them, while one paragraph added to `CLAUDE.md` is
paid for on every single session. **Deleting a doc saves nothing** — it was never loaded. What
actually helps, in order:

1. **Shrink your own `CLAUDE.md`** if it duplicates what the notes now own — endpoint tables, env
   tables, folder trees. On a real app that was ~4,000 tokens per session.
2. **Route per task, not per session.** A grep of `MAP.tsv` when you build costs less than a routing
   table every session that does not.
3. **Move work into scripts.** Not a standing cost at all — it is what a `/sync-app-notes` run stops
   spending. The profile's mechanical notes then cost nothing.
4. **Leave the docs alone.** They are the cheap half of the design.
