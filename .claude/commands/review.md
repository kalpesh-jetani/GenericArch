---
description: Review someone else's diff or PR against the architecture rules — reports findings, never edits
argument-hint: [PR number, branch, or base ref — defaults to the current branch vs main]
allowed-tools: Bash, Read, Grep, Glob
---

```bash
./Scripts/ga-step.sh after project-init      # sequence gate
```

**Exit 5 means an earlier step has not run.** Say which one, and stop — never pass `--force`, and
never work around it. Order and why: [SEQUENCE.md](/docs/operations/SEQUENCE.md)(../../docs/SEQUENCE.md).

Review a change you did not write.

Target: `$ARGUMENTS` — a PR number, a branch, or a base ref. Default: current branch vs `main`.

```bash
# a branch or the current one
BASE=$(git merge-base HEAD main 2>/dev/null || echo main)
git diff "$BASE"...HEAD --stat
git log --oneline "$BASE"..HEAD

# or a PR by number
gh pr diff "$ARGUMENTS" --patch | head -400
gh pr view "$ARGUMENTS" --json title,body,files --jq '.title, .body'
```

`/verify` walks your own working tree. This walks someone else's finished work, so the bar is
different: **you are not fixing it, you are telling them what you found.**

---

## 1. Read the diff before the rules

Understand what the change is *for* first. A review that opens with a lint violation and never
mentions that the approach is wrong has failed at the expensive part.

Say in one line what the change does. If you cannot, that is the first finding.

## 2. Check what a linter cannot

The active profile's check command (`./Scripts/check.sh` runs it) already covers the mechanical
rules a linter can express. **Do not spend the review on those** — say "check covers this"
and move on. (Do not run it yourself — it may compile, CLAUDE.md §2.8.)

The active profile's rules drive the structural checks a linter cannot make — run whichever the
profile declares. One holds on any stack: an inventory row that should have moved with the code and
did not.

```bash
FILES=$(git diff --name-only "$BASE"...HEAD)
printf '%s\n' "$FILES" | grep -q '^\.claude/notes/' \
  || echo "NOTE: check whether an inventory row should have changed with this diff, and did not"
```

What needs a human-shaped read:

| Look for | Because |
|---|---|
| A violation of one of the active profile's rules that a linter cannot express | The profile states these; with no profile, only the neutral §2 rules apply |
| An error mapped with the wrong retry semantics | A Retry affordance on a non-retryable failure |
| A note row that should have changed and did not | The inventory silently goes stale |
| A doc comment that restates the signature | Meta comment, not documentation (§2.7) |

## 3. Say what you are unsure about

A review that only lists certainties is a review that skipped the hard parts. If a change looks
wrong but you cannot say why, say that — it is more useful than silence, and cheaper than a bug.

Separate:

- **Blocking** — a §2 rule broken, or a defect with a concrete failure case.
- **Worth changing** — real, not blocking. Say so plainly so it can be deferred.
- **Question** — you do not understand the intent. Ask; do not guess and then critique the guess.

## 4. Never

- **Never edit their branch.** Report; they decide.
- **Never commit, push, or build** (§2.2, §2.8). Hand over the command if you want it run.
- **Never rewrite a decision that DECISIONS.md already settled** — if the change follows a recorded
  decision you disagree with, that is a `/decide` conversation, not a review comment.
