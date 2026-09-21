---
description: Walk the active profile's definition-of-done against the working diff and report what passes, fails, and was not checkable
argument-hint: [optional: path or area to scope to]
allowed-tools: Bash, Read, Grep, Glob
---

```bash
./Scripts/ga-step.sh after project-init      # sequence gate
```

**Exit 5 means an earlier step has not run.** Say which one, and stop — never pass `--force`. Order
and why: [SEQUENCE.md](/docs/operations/SEQUENCE.md)(../../docs/SEQUENCE.md).

Check the current change against the **active stack profile's definition-of-done**. The layer ships
no definition-of-done of its own — a profile declares it; with no profile, only the neutral
disciplines below apply.

Scope: `$ARGUMENTS` if given, otherwise the whole working diff.

## How to run it

1. **Get the diff first** — everything is judged against what changed, not the repo at large:

   ```bash
   git status --porcelain=v1
   BASE=$(git merge-base HEAD main 2>/dev/null || echo HEAD~1)
   git diff --stat "$BASE"...HEAD
   ```

2. **Walk the active profile's definition-of-done** against the diff — its rules and its mechanical
   checks (run `./Scripts/check.sh`, which runs the profile's `check_cmd`). With no profile declared
   there is nothing stack-specific to check.

3. **Check documentation currency** (holds on any stack): did code an inventory tracks change
   without its `.claude/notes/` row moving?

   ```bash
   git diff --name-only "$BASE"...HEAD | grep -E '^docs/|^\.claude/notes/'   # what moved
   ```

   If the diff touches tracked code but no note row moved, that is a finding.

4. **Build only if asked.** Use `/build` — this command reads and greps.

## Report format

- **Failing** — the rule, the file:line, the fix. Most severe first.
- **Not checkable here** — anything needing a device, environment, or a human eye. **List these
  explicitly**; do not let them read as passing.
- **Passing** — one line, a count.

## Constraints

- **Do not fix anything, and never commit** (§2.2). This command reports; the user decides.
- **Do not run `/sync-app-notes`.** Say which rows look stale and let the user start the rescan (§3).
- Never report a line as passing because it "looks fine". If it wasn't checked, it goes in *Not
  checkable here*.
