# Trigger evals for `debug`

Twenty queries — ten that must reach this skill, ten near-misses that must not. A description is
the whole triggering mechanism, and "it reads well" is not a measurement.

```bash
python3 Scripts/check-skill-triggers.py     # word overlap vs siblings — gates every edit here
```

The model-based optimizer is the second opinion; `.claude/memory/` records what it needs to run
(capped concurrency, python3.12, the `claude` CLI).

## Measured, 2026-09-09

2 runs per query, held-out split 12 train / 8 test.

| Description | Result |
|---|---|
| Shipped — house style, `Fires on "<quoted phrase>"` | 17/24 train · 11/16 test · precision 100% · recall 42%/38% |
| Drafted rewrite — imperative, **not applied** | 20/24 train · 11/16 test · precision 100% · recall 67%/38% |

**Not shipped.** Train rose, held-out did not move at all (same 11/16, same 6/8 by query). A train-up/test-flat split is the signature of fitting the eval queries.

Both persistent held-out failures are ones this draft explicitly tried to cover — "ui freezes
for about 4 seconds" (the draft adds *the ui hangs*) and dev-scheme-vs-TestFlight (the draft adds
*one build behaves unlike another*). Adding the vocabulary did not make the model route them, so
the gap is not vocabulary.

## The drafted rewrite, kept because it passes the gate

It clears `check-skill-triggers.py` at 44/44 and claims none of OpenSpec's vocabulary. It is
recorded here so the next attempt starts from it rather than re-deriving it — and so nobody ships
it believing it was validated.

```
Use when the app is doing something wrong and you have to work out why before you can fix it — it crashes or throws, a view renders blank or white, a control does nothing when tapped, a localized string shows its raw key, a font renders as something else, the ui hangs, memory climbs and never returns, items duplicate or vanish, or one build behaves unlike another. Work from the symptom to the owning layer first, because the layer where a fault shows is usually not the layer that caused it.
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
