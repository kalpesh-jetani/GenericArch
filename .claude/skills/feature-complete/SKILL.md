---
name: feature-complete
description: Close out finished work and decide what to keep from it. Fires when a feature is called done — "that's finished", "wrap up the auth work", "mark this complete", "close this out" — or right after /verify returns clean. Offers four outcomes: capture the reusable pattern as a new skill, close with a note only, keep working, or decide later. Never creates a skill without judging that a genuine repeatable pattern exists, and records the outcome in the feature doc and the FEATURES note. Do NOT use mid-build, or to determine whether work is done — that is /verify.
---

# Closing out a feature

Two jobs: confirm it is actually finished, then decide what is worth keeping from how it was built.

---

## 1. Confirm it is done before offering to close it

Run `/verify` first, or check [DONE.md](../../../docs/DONE.md). **Do not offer the closing options
over a red checklist** — "mark complete" on unfinished work is how a definition of done stops
meaning anything.

If items are outstanding, list them and stop. If some are 👁 (device, VoiceOver, Mac resize), say
which were **not** checked rather than counting them as passed.

## 2. Ask — four outcomes, always all four

Use `AskUserQuestion`. Lead with what was built, in one line, so the choice is informed.

| Option | What happens |
|---|---|
| **Mark Feature as Completed** | Capture the reusable pattern as a new skill, then close |
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

## 3. "Mark Feature as Completed" → create the skill

### 3a. First, judge whether a pattern actually exists

A skill is worth writing only if **the next similar feature would follow the same sequence**. Test
it against three questions, and say the answers out loud:

1. **Did this take a non-obvious sequence?** Order that mattered, a setup step that is easy to miss.
2. **Would a second feature of this kind repeat it?** Name the plausible second feature. If you
   cannot, there is no pattern.
3. **Did it hit a gotcha worth warning about?** Something that cost time and would cost it again.

Fewer than two yeses → say so and fall back to *Just Close*. **Do not create a thin skill to honour
the option that was picked** — that is how a skills directory becomes noise nobody trusts.

### 3b. Draft it, don't write it yet

```markdown
---
name: <verb-noun, kebab-case, no collision with an existing skill>
description: <what it covers · the phrases that should fire it · when NOT to use it>
---

> **Derived from** Feature<Name>, <date>. Generalise it when a second feature confirms the pattern;
> delete it when it stops matching. A derived skill that no longer describes how the work is done
> is worse than none — it will be followed anyway.

# <Title>

## The sequence that worked
1. …            ← the actual order followed, not an idealised one

## Decisions this settled
… link the DECISIONS.md rows rather than restating them

## What cost time
… the gotcha, and the symptom that gives it away
```

Rules for the draft:

- **Write the sequence that was actually followed**, including the part that was got wrong first.
  A cleaned-up version omits exactly the thing worth recording.
- **Description decides whether it ever fires.** Name the concrete trigger phrases and when *not*
  to use it. Vague descriptions fire everywhere or nowhere.
- **Vocabulary must not overlap an existing skill.** Naming another skill's *topic* pulls its
  keywords in — reference siblings by name only.

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
- **[FEATURES.md](../../notes/FEATURES.md)** — the feature and screen rows, with their file paths
  and a note on each ([STRUCTURE.md](../../../docs/STRUCTURE.md)). Targeted edits, not a
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
