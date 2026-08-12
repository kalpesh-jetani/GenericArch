---
description: Review mismatches between the project's stack settings and the machine, then apply only the fixes the user approves — asks twice before changing anything
argument-hint: [optional: a mismatch id, e.g. macos-target-above-sdk]
allowed-tools: Bash, Read, Edit, Grep, Glob, AskUserQuestion
---

Reconcile the project's stack settings with the machine.

```bash
./Scripts/detect-toolchain.sh              # human report
./Scripts/detect-toolchain.sh --mismatches # SEVERITY|id|what|current|available|remediation
```

Scope: `$ARGUMENTS` if a mismatch id is given, otherwise everything reported.

---

## Two approvals. Always. No exceptions.

**Gate 1 — what to address.** Present the mismatches, get a selection.
**Gate 2 — the exact edits.** Show the concrete before/after per file, get a second yes.

Between the gates you **compute** changes; you do not apply them. A single yes is never enough,
because gate 1 approves an *intent* ("fix the macOS target") and gate 2 approves the *act* ("change
this line in these three files"). Those are different decisions and the second is where mistakes
become visible.

If the user says yes at gate 1 and then goes quiet, **nothing has been changed** — say so plainly
rather than assuming consent.

---

## Step 1 — Classify, don't lump

`--mismatches` marks each one. Treat them very differently:

| Severity | Means | Urgency |
|---|---|---|
| **BLOCKING** | The project cannot build as configured | Real. Lead with it |
| **OPPORTUNITY** | It builds; something newer exists | **A choice, often a product decision** |
| **DRIFT** | Docs or unanswered settings disagree with reality | Cheap; no build impact |

**Never present an OPPORTUNITY as if it were a problem.** "Your Swift language mode is behind" is
not a defect — a team on mode 5 with a large codebase has a reason, and migrating means new
concurrency diagnostics across every package.

## Step 2 — Gate 1: which mismatches to address

Batch with `AskUserQuestion`, one question per mismatch, options: **Fix now · Defer · Skip
(record it) · Other**.

For each, state three things and nothing more:

1. What is mismatched — current vs available.
2. **What happens if it's left alone.** For BLOCKING that is "the app target won't build". For
   OPPORTUNITY it is usually "nothing".
3. Your recommendation, one clause.

### Say the user-impact out loud for anything that raises a floor

Raising a deployment target is **not a technical upgrade — it drops users**. Any option that raises
`IPHONEOS_DEPLOYMENT_TARGET`, `MACOSX_DEPLOYMENT_TARGET`, or a `platforms:` entry must name who
stops being able to install the app. If you don't know the user split, say that you don't, and say
that the answer belongs to whoever owns the product.

Lowering a target to match the SDK is the safe direction and usually the right fix for BLOCKING.

## Step 3 — Compute the edits, show them, then Gate 2

Produce the exact change set. Per file: path, the current line, the proposed line.

```
Packages/Core/Package.swift
  -   platforms: [.iOS(.v17), .macOS("26.6")]
  +   platforms: [.iOS(.v17), .macOS("26.5")]
Packages/DIKit/Package.swift
  -   platforms: [.iOS(.v17), .macOS("26.6")]
  +   platforms: [.iOS(.v17), .macOS("26.5")]
```

Then ask **gate 2**: apply these exact edits · revise · cancel.

Rules for this step:

- **Every affected file, not a sample.** `grep -rn` the setting first; a partial change leaves the
  repo inconsistent and the next build confusing.
- If the change is large, say how many files before showing the list.
- **`git status` must be reported first.** Applying edits over a dirty tree mixes your changes with
  the user's. If the tree is dirty, say so and let them decide whether to proceed.

## Step 4 — Apply, then prove it

Only after gate 2:

1. Make the edits.
2. Re-run `./Scripts/detect-toolchain.sh` — the mismatch must be gone.
3. Run `./Scripts/check.sh` and `swift build` for each touched package.
4. **If verification fails, say so and stop.** Do not chase the failure with more unapproved edits;
   that is how a two-gate process turns into an unsupervised one.

Record the outcome with `/decide` — a stack change is a settled decision, including a deliberate
Skip, so it isn't re-raised next month.

---

## What this command must never do

- **Never edit `CLAUDE.md`.** §1 drift is reported as DRIFT, and refreshing it needs its **own**
  separate approval with the exact text shown ([STRUCTURE.md](../../docs/STRUCTURE.md)) — a third
  gate, not folded into gate 2.
- **Never install or switch Xcode**, and never run `xcode-select`. If the fix is "install a newer
  Xcode", say so and stop; that is the user's machine.
- **Never touch the extracted packages** (`GenericArch-NetworkKit`, `GenericArch-ImageCache`). They
  are separate repositories — `/release-bump`.
- **Never raise a deployment target because the SDK allows it.** SDK availability is not a reason;
  product reach is.
- **Never batch an OPPORTUNITY in with a BLOCKING fix.** Approving "make it build" is not approving
  a language-mode migration.
