# Tool profiles — what an external platform exposes

Reference for `.claude/tools/`. One profile per external platform, recording what it exposes and
how to reach it, so the next session does not have to reach the platform again to find out.

- **When to read this:** before generating, extending or retiring a profile, or when a recorded
  recipe did not work.
- **Fired by:** the `tool-profile` skill, which routes here rather than carrying this body.
- **Driven by:** `./Scripts/ga-tool-note.sh` — its `#@` header is the contract
  (`grep ga-tool-note .claude/SCRIPTS.tsv`).

---

## Scope — what earns a profile

The test: **the resource lives outside this repo and is reached through a connector, a URL, or
credentials.**

| In scope | Out of scope |
|---|---|
| Design tools and design-reference URLs | Local files, and anything under `Packages/` or `App/` |
| Mockup and layout references | The repo's own `Scripts/` |
| Ticket trackers and project systems | `git` |
| CI/CD and delivery platforms | The iOS Simulator |
| Observability and paging systems | The browser used for generic reading |
| Any Claude Connector | A one-off page fetched once and not depended on |

A platform that was reached but never *successfully* used gets no profile. That is a
connectivity fact to record on an existing profile, not a reason to open a new one.

---

## The lifecycle

**find → generate → register → extend → fail → generate → unregister → retire → revive**

A failure has no repair operation of its own: it loops back to `generate`, on fresh
observation. There is one way a profile comes into existence, and a stale one re-enters it
rather than being patched in place.

| Operation | Invocation | Effect |
|---|---|---|
| **find** | `--find <tool>` | `0` = hit, prints the profile and recipe paths; `1` = miss or stale |
| **generate** | `<tool> [--apply]` | Tombstone check, then scaffold profile + recipe + ledger row. On a `stale` profile this is the repair path: rows replaced, `failures` reset to 0 |
| **extend** | `<tool> --extend [--apply]` | Same platform, new input or output → append rows and a recipe mode to the **existing** files |
| **register** | automatic on write | Updates all four documentation surfaces below |
| **fail** | `<tool> --fail --cause "…"` | Increment `failures`, move `status`, file a report via `ga-handoff.sh` |
| **unregister** | `<tool> --unregister [--apply]` | Drop the index rows, keep the files — dormant, not gone |
| **retire** | `<tool> --retire --reason "…"` | Delegates to `ga-remove.sh --untracked --apply` |
| **revive** | `<tool> --revive [--apply]` | Restores **both** tombstoned paths, drops both tombstones, re-indexes. Retire covers two paths, so revive must too |
| **list** | `--list` | The ledger, with failure counts |
| **sync** | `--sync` | Regenerate the registry note, and the managed index spans, from the ledger |

**Find before you generate.** A hit means the profile is used as recorded and nothing is
written. This is the same reuse gate `session-script.sh` applies before staging a duplicate
script.

---

## Observation only — `not observed` is a required entry

Every row is something seen in a real response. A field that was not observed is written
`not observed`, and stays that way until it is actually seen.

Never fill a cell from knowledge of the vendor's API, from a neighbouring row, from a similar
platform, or because the value looks obvious. CLAUDE.md §2.14 — building from the name of a
thing produces something plausible and wrong — and a plausible profile is worse than none,
because it is trusted.

Two mechanical consequences:

- Every scaffolded cell starts as `not observed`. The generator ships no example attributes and
  no plausible defaults, so an unfilled profile is visibly unfilled.
- **`--apply` refuses a profile with no *retrieved* row** (exit 1). A platform that was never
  successfully reached produces no file.

### The three provenance values

`Observed` is derived, not typed — the generator sets it from what the row itself claims:

| `Observed` | Means | When |
|---|---|---|
| a date | The attribute was **retrieved** on that day | `Accessible` is anything but `not observed` |
| `contract` | The **shape** is known from the connector's tool definition, but the platform was never asked for it | `Accessible` is `not observed`, unit is known |
| `—` | Nothing is known but the attribute's name | both are `not observed` |

**Only a dated row satisfies the gate.** A tool contract tells you a field's pattern; it never
tells you the platform answered. A profile assembled purely from contracts would be a plausible
profile of a platform nobody reached — the exact artifact rule 3 exists to prevent — so
`--apply` refuses it and says how many contract rows it saw.

---

## The schema

Notes-style bullet header, then the attribute table, then two prose sections. No YAML
frontmatter — `.claude/notes/` uses bullets, and a third frontmatter dialect is one to avoid.

```markdown
# <Platform>

- **Platform:** <what kind of system, and what it holds>
- **Reached via:** <connector tool names> — *or* <what the user pasted> when unwired
- **Read it when** <extracting one of the attributes below, or deciding if one is reachable>
- **Recipe:** `./Scripts/Generated/<tool>.sh` — the call sequence, wired and unwired
- **Status:** active · failures 0 · **Last verified:** <date>

---

## Attributes

| Attribute | Unit / type | Accessible | Extraction method | Scope | Observed |
|---|---|---|---|---|---|
| <name as the platform calls it> | <unit, e.g. `w:h` float, hex, pt, ISO date> | yes | <the call, and the field in its response> | <per record / per file / per account> | <date> |
| <an attribute whose name was seen and nothing else> | not observed | not observed | not observed | not observed | — |

## Connectivity

**Wired** — which connector tools, and what each needs as input.

**Unwired** — a reference was pasted instead. What is still obtainable from it, what must be
asked for, and what is simply unreachable.

## Usage notes and gotchas

What cost a wrong turn the first time — a unit that is not what it looks like, a scope that is
per-account not per-record, a value only present after another call.
```

`Observed` is the provenance column and it is not optional: a date means the row came out of a
real response on that day.

**The seven recorded fields map onto this exactly** — attribute name → column 1, value type or
unit → 2, accessibility → 3, extraction method → 4, scope definition → 5, and third-party
connectivity plus usage note → the two prose sections.

### Why the recipe script exists

`Scripts/Generated/<tool>.sh` prints the recorded access recipe and exits — read-only, no
network. It earns its place in the **unwired** case: when no connector is configured and a
reference was pasted, it states what is reachable from that reference, what to ask for, and
what is not reachable at all, instead of attempting a connector call that will fail.

---

## Documentation is part of register, not a follow-up

CLAUDE.md §5 requires the affected index rows to be edited in the same change as the insertion
or deletion. Acquiring a platform updates four surfaces; retiring one reverses all four.

| Surface | On register | On unregister / retire | Written by |
|---|---|---|---|
| `.claude/SCRIPTS.tsv` | row for the recipe script, from its `#@` header | row pruned | `register-scripts.sh` |
| `.claude/skills/tool-profile/references/generated-skills-note.md` | row for the profile | row dropped | `--sync` |
| `.claude/MAP.tsv` | grep row for the profile | row pruned | `--sync`, in a managed span |
| `.claude/INDEX.md` *External systems* | row naming the platform | row dropped | `--sync`, in a managed span |

`ga-remove.sh` prunes `MAP.tsv` and `SCRIPTS.tsv` itself, so `--retire` gets half the reversal
free and `--sync` finishes the rest.

Generated rows live between managed-span markers. `MAP.tsv` is otherwise maintained by targeted
edit, so a hand-written row must never be clobbered by a generated pass — and a person can
hand-fix a topics column without the next `--sync` reverting it.

---

## When a profile fails

A **failure** is the recorded recipe not working: an attribute that is not there, a unit that is
wrong, a call the profile said would succeed. An authorization prompt is not a failure — it is a
connectivity fact to record.

| Failures | `status` | What happens next |
|---|---|---|
| 1 | `suspect` | Report filed under `.genericarch/failures/`. Profile still usable, flagged in the registry |
| 2 | `stale` | **Back to generate.** `--find` reports a miss, so the next use re-observes the platform and replaces the rows rather than patching them |
| 3 | `retired` | **Retire.** Claude proposes it and asks; `ga-remove.sh` does the move |

Read the failure report, never the script body (CLAUDE.md §5).

---

## Removing one

`--retire --reason "<why>"` delegates to `./Scripts/ga-remove.sh`, which owns the rule: the file
**moves** to `.genericarch/safetodelete/`, gains a `.genericarch/TOMBSTONES.tsv` row, loses its
index rows, and gets a `docs/DECISIONS.md` *Do not re-propose* row. Nothing is deleted, and
`--revive --apply` reverses it, and it is deliberately symmetric: retirement tombstones the profile
*and* the recipe, so a revive that restored only the profile left the recipe tombstoned while
`generate` re-created it — a file on disk that the install machinery believed was declined.

The tombstone is what makes retirement stick: `generate` checks **both** paths before writing and
refuses a retired platform. Without that check every deliberate removal is undone by the next run
([INSTALL-MANIFEST.md](INSTALL-MANIFEST.md)).

Any run that rewrote installed files closes with `./Scripts/ga-reseal.sh --apply` (CLAUDE.md
§2.15).
