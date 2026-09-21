# Sharing GenericArch

Three ways to hand this to someone else. They are not alternatives to pick once — most teams end up
using two of them, for different layers.

- **When to read this:** you are the one **publishing** this base.
- **Consumers read the repo's `README.md`** instead — it has the copy-paste install for each
  case (github.com/kalpesh-jetani/GenericArch). Keep the two in step: the version pinned in README's `curl` URL must be a tag that exists.

---

## Four categories

### 1. Copied — must be local to function

| What | Why it cannot be lazy |
|---|---|
| `.claude/skills/*`, `.claude/commands/*` | Claude Code discovers them from disk; a fetched skill never fires |
| `.claude/MAP.tsv` | Grepped on every task to route to a doc — a fetched map costs more than it saves |
| `Scripts/*` | Executed, and referenced by CI |
| `profiles/` | The stack-profile mechanism — a consumer authors a profile against it |

### 2. Referenced — listed, fetched when read

All of `docs/` except the two below. `genericarch.installation.md` carries the index: every path, what
is there, and when to read it, pinned to a commit. **A `docs/…` link that is not on disk is a fetch
instruction, not a broken link.**

Nothing to keep in sync, nothing to go stale, and 21 files a consumer may never open stay out of
their repo.

### 3. Scaffolded — created empty, never copied

`docs/DECISIONS.md`, the `.claude/notes/*`, and `.claude/memory/`
(its `INDEX.md` only — our memories are ours). All are **written to** —
`/decide` and every insertion or deletion edit them. Copying this product's versions would
hand over its answers; referencing them would make them unwritable. So: created fresh.

### Never travels

`CLAUDE.md` (the target's rules are its own), `README.md`,
`.claude/settings.json` (per-machine consent), `.claude-plugin/`.

`Scripts/adopt.sh` enforces all of this, and **refuses to run** if a file is in none of the lists.

**"Never travels" is a statement about the installer, not about GitHub.** A template copy
(`gh repo create --template`) is made by GitHub, which copies every **tracked** file — so
`README.md`, `CLAUDE.md` and `.claude-plugin/` all land in the new repo, and no list here
stops them. Two consequences worth knowing before relying on either:

- **No file can identify this repo.** A copy's tree is identical, marker files included, so no
  marker can stand in for identity. The **history** is what differs, and it is what
  `ga_is_source_checkout` reads ([Scripts/ga-lifecycle.sh](../Scripts/ga-lifecycle.sh)).
- **A template copy inherits this product's state**, including its floors and its `.gitignore`. The
  reset is manual — see *The template path is withdrawn* below.

---

## The template path is withdrawn

This repo was briefly a GitHub template. It no longer is (`gh repo edit … --template=false`), because
a copy is made by GitHub rather than by an installer, and **removability comes from the installer**:
no manifest means `uninstall.sh` refuses the repo as an incomplete install — nothing can prove which
files were ours — and `ga-reseal.sh` has nothing to keep honest. A copy also arrives holding this
product's decisions, gaps, notes, memory and deployment floors as if they were its own.

One thing a copy does **not** lose: *Updating an install* below. `adopt-review.sh` classifies by
comparing content against a base checkout and never reads a manifest, so a fork can still pull an
upstream fix per file.

**If you already have a copy**, it is a fork, not an install. It is usable — nothing about it is
broken — but treat it as one:

```bash
./Scripts/detect-toolchain.sh --mismatches   # inherited floors first: BLOCKING cannot build
```

Then clear the inherited state by hand: the per-product rows in `docs/DECISIONS.md`, the
`.claude/notes/` table bodies, every `.claude/memory/` file **and its `## Index` row**, any
authored `profiles/<name>/`, and `.genericarch/` in `.gitignore` — ignored correctly in this repo,
wrong in a product. `Scripts/ga-lifecycle.sh` recognises a copy for what it is
(`ga_is_template_copy`), so the lifecycle commands still sequence correctly there.

For a genuinely new project, create the project with your stack's own tooling first, then install
this layer afterwards.

## Option 1 — Plugin · for the **tooling layer**, across many repos

Ships only skills and commands, installable anywhere, updated centrally. This is the right answer
when several products should share the *tooling* while keeping their own rules.

```bash
./Scripts/build-plugin.sh 0.1.0        # generates dist/genericarch/
cd dist/genericarch
git init && git add -A && git commit -m "genericarch plugin 0.1.0"
gh repo create kalpesh-jetani/genericarch-plugin --public --source=. --push
```

In any repo:

```
/plugin marketplace add kalpesh-jetani/genericarch-plugin
/plugin install genericarch
```

The plugin is **generated, never hand-edited** — `.claude/skills` and `.claude/commands` stay the
single source of truth. A hand-copied plugin drifts, and a doc that drifts from its source is worse
than none.

| Good | Bad |
|---|---|
| One install; central updates reach every repo | Tooling only — no rules, docs, or code |
| Each product keeps its own CLAUDE.md | `/verify`, `/decide` need the docs adopted too |

## Option 2 — Installer · for an **existing** codebase

Consumers run `install.sh` from inside their own repo — it fetches a pinned tag and delegates to
`adopt.sh`, so the "what travels" list lives in exactly one place:

```bash
# what a consumer runs, from their repo
curl -fsSLO https://raw.githubusercontent.com/kalpesh-jetani/GenericArch/v0.1.0/install.sh
bash install.sh --apply
```

`adopt.sh` is still the direct path when you already have a checkout:

```bash
cd /path/to/GenericArch
./Scripts/adopt.sh /path/to/ExistingApp             # dry run — shows the plan
./Scripts/adopt.sh /path/to/ExistingApp --apply
```

Installs the tooling, writes `genericarch.installation.md` for the reference docs, creates the
per-product files empty, and **never overwrites** — an existing file is reported as a collision and kept.
Then:

1. **`/project-init`** — follows [adoption/ADOPTION.md](/docs/adoption/ADOPTION.md)(/docs/adoption/ADOPTION.md): reads their CLAUDE.md in full, builds the rule-conflict table
   (the conflicts the active profile names — build system, framework, dependency management,
   existing conventions), classifies each honestly, and asks per conflict with **keep-theirs as the
   default**. *Adopt for new code only* is usually the right answer for a hard conflict — it's the
   only option honest about code that already exists.
2. **`./Scripts/check.sh`** — expect failures. That is the point; triage them above.

| Good | Bad |
|---|---|
| Non-destructive; their rules survive | Rule adoption is a negotiation, not a copy |
| Works on a codebase that violates half the rules | Base updates need re-running the script |

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
| `3` | **Compatibility** — reserved; the stack gate now only sets a hint and never refuses, so this is effectively unused |
| `4` | Aborted at the confirmation prompt |
| `78` | **Unsupported host** — no SHA-256 tool (`shasum`/`sha256sum`). `install.sh` and `bootstrap.sh` refuse before writing or fetching. `uninstall.sh` deliberately has no such gate, so an install that predates it can still be removed |

`78` is distinct so CI can tell "this host cannot run the tooling" from "the install broke" (`1`)
without parsing output.

### What "user-edited file preserved" means

When `uninstall.sh` reports:

```
  KEPT — not deleted
    · .claude/MAP.tsv
        you edited it — content hash does not match the manifest
```

…the file's current sha256 differs from the hash recorded when it was installed. **Someone changed
it after install — so it is left exactly where it is, and nothing about it is modified.**

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
`docs/DECISIONS.md` — have no shipped blob to compare against, so a fallback
uninstall keeps them and lists them.

Full format reference: [INSTALL-MANIFEST.md](/docs/reference/INSTALL-MANIFEST.md)(/docs/reference/INSTALL-MANIFEST.md).

### Moving to a new version — uninstall, then install

**This is the sanctioned upgrade**, and `install.sh` now enforces it: a manifest recording a
different version stops the run with exit `6` and names the command to run.

```bash
./uninstall.sh v0.5.0     # from the target; edited files survive, and are listed
./install.sh /path/to/YourApp
```

Installing over an older release was never an upgrade. A file GenericArch installed, that nobody
touched, and that the base has since changed, is reported as *"left at older version"* and left
there — only shared libraries move forward, and only because their callers break otherwise. So a
v0.4.2 → v0.5.0 run left most of v0.4.2 on disk under a v0.5.0 manifest.

Removing first costs nothing: a file comes out only while its hash still proves it is GenericArch's,
so anything edited survives. `uninstall.sh` lists those in `safetodelete-after-migration-note.md` at
the repo root, and the next `install.sh` reads it and records them as `orphan` — tracked, never
rewritten, never deleted. `--in-place` keeps the old behaviour for anyone who wants it.

### Updating one file at a time — the consumer decides, per file

For a fork, or for taking a single upstream fix without a version move, `install.sh` never
overwrites. That is the right default and it has a cost: once a repo has adopted, a fix upstream
reaches it only if someone goes and gets it, and *"0 collisions kept as-is"* says nothing about
whether the incoming file even changed.

`adopt-review.sh` is that missing half. It classifies every shipped path against the target and
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

Identical files are not listed — they would bury the decisions. Then take only what is wanted:

```bash
./Scripts/adopt-review.sh /path/to/YourApp --take 2,3
```

Exit `0` means the target matches the base, `1` means decisions are pending — so it also works as a
CI staleness gate. **Claude reports this table and never passes `--take`:** overwriting a file in a
shipping repo is the owner's call, and an approval never carries to the next run.

#### CLAUDE.md gets the same treatment, one section at a time

`install.sh` leaves `CLAUDE.md` alone unless asked. `--with-claude-md` is the one way it writes
that file: the consumer's copy moves to `CLAUDE-BK.md`, the swap is recorded in the manifest as
`replaced`, and `uninstall.sh` puts their original back byte-for-byte, verified against its recorded
hash. Off by default — protecting a consumer's rules is still the right default, and it means a
genuinely useful new rule can never reach a project that already adopted. `adopt-review.sh` compares
it **by numbered section** instead of as a file:

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
pipeline that edits it under a record, with its own approval gate ([CLAUDE-TASKS.md](/docs/operations/CLAUDE-TASKS.md)(/docs/operations/CLAUDE-TASKS.md)).

---

## Which layer to keep in sync — and which not to

Don't try to sync all of it. Three layers, three honest answers:

| Layer | Strategy |
|---|---|
| Skills, commands, indexes, scripts | **Genuinely shared** → Option 1, the plugin |
| `CLAUDE.md`, `docs/`, `profiles/<name>` | **Let them diverge** — a product's rules and its stack are its own |

That last row is a recommendation, not a shrug. These are a product's rules. The moment two products
need different persistence engines or a different minimum OS, a shared rules file becomes a blocker
and someone edits it for everyone. Divergence here is correct behaviour, not debt.

## Before you share

- [ ] `git init` and a first commit exist, with `.build/` excluded — it is ~49 MB of artifacts
- [ ] **A tag exists and README's install URL points at it.** `install.sh` defaults to a pinned ref;
      if that tag isn't pushed, every consumer silently falls back to the default branch
- [ ] `install.sh` tested against both a fresh and an existing repo — the existing case is the one
      that can damage someone's work
- [ ] `./Scripts/check.sh` and `Scripts/check-skill-triggers.py` pass
- [ ] **`./Scripts/detect-toolchain.sh` is clean** — §1 (the stack) is declared by the active
      profile, not hand-written here; each consumer declares its own and never inherits GenericArch's
- [ ] Decide on the name. Keeping `GenericArch` means it appears in every consumer that installs it
      — fine if each product forks the blueprint, odd if several share it
