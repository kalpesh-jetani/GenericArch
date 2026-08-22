# Changelog

Releases of the GenericArch base. A version is a tag; `install.sh` records it in the target's
manifest and `uninstall.sh` validates against it, so a release name is load-bearing rather than
decorative.

---

## v0.5.0

The theme: **an upgrade over an older install now works, and no command deletes as a side effect.**
Both came out of adopting this base into a repo that already carried v0.2.0 — where the install
succeeded, reported success, and left seven scripts that could not run.

### The upgrade bug, and why it was silent

`install.sh` is additive by contract: nothing existing is ever overwritten. That is right for a
product's own files and wrong for a **shared library**, because the scripts shipped beside it
`source` it. Upgrading over v0.2.0 skipped `ga-lifecycle.sh` as a collision and installed seven new
scripts against it, so every one failed with `command not found` — **while still exiting 0**, which
is why nothing anywhere reported it.

- A staged file whose `#@kind` is `lib` is now **upgraded in lockstep** with its callers instead of
  being kept. The manifest already proves such a copy is ours and unedited, so nothing local is at
  stake; the previous bytes are backed up under `.genericarch/backups/` regardless.
- A library the target has *edited* still wins — their file always does — but it is now named in a
  warning that says its callers may fail, rather than disappearing into the skip list.
- `ga-roundtrip.sh` case 3b pins it. It fails against the old installer.

### Removal is one command's job now, not every command's

`/project-init` no longer deletes anything — not a doc, not a skill, not a rule. It reports
candidates and stops. A removal is four coupled writes (the file moves to `safetodelete/`, a
tombstone lands, `MAP.tsv` and `SCRIPTS.tsv` rows are pruned, a `DECISIONS.md` row is written), and
that pruning also strips the path out of the index and memory directories later lookups depend on.
Interleaved with rule reconciliation it was unreviewable, and unpickable-apart if a conflict answer
changed.

- **`/clean-up-genericarch-extra-memory`** owns every deletion, asking per candidate.
- **`/sync-with-genericarch`** brings an install up to the base and promotes the patterns the code
  now justifies — the half that had no command, so a repo sat 27 files behind with nothing pointing
  at `adopt-review.sh`.
- Both are backed by read-only, offline scripts: **`ga-cleanup-scan.sh`** and **`ga-sync-scan.sh`**.
  The scanners gather evidence; the commands hold the judgement. `ga-sync-scan.sh` stops with exit 1
  when a checkout carries two install roots, because a sync would faithfully update the wrong one.
- `S2b`/`S2c` in `/project-init` described a v0.2.0 installer — deleting the 12 `docs/modules/*.md`
  and the `release-bump` skill. None of those has been installed since v0.4.2 made module docs
  fetch-on-demand and the architecture layer opt-in. Roughly 40 lines of dead instructions, rewritten.

### Three tools were reading the wrong directory

All three assumed the install root is the git root. It is not when the Xcode project sits one level
down from its checkout, which is the common shape.

- `detect-toolchain.sh` never read `project.pbxproj` — the only place a repo with no `Packages/`
  states its floors — so it declared "fresh repo" and substituted the host SDK. It reported **min
  iOS 26.5 for an app whose pbxproj says 16.0**. It now reads the pbxproj, takes the lowest value
  across configurations, and ranks below an explicit `.xcconfig`. When nothing states a floor it
  reports `unset` instead of inventing one.
- `find.sh` and `notes-staleness.sh` resolved to the git root and read an absent notes directory,
  answering "No row" for terms the populated notes documented. Both now walk up from the caller.
- `adopt-review.sh --take` on `.claude/MAP.tsv` dropped the `FETCH-BASE` stamp, because the base does
  not carry one — install stamps it. Every fetched `docs/` row stopped resolving, with the rows still
  in place, pointing nowhere. The stamp is now carried across.

### Fixed

- `ga_json_field` scans a single line, so every top-level lookup against a pretty-printed manifest
  returned empty. Callers that needed `source_ref` read it directly.
- `ga-remove.sh`'s header still said `/project-init` "is told to delete module docs".

---

## v0.4.2

The theme: **this base installs into a repo that already has its Xcode project, and nothing else.**
The package layout it used to write moved to its own repo, and with it every code path that existed
for a directory with no shape yet.

### Two repos, because they answer different questions

- **[GenericXCodeSetup](https://github.com/kalpesh-jetani/GenericXCodeSetup)** now owns
  `Scaffold/` and its templates, `ga-scaffold.sh`, the `Core`+`DIKit` reference packages, and the
  pre-project checklist. It stands alone on a 141-line `gxs-common.sh` vendored from this repo's
  711-line `ga-lifecycle.sh`: no manifest, no tombstones, no step ledger, because it installs
  nothing.
- **This repo** keeps the rules, docs, skills, commands, indexes and lifecycle tooling. Every
  guarantee here comes from the installer — a manifest, hashes, a reversible uninstall — and none of
  it means anything in an empty directory, so `install.sh` now **refuses** one and points at the
  other repo.

### One install shape

- `--mode existing|new` is gone, along with `--fresh` in `adopt.sh`, the two-install table, and the
  20 `MODE` branches that asked which one this was.
- **The `scaffold` step is gone from the ledger**: `install → /project-init → /gaps →
  /sync-app-notes → ready`. A consumer ledger written earlier may still carry a `scaffold` row; it is
  ignored, because the gate iterates the step list and not the file.
- `ga-project-setup.sh` is **adopt-only** and now part of every install: it writes the five
  `.xcconfig` files an existing project should reference, and its checklist dropped the two
  "create the project" sections — steps you cannot follow are worse than steps you do not get.
- `ga_known_paths` gains a `v0.4.2` entry (44 paths — v0.4.1's 46 without `Scaffold` and
  `ga-scaffold.sh`). **The v0.1.0–v0.4.1 entries are untouched**: a repo that installed one of those
  still needs them to uninstall cleanly.

### Postmortem comments removed

Thirteen comments and sentences that narrated what a *previous* version got wrong are gone from the
scripts and the docs — the defects were fixed, so the notes described code that no longer existed.
`docs/CONVENTIONS.md`'s *Doc comments, not meta comments* rule now says it applies to every file the
repo ships rather than only Swift `///`, carries a shell example of the failing shape, and names the
test: **tense**. A rule about what must hold stays; an account of what once failed belongs to the
commit that fixed it. `DECISIONS.md`, `.claude/memory/` and `CHANGELOG.md` are exempt — recording
history is their contract, and the three rows this release adds to `DECISIONS.md` are where its
history went.

### Also

- The GitHub template path is **withdrawn** — the repo's template flag is off. A copy no installer
  wrote has no manifest, so `uninstall.sh` refuses it and `ga-reseal.sh` has nothing to keep honest.
  `ga_is_source_checkout` still tells a copy from this checkout, by **history** rather than by
  marker files, because copies made while the flag was on still exist.
- `.claude/memory/` lost the memory whose whole subject was the removed scaffolder; `verify-memory.sh`
  reports a bijective index of 2.
- `plugin.json` 0.4.0 → 0.4.2, description matching what now ships.

## v0.4.1

Docs and tooling caught up with the withdrawn template path: `README.md` dropped it as an install
route, `SHARING.md` gained the reason, and `ga_is_source_checkout` / `ga_is_template_copy` replaced
the marker-file check that had made every template copy answer to it. No footprint change, so
`ga_known_paths` treats v0.4.1 exactly as v0.4.0.

## v0.4.0

The theme: **an empty directory is now a supported starting point**, and the command that adopts a
repo stops paying for what a script can prove. v0.3.0 moved the note generation out of the session;
this moves the project setup and half of `/project-init` out with it.

### An empty directory is a first-class path

- **`Scripts/ga-project-setup.sh`** — the part of project creation that *is* mechanical: the Xcode
  toolchain gate, the four committed `.xcconfig` files with per-stage bundle IDs, and an exact
  `XCODE-SETUP.md` checklist. It never creates, opens or edits an `.xcodeproj` — SPM stays the source
  of truth (CLAUDE.md §1), and a hand-authored `pbxproj` is a binary nobody could review.
- **`install.sh` offers it** before writing anything, so a missing toolchain costs nothing: a
  toolchain gate failure exits 3 with the target untouched. `--project-setup` forces it,
  `--no-project-setup` never offers it, and with no tty it is skipped rather than failing an install
  that was otherwise fine — a bundle ID, a Team ID and a deployment floor may not be defaulted (§0).
- **The bare-`.xcodeproj` case is caught.** An `.xcodeproj` is an Apple marker, so the compatibility
  gate read "project you just created in Xcode" as an *existing* repo and skipped `Scaffold/` and
  `ga-scaffold.sh` — the package layer that had not been written yet. The install now says so and
  offers `--mode new`, reprinting the mode rather than correcting it silently.
- `README.md` gains that path as **B. New project — from an empty directory**, and the
  eighth of "the rules that matter most".

### Half of `/project-init` now runs offline

- **`Scripts/ga-init-scan.sh`** — the deterministic half of the command, as a read-only script: the
  mode (from the same gate `install.sh` uses), the toolchain mismatches, one evidence row per
  `docs/ADOPTION.md` §A2 conflict with counts and example paths, the §A4 name collisions, the
  routable-path validator that used to be 35 lines of inline bash, the orphan module docs, and which
  of the four rule levels exist. Every count carries its method's blind spot in the same row.
- **`install.sh` runs it** once the manifest has landed and writes
  `.claude/notes/.evidence/INIT-SCAN.md` plus a machine-readable `INIT-CONFLICTS.tsv`. The next
  session reads one artifact instead of paying for four rounds of grep. `--no-preflight` skips it.
- **`install.sh` also says when the repo does not build** — a BLOCKING row from
  `detect-toolchain.sh --mismatches` is reported rather than refused, because rules and tooling are
  still correct in a repo whose floors need lowering. The refusal stays where it belongs:
  `ga-init-scan.sh` exits 3, and `/project-init` inherits it.
- **What it deliberately does not do:** classify a conflict, write a rule, touch `CLAUDE.md`,
  remove a file, or record the `project-init` step. A script marking the asking step done would
  unblock `/gaps` against rules nobody accepted.
- `uninstall.sh` removes the generated evidence, and `ga-roundtrip.sh` case 11 proves it — the first
  files `install.sh` creates that the manifest does not own.

### A cross-repo call read the wrong repo — every time

- **`detect-toolchain.sh` gains `--root`**, and no longer `cd`s to its own checkout unconditionally.
  Every caller that installed or scaffolded *into* another repo was silently reading GenericArch's
  own floors and reporting them as the target's. `ga-scaffold.sh` wrote them into every manifest it
  generated; the code even read `$(cd "$TARGET" && …)` and claimed it had scanned the target.
- `--mismatches` now documents its contract: exit 0 always, including when a BLOCKING row stands.
  Callers gate on the rows, never on the status.

### §2.12 rewritten: build to validate, ask before running

- Claude **compiles on its own initiative** — usually through `./Scripts/check.sh`, whose iOS-floor
  step is the slow part — and reports what came back. **Running and testing still need consent:**
  `swift test`, `xcodebuild test`, any simulator or device launch. `/build` is that consent for the
  run it names and does not carry to the next one.
- `check.sh` is reclassified `never:compiles-the-iOS-floor` → `call` in the registry, and
  `docs/BUILD-PROCESS.md` matches. The old rule made the repo's own gate the one thing that could
  never be run, so a change was reported as validated by whoever remembered to ask.

### The scaffold step stops blocking its own author

- `ga-step.sh` derives **scaffold** as not-applicable in a GenericArch checkout, for the same reason
  it already derived `install`: this repo *is* the structure `ga-scaffold.sh` creates. `/project-init`
  used to refuse in the repo that authors the scaffolder, with an operator `--force` as the only
  documented escape.
- `ga-scaffold.sh` takes `--yes`, like `install.sh` and `uninstall.sh`. Without it, `--apply` from CI
  or a pipe reached the confirm prompt, found no tty, and stopped.
- `ga_confirm` stops advising `--yes` to callers that have no such flag; every non-interactive caller
  is pointed at `GA_ASSUME_YES=1`, which works everywhere. The old remediation sent
  `ga-scaffold`/`ga-remove`/`ga-reseal`/`adopt.sh` into an "unknown flag" exit.

### Scanners survive the repos they meet

- **`scan-fonts.py`** no longer aborts the whole FONTS inventory on one unparseable file. A `.ttf`
  extension is not a promise of a parseable sfnt — Git-LFS pointers, stubs and truncated binaries all
  carry one. Each is named on stderr and skipped.
- **`sync-notes.sh` NAVIGATION** counted call sites wrong in both directions: it subtracted a flat 1
  for a declaration the pattern had never matched, and counted `case .route:` in a destination switch
  as a navigation. It now excludes the mapping lines and subtracts nothing — the old arithmetic
  undercounted every route by one and reported a route with exactly one call site as dead.
- Several `|| echo 0` fallbacks became `|| true`. Under `grep -c`, the first appended a literal `0`
  to a count that already existed.

### Written down rather than fixed silently

`docs/GAPS.md` gains four rows, each measured rather than suspected:

- **A release that does not publish its tag** poisons every installed `MAP.tsv`: `FETCH-BASE` points
  at a tag that 404s and `bootstrap.sh` resolves the *previous* release instead. Measured on v0.3.0:
  52 dead rows, the same paths returning 200 at v0.2.0. The one failure a local round trip cannot see.
- **`ga-handoff.sh` resolves `.genericarch/failures/` from the working directory**, so running a
  target's script from elsewhere writes the diagnosis into an unrelated repo.
- **Who owes the reseal** — `sync-notes.sh --apply` and `notes-staleness.sh --stamp` rewrite installed
  notes and reseal nothing, so uninstall preserves a note and tells the operator *"you edited it"* for
  a write GenericArch made.
- **What counts as "source"** — one scanner walks the filesystem, the other enumerates tracked files,
  and nothing says which is authoritative.

### Version plumbing

- `GA_LATEST_VERSION` → `v0.4.0`, and v0.4.0 added to the supported list.
- `ga_known_paths` gains a v0.4.0 entry — v0.3.0's footprint plus `ga-project-setup.sh` and
  `ga-init-scan.sh`. The generated evidence directory is deliberately absent from it: nothing can
  hash-prove ownership of a file the installer generated, so `uninstall.sh` removes it by name.
- `plugin.json` 0.3.0 → 0.4.0, with a description matching what now ships.

---

## v0.3.0

The theme: **work moves out of the session.** A release ago the model ran the scans, wrote the
rows, and re-derived the same answers next time. Now scripts do what is provable, say what they
could not prove, and hand over a diagnosis when they fail.

### The command sequence is enforced

`install → scaffold* → /project-init → /gaps → /sync-app-notes → ready` *(scaffold: new repos only)*

- **`Scripts/ga-step.sh`** — a step ledger in `.genericarch/STEPS.tsv`. Every command's first step
  is a gate; an out-of-order run exits 5 having written nothing. `--force` exists for an operator
  and never for Claude.
- Out of order, these commands did not fail before — they succeeded against the wrong input, which
  is worse. `docs/SEQUENCE.md` records why each position matters.

### A deletion now sticks

- **`Scripts/ga-remove.sh`** — retiring a file **moves** it to `.genericarch/safetodelete/`,
  tombstones it, prunes its rows from `MAP.tsv` and `SCRIPTS.tsv`, and records the reason in
  `DECISIONS.md`. `--revive` puts it back byte-identical.
- `install.sh` consults tombstones before creating a file. Previously "absent from disk" and
  "never installed" were the same state, so every deliberate deletion came back — four times in
  one adoption before anyone noticed.
- **`Scripts/ga-reseal.sh`** — commands that rewrite installed files now re-hash them, so they
  stay removable. An edited file whose hash no longer matched the manifest could never be
  uninstalled.
- `uninstall.sh` writes `.genericarch/orphans-<version>.txt` and **exits 1** on a partial removal.
- Because v0.3.0 transforms `MAP.tsv`, `SCRIPTS.tsv` and the scaffolded notes at install time, the
  no-manifest fallback cannot prove ownership of those and preserves them — the manifest path
  removes them cleanly ([INSTALL-MANIFEST.md](docs/INSTALL-MANIFEST.md)).

### Two installs, one difference

- `install.sh --mode existing|new`, derived from the compatibility gate.
- **Existing repos get no module material** — no `Packages/`, no `docs/modules/`, no scaffold, and
  no
  `new-feature`/`/review`, because both enforce rules such a repo has not adopted. `/project-init`
offers them once the rule-conflict table is settled; `--with-architecture` takes them up front.
- **New repos** additionally get `Scaffold/` and **`Scripts/ga-scaffold.sh`**: the layout, the
  `Core`+`DIKit` seed, the layer they choose, and `Scaffold/ARCHITECTURE-OPTIONS.md` to choose from.
- **No version is ever written for you.** Deployment floors come from `detect-toolchain.sh`
  reading the target's own manifests, or from `--ios`/`--macos`. With neither, manifests carry a
  comment instead of a `platforms:` line.
- One install per checkout: a second footprint in the same git tree is refused.

### The notes are generated, offline

**`Scripts/sync-notes.sh`** — `--check` (CI gate, exit 1 on drift) · `--apply` · `--evidence`. No
  model, no network. Seven of the nine inventories now come from it:

| Tier | Notes |
|---|---|
| Generated | FONTS · ASSETS-COLORS · PROJECT |
| Partial — rows proven, remainder named *in the note* | ASSETS-IMAGES · API-MAP · NAVIGATION · SCHEMES |
| Hand-written from candidates | FEATURES · STYLE-GUIDE |

- Writes only between `GA:ROWS` markers; prose, rules and hand-written rows outside them are never
  touched.
- `scan-api-map.py` gained a second discovery pass for repos with **one router enum per feature**,
  where the `path` property sits in a separate `extension`. On such a repo it went from 0
  endpoints to 90, and it now reports which files it still cannot read rather than implying none
  exist.
- `notes-staleness.sh --stamp` records a per-note content hash, so "is this still current" is one
  comparison instead of re-reading nine files.

### When a script fails

**`Scripts/ga-handoff.sh`** — a bounded report in `.genericarch/failures/`: what the script
  expected, what it found, the input it choked on, and the machine's versions. Capped at 60 lines.
  The agent fixes the script from that, instead of reading 175 lines to re-derive it.

### Smaller footprint, smaller sessions

- Reference docs, the lint configs (`--with-lint`) and the CLAUDE.md authoring pipeline
  (`--with-meta`) no longer install by default; `install.sh` and `bootstrap.sh` no longer copy
  themselves into a target.
- `MAP.tsv` rows for files not on disk are marked `:remote`; `SCRIPTS.tsv` rows for scripts that
  were not installed are pruned outright.
- On a real existing repo: **80 files → 64**, and always-loaded skill/command descriptions **1,315
  → 377 tokens**.

### Where rules and knowledge live

- `CLAUDE.md` is session material only. Setup, build, ship and settings moved to
  `docs/BUILD-PROCESS.md`, `docs/DEPLOYMENT-PROCESS.md` and `docs/PROJECT-SETTINGS.md`, each linked
from it — a file nothing links to is one the agent never learns exists.
- **`Packages/CLAUDE.md`** carries the detail behind §4, §7 and §9, loaded where it binds. Every
  root heading stays: ~380 `§N` citations resolve against them and no linter checks that.
- New: `OPERATORS-GUIDE.md` (for the person), `docs/patterns/wrapper.md`, `docs/SEQUENCE.md`.
- `.claude/memory/` is the repo's own store, read at the start of work rather than every session.

### Verification

**`Scripts/ga-roundtrip.sh`** — 15 cases against repos built from nothing: clean round trip, a
  decline that stays declined, revive, reseal, orphan reporting, the one-root rule, both install
  directions, the offline note pass, and that no partial note reads as complete. Run it before
  tagging.

---

## v0.2.0

The manifest release. `install.sh` records every path it writes with a hash, `uninstall.sh` reads
that manifest and nothing else, and `adopt-review.sh` classifies an installed repo against the
base. Added the script registry (`SCRIPTS.tsv` generated from each script's `#@` header), the
document map (`MAP.tsv`), the nine generated notes, `find.sh`, `/find`, `/learn`, `/review`, and
the `debug` skill.

## v0.1.0

The first extraction: `CLAUDE.md`, the module docs, the skills and commands, `check.sh`, and the
toolchain detection. No manifest — which is why `uninstallv0.1.0.sh` exists and proves ownership
by hashing against the blobs that release shipped.
