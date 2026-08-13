---
description: Learn from a resource or from finished work, and record it — take a sample repo, Figma link, doc URL or a completed feature, write a usage note, index it, and promote a pattern to a skill when it has earned it
argument-hint: [a URL, a path, a pattern name, or a feature that just shipped]
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, WebFetch, AskUserQuestion
---

Turn something into repo knowledge: a resource you were given, or work that just finished.

Input: `$ARGUMENTS` — a URL, a local path, a pattern name from `docs/patterns/`, or nothing (then
ask what to learn from).

---

## 1. Ask for the source — do not infer it

Before writing anything, get the material. **Ask; do not guess from the name of the thing.**

| Building | Ask for |
|---|---|
| A screen or component | The Figma frame or a screenshot, and which existing screen it should resemble |
| An integration | The vendor's docs URL, and a working sample — theirs or yours |
| A pattern from elsewhere | The example repo or file, and what specifically to copy from it |
| A framework or tool | The docs URL, and what problem it is being brought in to solve |

Also ask the question that decides everything else: **what does success look like?** A resource with
no goal attached produces a summary nobody reads. A resource with a goal produces a usage note.

If the user has no source to give, say that plainly and stop — inventing an integration from the
name of an SDK is how a plausible, wrong implementation gets written.

## 2. Read it, then write the usage note

For a web or Figma link, fetch it. Then write `docs/resources/<name>.md`:

```markdown
# <Resource>

- **Source:** <url or path> — what it is
- **Goal:** what we are using it to accomplish
- **Read on:** <date>

## What we take from it
The specific pieces, each with the file or section they come from.

## What we deliberately do not take
The parts that conflict with a §2 rule, or that solve a problem we do not have.

## How it maps here
Their concept → our layer. Where the wrapper goes (§7) if it is a vendor.

## Open questions
What the source does not answer.
```

**Cite, do not transcribe.** A usage note that restates the vendor's documentation goes stale on
their next release and is worse than a link. Say what *we* do with it.

## 3. Index it

Every resource, pattern, feature and skill gets a row in [INDEX.md](../INDEX.md). A note nobody
indexed is a note nobody finds.

## 4. Promoting a pattern to a skill

`docs/patterns/` holds six patterns that ship un-promoted because they cannot fire in an empty repo.
`/learn <pattern>` promotes one.

**Promote only when all three are true:**

1. **The code it governs exists** — a `style-guide` skill with no registered tokens fires on nothing.
2. **It has been needed at least twice**, or once with a gotcha worth warning about. Once is an
   anecdote.
3. **Its trigger vocabulary does not collide** — `python3 Scripts/check-skill-triggers.py` after
   drafting, and add a prompt for it.

Then: move the body to `.claude/skills/<name>/SKILL.md`, rewrite the description as trigger phrases
only, **replace its generic examples with this repo's real file paths**, and delete the pattern file.
Two copies means one rots.

Show the draft and **wait for approval** before writing it — a skill changes behaviour in every
future session.

## 5. Learning from finished work

When a feature ships, `docs/patterns/feature-complete.md` has the full close-out procedure. The
short version: offer **save it as a skill · just close with a note · continue · decide later**, and
recommend *just close* unless the next similar feature would follow the same sequence. Most work
teaches nothing reusable, and a thin skill is worse than none.

## Constraints

- **Never invent a resource.** No plausible-looking API surface, no remembered SDK signature. If it
  was not fetched or supplied, it is not known.
- **Never promote a pattern to a skill unasked** — the always-on cost is the user's to accept.
- Do not fetch a URL the user did not give you.
- One resource note per resource. If two overlap, merge them.
