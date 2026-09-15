---
name: skill-description-optimizer-needs-low-concurrency
description: The skill-creator description optimizer defaults to ~24 parallel 'claude -p' workers and dies with 'RuntimeError: claude -p exited 1' on rate limits — cap --num-workers, and it needs python3.12 plus the claude CLI, neither of which is the default here
metadata:
  type: project
---

Running `scripts/run_loop.py` (the skill description optimizer) needs three things that are not true by default here:

- **`--num-workers 2`.** The default spawned 24 concurrent `claude -p` processes and the run died in iteration 2 with `RuntimeError: claude -p exited 1`. A single `claude -p` smoke test passed both before and after, so the cause is rate limiting under concurrency, not auth.
- **`python3.12`.** The default `python3` is 3.9 from Xcode, and `improve_description.py` uses `str | None` (PEP 604), so it fails at import under 3.9.
- **The `claude` CLI**, which was absent — `npm i -g @anthropic-ai/claude-code` puts it at `/opt/homebrew/bin/claude`.

Write the run log somewhere outside the session scratchpad: that directory is session-scoped, and a session restart deleted a finished run's log. The eval set survives because it is tracked at `.claude/skills/tool-profile/evals/trigger-eval.json`.

Two measurements, not one. `Scripts/check-skill-triggers.py` scores word overlap against sibling descriptions and is what gates a description change; the optimizer asks a model whether it would actually consult the skill. Neither replaces the other, and the optimizer catches cases word overlap cannot — a query that refers to a recorded fact without naming the concept.

**Why:** 
**How to apply:** 

**Why:** The failure is silent about its cause. `claude -p exited 1` reads like broken auth, so the
instinct is to re-authenticate or abandon the run — but a single smoke test passes, which sends you
looking in the wrong place. The real cause is concurrency, and nothing in the error says so.

**How to apply:** Before running the optimizer, cap `--num-workers 2`, invoke it with `python3.12`,
confirm `command -v claude`, and point `--report`/`--results-dir` outside the session scratchpad.
Smoke-test `claude -p` first — it is one cheap call that separates auth from rate limiting. Keep
`Scripts/check-skill-triggers.py` as the gate on any description edit; treat the optimizer as the
second, slower opinion rather than a replacement.
