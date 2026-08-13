---
description: Review someone else's diff or PR against the architecture rules — reports findings, never edits
argument-hint: [PR number, branch, or base ref — defaults to the current branch vs main]
allowed-tools: Bash, Read, Grep, Glob
---

Review a change you did not write.

Target: `$ARGUMENTS` — a PR number, a branch, or a base ref. Default: current branch vs `main`.

```bash
git diff main...HEAD --stat        # or: gh pr diff <n>
```

`/verify` walks your own working tree. This walks someone else's finished work, so the bar is
different: **you are not fixing it, you are telling them what you found.**

---

## 1. Read the diff before the rules

Understand what the change is *for* first. A review that opens with a lint violation and never
mentions that the approach is wrong has failed at the expensive part.

Say in one line what the change does. If you cannot, that is the first finding.

## 2. Check what a linter cannot

`./Scripts/check.sh` and SwiftLint already cover raw strings, force-unwraps, `.alert`, `#if DEBUG`
in a feature, and the iOS floor. **Do not spend the review on those** — say "check.sh covers this"
and move on.

What needs a human-shaped read:

| Look for | Because |
|---|---|
| A missing `ContentState` case | The screen renders nothing, and no rule catches which case is absent |
| A new boolean beside `ContentState` | The state drift §2.5 exists to prevent |
| An error mapped with the wrong `isRetryable` | A Retry button on a non-retryable failure |
| A feature reaching for another feature's type | §2.1, and the manifest may not catch it yet |
| A token added that duplicates an existing one | `style-guide` — nobody reconciles these later |
| A note row that should have changed and did not | The inventory silently goes stale |
| A doc comment that restates the signature | Meta comment, not documentation |

## 3. Say what you are unsure about

A review that only lists certainties is a review that skipped the hard parts. If a change looks
wrong but you cannot say why, say that — it is more useful than silence, and cheaper than a bug.

Separate:

- **Blocking** — a §2 rule broken, or a defect with a concrete failure case.
- **Worth changing** — real, not blocking. Say so plainly so it can be deferred.
- **Question** — you do not understand the intent. Ask; do not guess and then critique the guess.

## 4. Never

- **Never edit their branch.** Report; they decide.
- **Never commit, push, or build** (§2.11, §2.12). Hand over the command if you want it run.
- **Never rewrite a decision that DECISIONS.md already settled** — if the change follows a recorded
  decision you disagree with, that is a `/decide` conversation, not a review comment.
