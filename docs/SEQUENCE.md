# Command sequence

The order the commands run in, what each one must leave behind, and what enforces it.

- **When to read this:** a command refused with "cannot run yet", you are adopting into an existing
  repo, or you are adding a command and need to know where it sits.
- **Enforced by:** `./Scripts/ga-step.sh` — every command's first step. The ledger is
  `.genericarch/STEPS.tsv`.

```bash
./Scripts/ga-step.sh show     # where am I, what is next
./Scripts/ga-step.sh next     # just the next step
```

---

## The order

| # | Step | Run by | Must leave behind |
|---|---|---|---|
| 1 | `install` | `./install.sh` (or `./bootstrap.sh`) | The manifest. Recorded automatically — no command records it |
| 2 | `project-init` | `/project-init` | A reconciled `CLAUDE.md`, `docs/DECISIONS.md` rows for every answer, declined files tombstoned |
| 3 | `gaps` | `/gaps` | Every `docs/GAPS.md` row at ✅ ⏸ or ⛔, each ⛔ with a *Do not re-propose* row |
| 4 | `sync-app-notes` | `/sync-app-notes` | Nine inventories in `.claude/notes/`, each with a `Last synced` line |
| 5 | `ready` | recorded by step 4 | Nothing — it is the gate everything else waits on |

After `ready`: `/find`, `/decide`, `/learn`, `/review`, `/verify`, `/build` and every skill run in
any order, as often as needed. They are not steps; they are the work.

**An upgrade re-enters at step 1.** `install.sh` refuses over a different recorded version (exit 6),
so moving releases means `./uninstall.sh <old>` and then installing — which resets the ledger, since
a clean uninstall deletes `STEPS.tsv` unless something was declined. The three commands run again
against the new base; that is the intent, not an accident of the gate.

## Why the order is load-bearing

Each step reads a repo state the previous one creates. Ungated, they would not fail out of order —
they would succeed against the wrong input, which is worse. That is what exit 5 buys:

- **`gaps` before `project-init`** triages capabilities against rules nobody has accepted yet, and
  writes ⛔ rows citing decisions that do not exist.
- **`sync-app-notes` before `project-init`** scans a tree whose structure is still being agreed, so
  nine inventories record a layout that changes the same day.
- **`sync-app-notes` before `gaps`** cannot mark an inventory row as deliberately empty, because
  nothing has yet decided that the capability was skipped.
- **anything before `install`** runs a command file that is not there.

Documented order is not enough. Enforcement is what makes it hold.

**There is no `scaffold` step.** This base installs into a repo that already has its Xcode project;
the package layout for a repo with no shape yet is written by [GenericXCodeSetup](https://github.com/kalpesh-jetani/GenericXCodeSetup) before any of
this runs, and it records what it chose in the target's `docs/DECISIONS.md` rather than in this
ledger. A consumer ledger written before that split may still carry a `scaffold` row — it is ignored,
because the gate iterates the steps above, not the file.

## Skipping a step

A step that genuinely does not apply is **recorded as skipped, not ignored** — by the operator, with
a reason. Claude never passes `--force`:

```bash
./Scripts/ga-step.sh record gaps "not applicable: docs-and-tooling adoption, no capabilities to triage"
```

`install` is the one step no command records: the manifest *is* the record, and `ga-step.sh` derives
it — so a repo installed before this ledger existed does not look like one that never ran it.

## Maintenance operations — outside the sequence

These run whenever the situation calls for them, and gate on `install` only:

| Operation | Tool | Why it is not a step |
|---|---|---|
| Gather what `/project-init` can establish without asking | `Scripts/ga-init-scan.sh` | Preflight, not a step: read-only, records nothing, and `install.sh` runs it once the manifest lands. `project-init` is still the step, because the asking is the step |
| Take a base update | `Scripts/adopt-review.sh` | Reacts to upstream moving, not to a phase |
| Decline a file (moves it to `safetodelete/`) | `Scripts/ga-remove.sh` | A decision, recordable at any point |
| Re-seal after editing installed files | `Scripts/ga-reseal.sh` | Runs *after* any command that rewrote them |
| Remove everything | `./uninstall.sh <version>` | Ends the lifecycle |

## Adding a command

1. Decide whether it is a **step** (it must precede other work) or **work** (it needs `ready`).
2. Add its `require` line as the command's first step, and — if it is a step — its `record` line as
   the last.
3. A new step also needs its name in `GA_STEPS` in `Scripts/ga-lifecycle.sh` and a row in the table
   above. Position in that list *is* the gate.
