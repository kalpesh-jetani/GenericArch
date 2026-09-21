# Project & Resolved Stack

The stack the active profile declares, resolved against the machine. **Never quote a version from
memory** — every value here is filled from the project or the profile's own probe.

**Read it when** you need the declared language, build system, test framework or their versions —
before writing anything that depends on one.

---

## Resolved stack

Filled by `/sync-app-notes` from the active profile (`profiles/<name>/`) and, where the profile
wires one, a machine probe. Blank until a profile is declared.

| Item | Value | Source |
|---|---|---|
| Stack profile | — | — |
| Language(s) | — | — |
| Build system | — | — |
| Test framework | — | — |

---

## Module / target inventory

The units the build produces, and what each links. Columns are the profile's to define; the ones
below are the common shape.

| Unit | Type | Depends on | Notes |
|---|---|---|---|
| — | — | — | — |

---

## Gaps

| Finding | Where | Noted |
|---|---|---|
| — | — | — |

`/sync-app-notes` flags a unit with no declared type, a dependency that resolves to nothing, and a
version stated in a doc but not in the project.
