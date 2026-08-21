# Changelog

Releases of the GenericArch base. A version is a tag; `install.sh` records it in the target's
manifest and `uninstall.sh` validates against it, so a release name is load-bearing rather than
decorative.

---

## Unreleased

Continuing v0.3.0's theme — **work moves out of the session** — one step further into
`/project-init`, the most expensive command in the sequence.

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
