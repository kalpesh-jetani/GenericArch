# Changelog

Releases of the GenericArch base. A version is a tag; `install.sh` records it in the target's
manifest and `uninstall.sh` validates against it, so a release name is load-bearing rather than
decorative.

---

## v0.6.2

The theme: **the base asserts no module it cannot show you.**

### The default architecture is gone

`docs/modules/` — twelve docs, one per package — has been deleted, along with every assertion that
those packages exist. The loop it caused: `CLAUDE.md` §2 stated rules like *"Every dependency
injected via protocol → DIKit.md"* in a file loaded into every session; `adopt.sh` never copied the
module docs (they were `REFERENCED`, fetch-on-demand); and `MAP.tsv` defines an off-disk path as *a
fetch instruction, not a broken link*. So absence could never mean **this product has no such
layer** — every session concluded `DIKit` existed, failed to find it, and demanded it again.
Nothing recorded which layers a product actually had: `/project-init` asked, then filed the answer
under `DECISIONS.md` ***Open***.

v0.4.2 made the docs fetch-on-demand and the architecture layer opt-in. That fixed the *copying*
and left the *asserting* intact, which is why the loop survived it.

- **The replacement is [`docs/REPO.md`](docs/REPO.md) §Layout** — the directory tree it already
  carried, now with a table of what each layer owns and the §2 rule it serves. It describes the
  shape a product *may* take, never an inventory of the one you are in, and says so in its first
  line. Its `MAP.tsv` grep terms gained `layout structure directory tree shape layer`; it had none
  of them, so the structure reference was unfindable by anyone searching for the structure.
- **A package's doc now lives beside its code**, as `Packages/<Name>/<Name>.md`
  ([STRUCTURE.md](docs/STRUCTURE.md)). A root-level doc outlives the package it names.
  `check.sh` warns on the new location; the *Module doc contract* is now a *Package doc contract*
  and no longer opens with a `**Package:**` assertion.
- **`new-feature` states contracts, not packages.** It named `Core`, `DesignSystem`, `Navigation`,
  `DIKit`, `Messaging` and `LocalizationKit` as bare parenthetical prose — invisible to every link
  checker — while telling `Package.swift` to depend on them. It now says what a screen must expose
  and render, and reads `Packages/` for what this product actually has.
- **`.swiftlint.yml`'s four rule messages** cited module docs. Those strings surface in Xcode on
  every violation, so each was a dead pointer in a developer's build output.
- `ga-init-scan.sh`'s `§orphan-docs` became `§root-package-docs`, and lost the base-checkout skip
  whose justification ("ships the full set as the blueprint") no longer holds. `ga-cleanup-scan.sh`
  reports a root-level package doc as a candidate to *move*, not only to delete.
- `ga-roundtrip.sh` case 7 proved the `--with-architecture` opt-in by asserting a `module` MAP row
  survived. There are none now, so it witnesses the `pattern` rows instead — which `adopt.sh` drops
  without the flag and keeps with it.

**Two files deliberately keep their `docs/modules` references**: `uninstallv0.1.0.sh` and
`ga_known_paths()` in `ga-lifecycle.sh`. Both are per-release records of what a given version
actually wrote, verified by content hash before anything is deleted. Editing them to match a later
release is how an uninstall starts hunting for files that release never wrote.

### Updating an existing install

An install from v0.6.1 or earlier carries twelve `module` rows in `.claude/MAP.tsv`, marked
`:remote` against a pinned `FETCH-BASE`. Those paths no longer exist upstream, so they now 404
rather than resolving. Run `/sync-with-genericarch` to prune them; until then a lookup that hits one
fails loudly instead of returning a doc for a layer the product does not have.

### Five lifecycle defects a real adopted project found

Running the whole lifecycle against a real iOS install — v0.5.0, through
`/project-init`, `/gaps` and `/sync-app-notes` to `ready` — turned up five things, all now closed.
Two of them made the uninstaller claim success it had not earned.

- **[#13](https://github.com/kalpesh-jetani/GenericArch/issues/13) — two roots had no way out.**
  `install.sh` and `ga-sync-scan.sh` both refuse while a checkout has two roots, and neither could
  say which to keep. New `Scripts/ga-roots.sh` ranks them by how far each got through `GA_STEPS`,
  counts stacked manifests against a root, and prints the exact retire commands. It retires nothing
  itself: that is `uninstall.sh`'s job, per root, with the manifest as the authority.
- **[#14](https://github.com/kalpesh-jetani/GenericArch/issues/14) — a twice-installed root reported
  a false clean.** Both manifests survive, one run removes one version's records, and it still said
  *"back to its pre-install state"* and exited 0. Now it names every manifest up front, withholds
  that claim while any remain, and exits non-zero.
- **[#15](https://github.com/kalpesh-jetani/GenericArch/issues/15) — `.genericarch-version` outlived
  the uninstall.** Its content *is* the version, so hash-comparing it always failed and it was kept
  as "you edited it" — still naming v0.2.0. Manifest mode now proves it by format, as the
  no-manifest path always did, and rewrites it when another install remains.
- **[#16](https://github.com/kalpesh-jetani/GenericArch/issues/16) — a newer `uninstall.sh` beside
  an older library lost functions in silence.** Six `ga_footprint_at: command not found` *after*
  printing success, so the second-root check never ran. `set -u` cannot catch it — an unset function
  is not an unset variable. The surface is now asserted with `command -v` before anything is removed.
- **[#17](https://github.com/kalpesh-jetani/GenericArch/issues/17) — the second-root refusal pointed
  at the wrong root.** It advised "install into that root instead" by position, which meant
  abandoning a root at `ready` for residue from two superseded installs. It now quotes
  `ga-roots.sh`'s ranking.

`ga-roundtrip.sh` gains cases 20–24, one per defect. The suite never removed a manifest before, so
the fallback path had no coverage at all.

### The OpenSpec bridge

[OpenSpec](https://github.com/Fission-AI/openspec) is a spec-driven workflow an agent follows step
by step; this layer had the rules but no such workflow. `/openspec-install` installs it and wires
the two together, and **nothing about it is recorded here except that URL** — no version, no package
name, no install command, no copy of its spec format, no forked schema. Its repo is revised by other
people, so a copy of any part of it is stale the moment they change it.

- **`/openspec-install`** — resolves the install from the live URL each run, shows what came back,
  and asks before running it. Idempotent: run it again to re-project, or to check.
- **`Scripts/openspec-sync.sh`** — projects this repo's own `CLAUDE.md` §2 headlines, the
  *Do not re-propose* rows, the §0 ask-list and the detected toolchain into OpenSpec's documented
  injection point (~1.5 KB, because every byte is re-sent on every artifact command). Reading the
  repo it *runs in* is deliberate: `CLAUDE.md` does not travel and `DECISIONS.md` arrives empty, so a
  projector reading the base would arrive with its inputs missing. It **writes no YAML** — the
  command applies, the way `sync-notes.sh` and `/sync-app-notes` already split.
- **The reverse direction** reads their `--json` CLI, never their markdown, and reports `IN-FLIGHT`,
  `FEATURE-ROW` and `FINDINGS` candidates. An interface it cannot read is `SHAPE-UNRECOGNISED` and
  prints a ready-to-run `gh issue create` rather than guessing a row — a wrong `FEATURES.md` row is
  worse than a missing one. An **issue only**, naming the branch: no commit, no PR, so §2.11 is
  untouched.
- **`Scripts/check.sh` now warns when the projection is stale**, skipping where there is no OpenSpec
  config. Editing a §2 rule silently staled the span that carries those rules, and nothing said so;
  hanging it off the gate that already runs before a PR removes a habit nobody would keep.
- **`check-skill-triggers.py` guards the boundary both ways.** A product that installs OpenSpec gets
  a dozen `openspec-*` skills in `.claude/skills/`, which fire by inference alongside `debug` and
  `new-feature`. It asserts that none of ours claims spec-workflow language and none of theirs claims
  house work — never which of theirs should win, because that would pin wording we do not control.
- **`new-feature` step 2b** checks for an in-flight change before scaffolding, for the same reason
  step 2 checks whether the screen exists.
- **`CLAUDE.md` §5 carries the routing line** that is the only path to `/opsx:explore`. It produces
  no artifact, so nothing in `openspec/config.yaml` reaches it; a line in a file that loads every
  session is the whole mechanism. 56 words, and §2's numbering is untouched.
- Two gaps are stated rather than papered over: their explore and verify steps have **no injection
  point at all**. What reaches explore is an always-loaded rule and nothing stronger, and
  [docs/DONE.md](docs/DONE.md) stays the authority on done.

**Tagged `v0.6.2`.** `install.sh` derives the version from git tags, and `ga_known_paths` has a
`v0.6.2` arm listing `Scripts/openspec-sync.sh` and `Scripts/ga-roots.sh` — under any other tag both
would be unaccounted for in a fallback uninstall. The plugin path carries the **command only**:
`build-plugin.sh` copies `.claude/skills` and `.claude/commands`, so a plugin-only consumer gets no
script and no doc, and the command detects that and says so.

### v0.6 is the LTS line, and everything below it is deprecated

`v0.6.0` opens the supported line and every `v0.6.x` belongs to it, and this release is its
current patch. Two constants say so rather than a convention: `GA_LTS_LINE="v0.6"` and
`GA_LATEST_VERSION`, which this release moves to `v0.6.2`.

**Versions are now two tiers, because installing an old release and removing one are different
questions.**

| | Tier | Versions |
|---|---|---|
| **Removable** | `GA_SUPPORTED_VERSIONS` — every release ever shipped | v0.1.0 … v0.6.2 |
| **Installable** | at or above `GA_INSTALL_FLOOR` | v0.6.0 and up |

`install.sh` refuses anything below the floor with exit 6 and writes nothing, naming the checkout
fix — the usual cause is an old tag being checked out. `uninstall.sh` still accepts every version in
the supported list, and says "deprecated" in its header while removing one.

That asymmetry is the whole design. Stripping the old entries would have stranded every existing
install below the floor with no way off it, which is the opposite of what deprecating them is for.
It would also have broken `ga-roots.sh`, whose entire output for the case that prompted it is
`./uninstall.sh v0.4.2` then `v0.2.0` against older nested residue. Case 25 pins both halves:
install refused and nothing written, uninstall still clean.

---

## v0.6.1

The theme: **the claims this base makes are checked against the base.** No shipped file was added or
removed, so a v0.6.1 install has exactly v0.6.0's footprint and the two share one arm of the
uninstall fallback. What changed is four things that reported something untrue, and the two
generators behind them.

**`scan-unused-assets.py` was proposing the deletion of live assets.** Xcode 15 gives every asset a
camelCased `ImageResource` symbol, and a modern call site uses it — `Image(isSelected ? .radioChecked
: .radioUnchecked)` for assets named `radio_checked` and `radio_unchecked`. The literal never appears
in source, so **11 live assets out of 24 came back dead: a 46% false-positive rate on what is, in
effect, a deletion proposal.** The scan now searches the literal *and* the symbol, anchored on the
leading dot so a same-named local variable cannot absolve an asset. The tell was shape rather than
count — a matched pair going dead together is a call site the scan cannot see
([SCAN-TRAPS.md](docs/SCAN-TRAPS.md) trap 5).

**`detect-toolchain.sh` reported its own fallbacks as findings.** It grepped a hardcoded `Packages App
Sources` and used a root-level `ls` for `Package.swift`, `*.xcodeproj` and `*.xcconfig`. Against a
repo whose project sits one directory down, every probe returned nothing and each default was printed
as a detection: `UIKit/AppKit` for a SwiftUI app, `vendored xcframework` for an all-SPM one, `SPM
only` for a checked-in `.xcodeproj`, `unresolved` concurrency for 76 Combine files. The costly one was
silent — `project.pbxproj` was never found, `ORIGIN` stayed empty, and **`ga-init-scan.sh`'s BLOCKING
deployment-target check could not fire at all**, which is the first thing `/project-init` raises. The
roots are now derived, with `.build`, `SourcePackages`, `DerivedData`, `Pods` and `Carthage` pruned:
without the prunes a resolved dependency answers questions about this repo, and a vendored
`sentry-cocoa` dSYM was cited as the app's own crash reporting.

**`detect-capabilities.sh` matched its own source.** Its UI-test probe was a bare
`grep -rlq XCUIApplication "$ROOT"` with no `--include`, and the script lives under `$ROOT` — the
pattern appears in that very line, so it reported `ui-tests FOUND` in a repo with zero test targets.
It now goes through the same filtered helper as every other check. Two neighbouring probes carried the
root assumption above, and one of them counted **0 external package refs for an app with 25**;
counting by marker instead would have said 67, so it counts distinct repository URLs, or reads
`Package.resolved` where it exists.

**The published plugin's README is generated from frontmatter now, not maintained by hand.** It is
what someone reads before installing, and both its tables were wrong: it advertised `dark-light-mode`,
`rtl-support` and `release-bump` as skills — all three are patterns under `docs/patterns/` and none
ship in the plugin — omitted `debug`, which does, listed seven of the twelve commands, and described
`/sync-app-notes` as rebuilding seven inventories where there are nine. Both tables now come from the
`description:` frontmatter of the skills and commands actually copied into `dist/`, with the counts
derived from the same globs, so the public README cannot claim a surface the plugin does not ship.

**`build-plugin.sh` reads `.claude-plugin/plugin.json` instead of a second copy of it.** The inline
copy it kept had drifted to advertise a Swift version §1 refuses to state from memory and three skills
that only ever existed as patterns, and it defaulted the version to `0.1.0` — so a plain build
published a plugin labelled wrong. Name, description and version come from the manifest, which is
where this release's bump is recorded.

**README audited claim by claim**, and two sources corrected behind it rather than just the prose: the
bootstrap dry run no longer promises "every file it would add" (it omits `.claude/CANDIDATES.tsv`);
three commands are lifecycle steps, not four, because `/find` gates on `/sync-app-notes` having
finished rather than being a step itself; `uninstallv0.1.0.sh` is documented at last; and the Layout
block gained the four root installers, `CHANGELOG.md`, `.swiftlint.yml`, `.claude/INDEX.md`,
`.claude-plugin/` and `dist/`. `session-script.sh` advertised a six-row gate table where `promote`
prints seven — the count is dropped rather than corrected, because a literal number in a header is
what rots. `.claude/SCRIPTS.tsv` regenerated: `register-scripts.sh --check` is back in sync at 48
scripts. `docs/CLAUDE-TASKS.md` carried the same stale `never:<reason>` example.

**Three open questions recorded from an adoption run**, in [DECISIONS.md](docs/DECISIONS.md) —
`/project-init` S3 offering `/sync-app-notes` where the gate exits 5; whether a fresh install should
ship the nine notes at all when they arrive carrying this base's own example rows; and how an
adoption's resolved conflicts survive a reinstall, which `ADOPTION.md` §A6 requires and nothing
enforces. Recorded, not fixed — each is a §0-shaped question, and inventing an answer here is what
`DECISIONS.md` exists to stop.

Upgrading from v0.6.0 is still uninstall → install: `install.sh` exits `6` on a manifest recording a
different version, footprint parity notwithstanding.

---

## v0.6.0

The theme: **uninstall, then install — and nothing of yours is lost in between.** v0.5.0 claimed an
in-place upgrade worked; adopting it over a v0.4.2 install showed what that actually meant, which
was most of v0.4.2 still on disk under a v0.5.0 manifest.

**Upgrading is now uninstall → install, and `install.sh` enforces it.** A manifest recording a
different version stops the run with the new exit code `6`, names the `./uninstall.sh <old>` command
to run, and writes nothing. Only shared libraries ever moved forward in place; everything else was
classified `keep` and reported as *"left at older version"*, which is a sentence no one reads twice.
`--in-place` keeps the old behaviour. The **same** version is still a repair run, ungated.

**Files you edited now survive the round trip as first-class records.** A hash mismatch has always
protected a file from deletion, but the report naming the survivors was written to
`.genericarch/orphans-<version>.txt` — inside the directory the same uninstall then retired, which
is why nothing ever read it. It is now `safetodelete-after-migration-note.md` at the repo root, and
`install.sh` reads it: each surviving path is recorded with the new `orphan` action — tracked, never
rewritten, never deleted, and re-emitted by the next uninstall.

**`uninstall.sh` asks once, at the end, what should become of them.** Re-installing leaves them
exactly where they are. Done with GenericArch moves them to `.genericarch/safetodelete/` — moved,
never deleted — records the list in your `CLAUDE.md` (or `GENERICARCH-ORPHANS.md` if you have none),
deletes the note, and exits `0`, because the working tree really is clean. `--upgrade` and `--final`
answer it non-interactively; with no terminal the answer is `--upgrade`, the side that moves nothing.

**`install.sh --with-claude-md` migrates a repo's rules, reversibly.** Your `CLAUDE.md` moves to
`CLAUDE-BK.md` and the swap is recorded with the new `replaced` action, so `uninstall.sh` restores
your original byte-for-byte, verified against its recorded hash. Off by default: *"no CLAUDE.md was
written"* is still what an ordinary install prints.

**Manifest schema 2**, and `uninstall.sh` now refuses a schema it does not know rather than doing
its best with it. An unrecognised `action` is the difference between *delete this* and *never touch
this*; the old parser fell through to "created" and would have deleted an orphan. Its `case` now
defaults to keeping the file. The manifest also records `sibling_root`, so a `--root-ok` install is
discoverable after the terminal that warned about it has closed.

Four fixes from the same adoption log:

- The confirmation prompt **restates the second footprint** instead of asking `Install into <dir>?`
  sixty lines after the warning scrolled past — and when every project marker resolves inside the
  other root, it says so: that is one product, not the two sharing a checkout `--root-ok` is for.
- `uninstall.sh` **names a surviving install** in the same checkout rather than reporting *"back to
  its pre-install state"* while a second copy is live.
- The plan's `.gitignore` line **described two entries where three were written**. Both now read
  `GA_GITIGNORE_BLOCK`, defined once.
- `rollback()` replays its ledger in reverse, and the `.gitignore` rows were ordered so the backup
  was **deleted before the restore read it** — a rollback that reported success and left the managed
  block in place. The rows are now written in the order the reverse replay needs.

`bootstrap.sh` forwards `--in-place` and `--with-claude-md`, and names exit 6 when it sees it.
`Scripts/ga-roundtrip.sh` gains seven cases covering all of the above.

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
