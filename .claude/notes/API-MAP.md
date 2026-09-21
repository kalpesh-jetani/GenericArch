# API Map

Every endpoint the app calls, and the code that calls it. An index — grep a row, then open the call
site it points at.

**Read it when** you need to find where an endpoint is called, or which screen depends on one —
before grepping the tree.

---

## Endpoints

Filled by `/sync-app-notes` from the project's call sites. Columns follow the active profile; the
shape below is the common one. Blank until a profile is declared.

| Method | Path | Screen | Caller — *what's there* | File |
|---|---|---|---|---|
| — | — | — | — | — |

---

## Reading a row

| Column | What it is | How it is resolved |
|---|---|---|
| **Method** | the verb, read at the call site | — |
| **Path** | the literal, with interpolation normalised to `{param}` | — |
| **Screen** | the user-visible surface that triggers the call | — |
| **Caller** | the type that owns the call | — |
| **File** | where the call is written — the code that would change | — |

---

## Gaps

| Finding | Where | Noted |
|---|---|---|
| — | — | — |
