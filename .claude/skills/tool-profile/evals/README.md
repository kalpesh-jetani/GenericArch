# Trigger evals for `tool-profile`

Twenty queries — ten that must reach this skill, ten near-misses that must not. They exist because
a description is the whole triggering mechanism, and "it reads well" is not a measurement.

```bash
# the repo's own scorer: does the description collide with a sibling's vocabulary?
python3 Scripts/check-skill-triggers.py

# the model-based optimizer: would Claude actually consult the skill? (needs the claude CLI)
python3.12 -m scripts.run_loop --eval-set .claude/skills/tool-profile/evals/trigger-eval.json \
  --skill-path .claude/skills/tool-profile --model <model-id> --max-iterations 5 --verbose
```

The two measure different things and neither replaces the other. `check-skill-triggers.py` scores
word overlap against sibling descriptions — it catches a skill stealing another's vocabulary, and it
is the one that gates a change here. The optimizer asks a model whether it would consult the skill,
which is the thing that actually happens in a session.

## Measured results

Real-model triggering over these 20 queries, 2 runs each, held-out split 12 train / 8 test:

| Description | Train | Test | Precision | Recall (train/test) |
|---|---|---|---|---|
| House style — `Fires on "<quoted phrase>"` | 15/24 | 11/16 | 80% / 100% | 33% / 38% |
| Optimizer's own winner | 20/24 | 12/16 | 100% | 67% / 50% |
| **Shipped** — imperative, no vendor named | 19/24 | **13/16** | **100%** | 58% / **62%** |

Two things that matter more than the totals:

- **The quoted-phrase style under-triggers badly.** "do we have a profile for linear yet" scored
  **0/2** against a description containing `Fires on "do we have a profile for this tool yet"`. A
  quoted trigger phrase sitting in the description did not cause the skill to be consulted.
  Imperative *"Use when work touches…"* framing is what roughly doubled recall.
- **Removing the vendor names improved the held-out score** (12/16 → 13/16, recall 50% → 62%).
  Naming Figma, Linear and Jira helped train and hurt test — it was overfitting to the queries.

Precision is 100% everywhere, so the risk here has never been over-firing. It is silence.

## What the negatives are for

The ten `should_trigger: false` queries are deliberately **near**-misses that share vocabulary with
this skill while needing something else: `/learn`'s "what we take from this vendor", a `debug`
symptom that happens to name a connector, a §7 Swift wrapper, an OpenSpec delta spec, a notes
resync. An obviously-unrelated negative tests nothing.

## Three known failures, left in on purpose

They are recorded here so nobody re-discovers them and "fixes" them by stuffing the description:

| Query | Why it is not worth fixing |
|---|---|
| "figma mcp connected … before I pull frames for the settings screen" | `new-feature` legitimately owns *start*, *settings* and *screen* in that one sentence. Out-scoring it needs three more incidental words |
| "the aspect ratio we wrote down turned out wrong, it's per file not per node" | Refers to a recorded fact without naming the concept. Word overlap cannot reach it; a model reading the registry can |
| "the github connector keeps asking me to reauthorise" | Fires on *connector*, this skill's central noun. `SKILL.md` step 1 catches it, and over-triggering is the cheaper failure |

**Adding a word to the description is only justified by a diagnosis** — which query, which matching
term. Two rules learned the hard way: the scorer matches by **prefix**, so `mockup` claims *mock*
and steals `new-feature`'s "add a protocol and a mock"; and an incidental word like *call* leaked
the api-map resync query. Re-run both checks after any edit.

## The OpenSpec boundary is not negotiable

`check-skill-triggers.py` also asserts that no house skill claims OpenSpec's vocabulary —
*propose, change, plan, tasks, spec, delta, capability, verify, explore, archive*, and `link` via
"magic-link". Those `SPEC_WORKFLOW` fixtures run **even when the checker reports OpenSpec absent**,
and that is deliberate.

GenericArch is the existing repo; OpenSpec is external and arrives only when `/openspec-install`
runs. **Installed, it is the priority executor for spec-workflow work**
([DECISIONS.md](../../../../docs/DECISIONS.md)). So the boundary has to hold *before* it is
installed — a description written while OpenSpec is absent is exactly the one that mis-fires once it
is there, and nothing would catch it at that point.

This is what ruled out the description-optimizer's own winning candidate. It scored better with the
real model but claimed `link` (STOLEN), plus `mockup`, `vendor` and `fields`. A higher trigger score
does not buy the right to shadow OpenSpec.
