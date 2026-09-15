# Trigger evals for `new-feature`

Twenty queries — ten that must reach this skill, ten near-misses that must not. A description is
the whole triggering mechanism, and "it reads well" is not a measurement.

```bash
python3 Scripts/check-skill-triggers.py     # word overlap vs siblings — gates every edit here
```

The model-based optimizer is the second opinion; `.claude/memory/` records what it needs to run
(capped concurrency, python3.12, the `claude` CLI).

## Measured, 2026-09-09

2 runs per query, held-out split 12 train / 8 test.

| Description | Train | Test | Recall (train/test) |
|---|---|---|---|
| Shipped — house style, `Fires on "<quoted phrase>"` | 12/24 | 8/16 | **0% / 0%** |
| Drafted — imperative, **not applied** | 15/24 | 9/16 | 25% / 12% |
| Drafted — cost-of-improvising, **not applied** | 15/24 | 8/16 | 25% / **0%** |

Precision was 100% in all three. **Three framings, one outcome**: held-out recall never left the
noise band of an 8-query × 2-run test set, and train never passed 15/24.

**Not shipped.** Real movement off zero, but held-out gained one run (8/16 → 9/16) and still misses seven of eight positives.

The baseline fired on **none** of ten positives, including "scaffold FeatureProfile please, with
the router case and a mock" — near-verbatim from its own `Fires on "scaffold FeatureX"`.

The imperative rewrite is probably not the fix. Per the skill-creator guidance, *"Claude only
consults skills for tasks it can't easily handle on its own"* — scaffolding files is something the
model believes it can simply do, so it never reaches for the skill. That is the dangerous case, not
a cosmetic one: it scaffolds without reading the §2 rules, producing the wrong layer, no content
states and no injection seam.

**That hypothesis was tested, and it failed.** A description leading with what improvising costs —
*"Improvised, it becomes a package the app cannot consume: the mistaken layer, a sibling import that
should never compile… no route case registered in the composition root"* — plus an explicit hook for
the skip condition (*"including when it seems like a handful of files you could just produce
yourself"*) scored **0% held-out recall**, the same as the untouched baseline.

So the defect is **not** in the wording. Stop tuning it.

```
Use before creating any new screen, feature package, module, tab or flow — including when it seems like a handful of files you could just produce yourself. Improvised, it becomes a package the app cannot consume: the mistaken layer, a sibling import that should never compile, nothing for the situations a real screen must cover, no injected dependency seam, and no route case registered in the composition root. This carries where the code belongs, what it may depend on, and the single line that wires it in. Getting the shape right is the hard part, not creating the files.
```

## What this means, and what it does not

It does **not** mean the eval queries are wrong: they are ordinary scaffolding requests
("start the notifications module, nothing exists for it yet"), and the model declines all of them
while correctly declining all ten negatives too. That is evidence about what the model will
consult, not about the queries.

What it leaves is a §0-shaped question this file cannot answer: **if a skill cannot be made to fire,
should it be a command?** `docs/STRUCTURE.md` already draws that line — *"If it must never trigger
by inference, it is a command"* — and `CLAUDE.md` §3 already writes it in the slash form,
`Use /new-feature`. Measured recall of 0% says the inference half was never real. Converting it
would also touch `CLAUDE.md` §2.13, whose "name the matching skill before starting" presumes
recognition, so it needs approval rather than a quiet edit.

**Before spending more on descriptions, spend it on the measurement.** At 8 held-out queries × 2
runs, a one-run difference is noise, and every result here sat inside it. Raising
`--runs-per-query` would settle whether the 12% was ever real.

## The drafted rewrite, kept because it passes the gate

It clears `check-skill-triggers.py` at 44/44 and claims none of OpenSpec's vocabulary. It is
recorded here so the next attempt starts from it rather than re-deriving it — and so nobody ships
it believing it was validated.

```
Use when something does not exist yet and has to be built from nothing — a new screen, a feature package, a module, a tab, or a whole flow. It covers where the code belongs, what it may depend on, which situations the screen must cover, and the single line that wires it into the composition root. Reach for it whenever the answer means creating files rather than modifying what is already there, even when the ask names only the thing and not the scaffolding around it.
```

## Two traps this cost us

- **The scorer matches by prefix.** `diff` matched *differs*; `mockup` matches *mock*. A word you
  did not think you used can claim a sibling's fixture.
- **Removing a word can lose a tiebreak.** Dropping `fix` and `why` from `debug` turned two clean
  wins into three-way ties with `new-feature`'s *screen* and `tool-profile`'s *profile*.

Adding or removing a word is only justified by a diagnosis — which query, which matching term.
Re-run the gate after any edit.

## What no gate here measures

The optimizer runs the real model against **one skill in isolation**; the gate scores all three
**together** but only by word overlap. Production is real model plus all three competing, which
neither measures. A good number is necessary, not sufficient.
