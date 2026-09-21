# Build Stages & Environments

The build stages this product defines and the rule for picking between them. A stage pairs a build
configuration with an environment (which backend it points at, what is logged, how it is
distributed).

**Read it when** choosing which stage to build, adding a stage-dependent value, wiring an
environment, or preparing a release.

---

## The stages

Filled by `/sync-app-notes` from the active profile's build configuration. Columns follow the
profile; the shape below is the common one — development, QA, prerelease, production. Blank until a
profile is declared.

| Stage | Configuration | Purpose | Who runs it | Distribution |
|---|---|---|---|---|
| — | — | — | — | — |

A stage handed to another person must be **release-like** — optimized, with development-only checks
compiled out. A QA build that behaves differently from the shipped build because it was built
unoptimized has tested nothing.

---

## What differs, per stage

The settings a stage changes — the backend it points at, log level, feature flags, signing,
telemetry destination. Filled from the project.

| Setting | Development | QA | Prerelease | Production |
|---|---|---|---|---|
| — | — | — | — | — |

---

## How configuration reaches code

Stage-dependent values belong in committed, reviewable configuration — one place per stage, resolved
**once** at the composition root into a typed value and injected. A feature must never read a build
flag directly: it receives the resolved environment, so it stays testable for every stage.

**Default to production** when a value is missing: a misconfigured build should fail closed —
quiet, no debug surfaces — not open.

---

## Launch guards

Assert the combination at launch and fail the build in CI rather than shipping a mismatch:

- A production build must not resolve a non-production backend.
- A production build must not carry development-only compilation flags.
- Any stage with debug surfaces on must not carry a production identity.
- The telemetry destination must match the stage.

---

## Gaps

| Finding | Where | Noted |
|---|---|---|
| — | — | — |
