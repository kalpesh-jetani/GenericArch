# Pattern — feature-complete

**Not a skill yet.** It becomes one when this repo has the code it describes — `/learn feature-complete`
promotes it. Until then it is reference: read it when the situation arises.

- **Promote when:** there is a feature to close out
- **Trigger phrases it would claim:** Close out finished work and decide what to keep from it. Fires when a feature is called done — "that's finished", "wrap up the auth work", "mark this complete", "close this out" — or after /verify ret…

---

**Index before grep** — check the `.claude/notes/` inventories first ([PATTERN-SEARCH.md](../PATTERN-SEARCH.md)); they map a name to its files without a search.

**Index first.** Look up the feature's own row in [FEATURES.md](../../.claude/notes/FEATURES.md) before grepping the codebase, then follow the row to its detail — a code path, or a sibling detail file. The note answers *what exists*; the pointer answers *what it is*.

# Closing out a feature

Two jobs: confirm it is actually finished, then decide what is worth keeping from how it was built.

---

## 1. Confirm it is done before offering to close it

Run `/verify` first, or check [DONE.md](../DONE.md). **Do not offer the closing options
over a red checklist** — "mark complete" on unfinished work is how a definition of done stops
meaning anything.

If items are outstanding, list them and stop. If some are 👁 (device, VoiceOver, Mac resize), say
which were **not** checked rather than counting them as passed.

## 2. Ask — four outcomes, always all four

Use `AskUserQuestion`. Lead with what was built, in one line, so the choice is informed.

**Use these labels verbatim.** They say what the option *does*, not what it is called internally —
"this can be used in future, so save it" is answerable without knowing that a skill is what gets
saved. Do not shorten them back into jargon.

| Option | What happens |
|---|---|
| **This can be used in future — so save it** | Capture the reusable pattern as a new skill, then close |
| **Just Close** | Record the outcome as a note. No skill |
| **Continue** | Not finished — keep working. Nothing is closed or recorded |
| **Skip** | Decide later. The feature stays open, and stop asking for now |

**Continue and Skip are different.** *Continue* means there is more to build and work resumes now.
*Skip* means the work has stopped but the closing decision is deferred. Conflating them either
drops work on the floor or nags about a feature nobody is touching.

If §1 found outstanding items, **offer Continue first** — the checklist has already named what is
left to do.

**Recommend honestly, and that usually means "Just Close".** Most features teach nothing another
feature can reuse — they are one screen, one endpoint, one shape of data. Say so:

> This was a settings toggle list: three rows, no async, no new tokens. There's no pattern here that
> a future feature would follow. **Just Close** — recommended. A skill for it would be always-on
> description cost for something that fires once, wrongly.

## 3. "This can be used in future — so save it" → create the skill

### 3a. First, judge whether a pattern actually exists

A skill is worth writing only if **the next similar feature would follow the same sequence**. Test
it against three questions, and say the answers out loud:

1. **Did this take a non-obvious sequence?** Order that mattered, a setup step that is easy to miss.
2. **Would a second feature of this kind repeat it?** Name the plausible second feature. If you
   cannot, there is no pattern.
3. **Did it hit a gotcha worth warning about?** Something that cost time and would cost it again.

Fewer than two yeses → say so and fall back to *Just Close*. **Do not create a thin skill to honour
the option that was picked** — that is how a skills directory becomes noise nobody trusts.

### 3b. Draft it — as pointers into the code, not a retelling of it

**A derived skill references the files; it does not describe what they contain.** Prose about code
is stale the moment the code changes, and it will still be followed. A path with a note stays
useful: it lands on the living version, and if the file is gone the skill is visibly wrong instead
of quietly wrong.

So every step cites the file that shows it, with a clause saying what to look at there.

```markdown
---
name: <verb-noun, kebab-case, no collision with an existing skill>
description: <trigger phrases · when NOT to use it — short; the body carries the detail>
---

> **Derived from** Feature<Name>, <date>. Delete it when the files below stop matching how the work
> is done — a derived skill that no longer describes reality is worse than none.

# <Title>

## The sequence that worked

1. **Protocol and mock before any view** —
   `Packages/Features/FeatureAuth/Sources/FeatureAuth/Services/Authenticating.swift` — the
   capability and its mock, written first so the view model had something to test against.
2. **View model exposes `ContentState`** —
   `Packages/Features/FeatureAuth/Sources/FeatureAuth/ViewModels/LoginViewModel.swift` — note how
   `failed` keeps the entered email rather than clearing the form.
3. **Assembly is the only file that sees the container** —
   `Packages/Features/FeatureAuth/Sources/FeatureAuth/DI/AuthAssembly.swift`.

## Decisions this settled

Link the [DECISIONS.md](../DECISIONS.md) rows. Do not restate them.

## What cost time

The gotcha, the symptom that gives it away, and **the file where the fix lives** — one line each.
```

Rules for the draft:

- **Cite, don't narrate.** If you find yourself explaining what a function does, link the function
  instead — it has a doc comment ([CONVENTIONS.md](../CONVENTIONS.md)).
- **Never a bare path.** Each one carries a clause saying what to look at there
  ([STRUCTURE.md](../STRUCTURE.md)).
- **Paths must resolve.** Verify each before writing it; a pointer to a moved file is worse than no
  pointer.
- **Record the sequence that was actually followed**, including what was got wrong first. A tidied
  version omits the part worth keeping.
- **Keep it short.** A derived skill that runs past roughly a screen is narrating. The code is the
  detail; this is the map.
- **Description is for triggering only** — the phrases that should fire it and when not to use it.
  Vocabulary must not overlap an existing skill; reference siblings by name, never by topic.

### 3c. Check it will not collide, then get approval

```bash
python3 Scripts/check-skill-triggers.py     # existing skills still route correctly
ls .claude/skills                            # no name collision
```

Add a case for the new skill to that script — a skill with no test is a trigger nobody verified.

Then **show the full draft and wait for a yes** before writing the file. A skill changes behaviour
in every future session; that is the user's call.

### 3d. Guard against sprawl

- **If it overlaps an existing derived skill, merge instead of adding.** Two skills covering
  neighbouring patterns means neither fires predictably.
- Keep derived skills findable: `grep -l "Derived from" .claude/skills/*/SKILL.md`.
- When one is superseded, **delete it in the same change** that supersedes it.

## 4. "Just Close" → the note, and nothing else

No skill. Record the outcome where it will be read:

- **`Feature<Name>.md`** — a short *What this settled* section: the shape chosen, the decisions
  taken, anything a future reader would otherwise have to reconstruct from the diff.
- **[FEATURES.md](../../.claude/notes/FEATURES.md)** — the feature and screen rows, with their file paths
  and a note on each ([STRUCTURE.md](../STRUCTURE.md)). Targeted edits, not a
  `/sync-app-notes` run.
- Any §0 answer that is not yet logged → `/decide`.

## 5. "Continue" → resume, with the next step named

Close nothing, record nothing. Say what remains and pick it up:

- If `/verify` left items outstanding, **that list is the plan** — start at the top.
- If everything passed and the user still chose Continue, ask what is missing. The checklist
  measures the rules, not whether the feature does what it was for.
- Don't re-offer these options until there is a reason to think it is done again.

## 6. "Skip" → say what stays open

Change nothing. State plainly that the feature is still open, and what remains — so *Skip* is not
later mistaken for *done*. Unlike Continue, work is not resuming, so leave `.claude/notes/` and
the feature doc exactly as they are: a half-recorded feature is worse than an unrecorded one.

---

## Offering a derived skill later

A derived skill fires on its own description when similar work starts. Two things make that
reliable, and both belong to whoever creates it:

- The `description` names the real trigger phrases — that is the whole mechanism.
- `new-feature` checks for derived skills before scaffolding and offers any that match, so the
  pattern surfaces even when the phrasing does not quite fire it.
