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
| 2 | `scaffold` | `./Scripts/ga-scaffold.sh` | **New repos only.** The directory structure, the Core+DIKit floor, and the layers chosen. On an existing repo `install.sh` records it *not applicable*, so nothing waits on it |
| 3 | `project-init` | `/project-init` | A reconciled `CLAUDE.md`, `docs/DECISIONS.md` rows for every answer, declined files tombstoned |
| 4 | `gaps` | `/gaps` | Every `docs/GAPS.md` row at ✅ ⏸ or ⛔, each ⛔ with a *Do not re-propose* row |
| 5 | `sync-app-notes` | `/sync-app-notes` | Nine inventories in `.claude/notes/`, each with a `Last synced` line |
| 6 | `ready` | recorded by step 5 | Nothing — it is the gate everything else waits on |

After `ready`: `/find`, `/decide`, `/learn`, `/review`, `/verify`, `/build` and every skill run in
any order, as often as needed. They are not steps; they are the work.

## Why the order is load-bearing

Each step reads a repo state the previous one creates. Out of order, they do not fail — they
succeed against the wrong input, which is worse:

- **`gaps` before `project-init`** triages capabilities against rules nobody has accepted yet, and
  writes ⛔ rows citing decisions that do not exist.
- **`sync-app-notes` before `project-init`** scans a tree whose structure is still being agreed, so
  nine inventories record a layout that changes the same day.
- **`sync-app-notes` before `gaps`** cannot mark an inventory row as deliberately empty, because
  nothing has yet decided that the capability was skipped.
- **`project-init` before `scaffold`** reconciles rules against a repo whose structure does not exist
  yet, so half the conflicts it finds are about files nobody has created.
- **anything before `install`** runs a command file that is not there.

The order was documented before it was enforced, and was not followed. Enforcement is the fix.

## Skipping a step

A step that genuinely does not apply is **recorded as skipped, not ignored** — by the operator, with
a reason. Claude never passes `--force`:

```bash
./Scripts/ga-step.sh record gaps "not applicable: docs-and-tooling adoption, no capabilities to triage"
```

`install.sh` does exactly this for `scaffold` on an existing repo — the step is settled at install
time rather than left to block everything behind it.

## Maintenance operations — outside the sequence

These run whenever the situation calls for them, and gate on `install` only:

| Operation | Tool | Why it is not a step |
|---|---|---|
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
