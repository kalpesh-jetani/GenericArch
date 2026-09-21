---
description: Reconcile the active stack profile's declared toolchain against the machine, applying only fixes the user approves — asks twice before changing anything
argument-hint: [optional: a specific mismatch id]
allowed-tools: Bash, Read, Edit, Grep, Glob, AskUserQuestion
---

```bash
./Scripts/ga-step.sh after project-init      # sequence gate
```

**Exit 5 means an earlier step has not run.** Say which one, and stop — never pass `--force`. Order
and why: [SEQUENCE.md](/docs/operations/SEQUENCE.md)(../../docs/SEQUENCE.md).

Reconcile what the **active stack profile** declares against the machine that will build it, and
apply only the fixes the user approves.

The layer fixes no toolchain: a profile (`profiles/<name>/`) declares the stack, and the
machine-reconciliation probe is the profile's own (`detect-toolchain.sh --mismatches`). **No shipped
profile wires that probe yet** (docs/DECISIONS.md → Open), so with no profile — or a profile with no
probe — there is nothing to reconcile; say so.

## How to run it

1. **Read the mismatches the profile's probe reports:**

   ```bash
   ./Scripts/detect-toolchain.sh --mismatches --root .
   ```

   Each line is `SEVERITY|id|what|current|available|remediation`. No lines → nothing to do.

2. **Two approvals, always.** Ask once for *which* mismatch to address (`AskUserQuestion`), then show
   the exact edit and ask again before making it. A stack setting is a product decision — never
   changed silently, never defaulted (§0).

3. **Apply only the approved edit**, then re-run the probe to confirm it cleared.

## Constraints

- **Never change a stack setting without two explicit yeses.** Raising or lowering a version can drop
  or exclude users — the product's call, not this command's.
- **Never install or switch a toolchain** on the user's machine.
- Report, then act only on approval; never commit (§2.2).
