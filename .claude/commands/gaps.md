---
description: Triage the open items in docs/GAPS.md — on an existing repo, derive each status from the code and record it without asking; on a fresh repo, help the user choose per item with adopt, defer, or skip
argument-hint: [optional: B | C | E | a specific item name]
allowed-tools: Read, Edit, Grep, Glob, Bash, AskUserQuestion
---

Triage the open gaps: @docs/GAPS.md

Scope: `$ARGUMENTS` if given (a section letter, or one item). Otherwise every row with Status **▶
Open**.

---

## Step 0 — Which mode

```bash
find . \( -name "*.swift" -o -name "Package.swift" -o -name "*.xcodeproj" \) -not -path "*/.git/*" | head
```

| Repo state | Mode |
|---|---|
| Real source exists | **Path A — derive from the code, do not ask** |
| Empty, or docs only | **Path B — ask the user** |

Always skip rows already ✅ ⏸ ⛔ — re-asking a settled item is how this file loses trust. A ⏸ row is
re-raised only if **its trigger has fired**; check, and say so when it has.

---

# Path A — Existing repo: read the answer off the code

**Do not ask.** The repo already contains the decisions; your job is to record them. Grep for
evidence, set the Status, and report.

## A1. Detect

**Run the scan; do not hand-grep the table below.** It exists as a script so the patterns stay
tightened — bare vendor words are wrong often enough to matter:

```bash
./Scripts/detect-capabilities.sh "${SRC:-.}"       # STATUS <tab> item <tab> evidence
```

Output is `FOUND` / `ABSENT` / `INFO`. Mapping those to ✅ ⛔ ▶ is A2's judgement and is deliberately
**not** encoded in the script.

⚠ **`FOUND` is a candidate, not a verdict — open the evidence file before you record it.** An
earlier version of this scan matched `Segment` against a UI segmented control and `Transaction.`
against a database call, and reported analytics and StoreKit in a product that has neither. The
patterns are anchored on imports and call shapes now; the discipline still applies.

To add an item, add a `scan` line to the script rather than a row to a table nobody executes.

## A2. Map evidence to Status — and mind the asymmetry

| Finding | Status | Note in the row |
|---|---|---|
| Present **and** documented in a module doc | ✅ Applied | where it lives |
| Present but **undocumented** | ▶ Open → *needs a doc, not a decision* | the files using it |
| Absent, and the capability is **not applicable** to this product | ⛔ Skipped | "no evidence in repo" |
| Absent, and the absence is a **risk** | ▶ Open, flagged | say the risk |

**Absence of evidence is not always a decision.** No StoreKit means the product doesn't monetise —
Skip is safe. No crash reporting, no dSYM upload, no kill switch, no lint config means a **missing
safeguard** — that is a finding to report, not something to quietly mark Skipped. Getting this
backwards turns "don't ask" into "silently declare everything fine", which is the one outcome this
command must not produce.

Treat as risk-on-absence, never auto-Skip: **crash reporting + dSYM upload · feature flags (the only
rollback that reaches installed copies) · SwiftLint (rules in §2 and [DONE.md](../../docs/DONE.md)
are mechanically checkable and decay without it) · universal-link AASA if deep links exist ·
keyboard/focus if forms exist**.

## A3. Write it and report

Update GAPS.md rows as you go, each with a one-clause evidence note (`⛔ no StoreKit usage found`).
Add a ⛔ row to [DECISIONS.md](../../docs/DECISIONS.md) *Do not re-propose* for every Skip, or it
resurfaces.

Then report three groups: **already covered** · **present but undocumented** · **risks found**. The
last group is the output that matters — list it first if it isn't empty.

Ask **only** where the evidence is genuinely contradictory, e.g. an analytics SDK linked but no
events sent. Say what you found and what's ambiguous, rather than guessing.

---

# Path B — Fresh repo: help the user choose

## The four options — offer all of them, every time

| Option | Means | Then |
|---|---|---|
| **Adopt** | Do it, now or this sprint | Do the work → move the row to *Applied* with where it landed |
| **Defer** | Keep it tracked | Set ⏸ and **name the trigger** — a deferral with no trigger is an Open item pretending to be decided |
| **Skip** | Decided against | Set ⛔ **and** add a row to [DECISIONS.md](../../docs/DECISIONS.md) *Do not re-propose*. Both, or it resurfaces |
| **Other** | Something the four don't cover | Ask what, then record it accurately |

**Skip is a first-class answer, not a failure to decide.** Most of section B *should* be skipped for
any given product. Present it neutrally — never imply that adopting more is better.

## How to run it

1. **Batch with `AskUserQuestion`**, grouped by section, a few at a time. Don't walk fifteen items
   across fifteen turns.

2. **For each item give three things, short:** what is missing · what it costs to skip (the column
   says; verify it's still true) · your recommendation with the reason in one clause.

3. **Recommend honestly, including recommending Skip.** The table's recommendations were written
   without knowing the product. If something you've seen contradicts one, say so and recommend
   differently.

4. **Say what order matters.** SwiftLint before the PR checklist means the checklist inherits a
   mechanical baseline; the reverse wastes effort.

5. **Update GAPS.md as you go**, not at the end — an interrupted session must not lose answers.

---

## Constraints — both paths

- **Do not do the adopted work here** unless asked. Recording a decision and acting on it are
  separate; a `/gaps` run that quietly writes five modules is not a triage.
- **Never edit CLAUDE.md.** If an item implies a rule, say which section, show the exact text, and
  wait for a separate yes ([STRUCTURE.md](../../docs/STRUCTURE.md)).
- **Never delete a row.** Change its Status — the value of the file is knowing what was declined.
- Don't invent new gaps. If you spot one, mention it and ask whether to add it.
- If a Skip looks genuinely risky, say the risk **once**, plainly, then record the choice and move on.
