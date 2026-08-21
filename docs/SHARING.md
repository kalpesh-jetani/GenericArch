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
| `.swiftlint.yml`, `.swiftformat` | Read by the linter |

### 2. Referenced — listed, fetched when read

All of `docs/` except the two below. `genericarch.installation.md` carries the index: every path, what
is there, and when to read it, pinned to a commit. **A `docs/…` link that is not on disk is a fetch
instruction, not a broken link.**

Nothing to keep in sync, nothing to go stale, and 21 files a consumer may never open stay out of
their repo.

### 3. Scaffolded — created empty, never copied

`docs/DECISIONS.md`, `docs/GAPS.md`, the eight `.claude/notes/*`, and `.claude/memory/`
(its `INDEX.md` only — our memories are ours). All are **written to** —
`/decide`, `/gaps` and every insertion or deletion edit them. Copying this product's versions would
hand over its answers; referencing them would make them unwritable. So: created fresh.

### 4. Resolved — SPM dependencies, never copied

| Package | Reaches a consumer as |
|---|---|
| `GenericArch-NetworkKit` | an SPM dependency by URL, pinned with `.upToNextMajor(from:)` |
| `GenericArch-ImageCache` | the same |

```swift
.package(url: "https://github.com/kalpesh-jetani/GenericArch-NetworkKit.git", from: "1.0.0")
```

They carry **zero dependencies** — not even `Core` — so any product resolves them without inheriting
this architecture. A consumer that vendors the source has undone the extraction and owns a fork.
They need to exist only for a consumer that uses them, and they are the one layer where an update
reaches every consumer by bumping a version.

### Never travels

`CLAUDE.md` (the target's rules are its own), `README.md`, `Packages/`, `App/`,
`.claude/settings.json` (per-machine consent), `.claude-plugin/`.

`Scripts/adopt.sh` enforces all of this, and **refuses to run** if a file is in none of the lists.

**"Never travels" is a statement about the installer, not about GitHub.** A template copy
(`gh repo create --template`) is made by GitHub, which copies every **tracked** file — so `Packages/`,
`App/`, `README.md`, `CLAUDE.md` and `.claude-plugin/` all land in the new repo, and no list here
stops them. Two consequences worth knowing before relying on either:

- **No file can identify this repo.** Treating `.claude-plugin/` as the marker for "this is
  GenericArch itself" made every template copy answer to it, which recorded `scaffold` as
  not-applicable in a brand-new product and then refused to scaffold it. The tree is identical; the
  **history** is not, which is what `ga_is_source_checkout` reads instead
  ([Scripts/ga-lifecycle.sh](../Scripts/ga-lifecycle.sh)).
- **A template copy inherits this product's state**, including its floors and its `.gitignore`. The
  reset is manual and it is listed in [README.md](../README.md) path A step 1.

---

## Option 1 — Template repository · for a **new** product

Best when the product starts from nothing. One command, no local checkout to install from, no
history — but **not everything present**: GitHub copies the tracked tree, and `Packages/` holds only
the `Core`+`DIKit` floor while `App/` does not exist here at all. The structure is still scaffolded,
and this product's state still has to be cleared. Full sequence: [README.md](../README.md) path A.

```bash
# once, on the base repo
gh repo create kalpesh-jetani/GenericArch --private --source=. --push
gh repo edit kalpesh-jetani/GenericArch --template

# per new product
gh repo create kalpesh-jetani/MyApp --template kalpesh-jetani/GenericArch --private --clone
cd MyApp
```

**Reset the inherited state first** — a template copies it wholesale, and `/project-init` reconciles
rules against whatever it finds:

```bash
./Scripts/detect-toolchain.sh     # §1 must describe THIS machine, not GenericArch's
# drop this product's answers from DECISIONS.md
# reset GAPS.md statuses to ▶ Open
# clear .claude/notes/ table bodies
# drop .genericarch/ from .gitignore — in a product that state is tracked
```

**Then scaffold**, because `scaffold` is genuinely pending in a copy (`ga-step.sh` records only
`install`):

```bash
./Scripts/ga-scaffold.sh . --list
./Scripts/ga-scaffold.sh . --with navigation,design --apply
```

Then in Claude Code: **`/project-init MyApp`** — asks for bundle ID, Team ID, v1 languages, the open
§1.1 visual-language decision, and permissions per group. Then `/gaps`, then `/sync-app-notes`.

| Good | Bad |
|---|---|
| One command to a working repo; rules, docs and tooling included | Inherits state that must be reset by hand — floors included |
| No sync obligation — the fork is yours | Divergence is permanent; later base fixes don't reach it |

## Option 2 — Plugin · for the **tooling layer**, across many repos

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
| Each product keeps its own CLAUDE.md | `/verify`, `/decide`, `/gaps` need the docs adopted too |

## Option 3 — Installer · for an **existing** codebase

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

Installs the tooling, writes `genericarch.installation.md` for the reference docs, scaffolds what
gets written to, and **never overwrites** — an existing file is reported as a collision and kept.
Then:

1. **`/project-init`** — follows [ADOPTION.md](ADOPTION.md): reads their CLAUDE.md in full, builds the rule-conflict table (CocoaPods vs
   SPM, UIKit vs SwiftUI, Combine, existing DI, min OS), classifies each honestly, and asks per
   conflict with **keep-theirs as the default**. *Adopt for new code only* is usually the right
   answer for a hard conflict — it's the only option honest about code that already exists.
2. **`/gaps`** — derives status from their code instead of asking; reports missing safeguards as
   risks rather than silently skipping them.
3. **`./Scripts/check.sh`** — expect failures. That is the point; triage them above.

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
| `3` | **Compatibility mismatch** — the target is not a macOS/Swift project. Nothing was written. `install.sh --force` overrides |
| `4` | Aborted at the confirmation prompt |
| `78` | **Not macOS** — `install.sh` and `bootstrap.sh` refuse before writing or fetching. No override: macOS is a fixed choice, not a default. `uninstall.sh` deliberately has no such gate, so an install that predates it can still be removed |

`3` is distinct so CI can tell "this repo is not a Swift project" (expected) from "the install
broke" (`1`) without parsing output.

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
`docs/DECISIONS.md`, `docs/GAPS.md` — have no shipped blob to compare against, so a fallback
uninstall keeps them and lists them.

Full format reference: [INSTALL-MANIFEST.md](INSTALL-MANIFEST.md).

### Updating an install — the consumer decides, per file

`install.sh` never overwrites. That is the right default and it has a cost: once a repo has adopted,
a fix upstream reaches it only if someone goes and gets it, and *"0 collisions kept as-is"* says
nothing about whether the incoming file even changed.

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

`install.sh` refuses to touch `CLAUDE.md` at all, which protects a consumer's rules but means a
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
pipeline that edits it under a record, with its own approval gate ([CLAUDE-TASKS.md](CLAUDE-TASKS.md)).

---

## Which layer to keep in sync — and which not to

Don't try to sync all of it. Three layers, three honest answers:

| Layer | Strategy |
|---|---|
| `GenericArch-{NetworkKit,ImageCache}` | **Already solved** — separate repos, semver over SPM. A consumer bumps a version; no files move. Category 2 above |
| Skills, commands, lint config | **Genuinely shared** → Option 2, the plugin |
| `CLAUDE.md`, `docs/` | **Let them diverge** |

That last row is a recommendation, not a shrug. These are a product's rules. The moment two products
need different persistence engines or a different minimum OS, a shared rules file becomes a blocker
and someone edits it for everyone. Divergence here is correct behaviour, not debt.

## Before you share

- [ ] `git init` and a first commit exist, with `.build/` excluded — it is ~49 MB of artifacts
- [ ] **A tag exists and README's install URL points at it.** `install.sh` defaults to a pinned ref;
      if that tag isn't pushed, every consumer silently falls back to the default branch
- [ ] `install.sh` tested against both a fresh and an existing repo — the existing case is the one
      that can damage someone's work
- [ ] The two extracted packages are **published as their own repositories and tagged** —
      `GenericArch-NetworkKit`, `GenericArch-ImageCache`. Consumers resolve them by URL; their source
      is never copied into a consuming repo, so an untagged or unreachable repo is what breaks, not a
      missing file. Each must build and test standalone with **zero dependencies** (CLAUDE.md §4.2)
- [ ] `./Scripts/check.sh` and `Scripts/check-skill-triggers.py` pass
- [ ] **`./Scripts/detect-toolchain.sh` is clean** — §1 is detected from the machine and the project
      file, not hand-written, and `check.sh` fails when it drifts. Each consumer detects its own;
      never inherit GenericArch's numbers
- [ ] Decide on the name. Keeping `GenericArch` means it appears in every consumer's dependency list
      and scheme names — fine if each product forks the blueprint, odd if several share these repos
