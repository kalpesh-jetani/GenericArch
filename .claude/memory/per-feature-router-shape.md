---
name: per-feature-router-shape
description: Real apps often declare one router enum per feature with `path` in a separate extension — scan-api-map.py handles it in a second pass, and that shape found 0 endpoints before the fix
metadata:
  type: project
---

`scan-api-map.py`'s original discovery assumed the sample-project shape: one router enum, one `path`
switch, one call convention (`callAPI(path:method:)`). A large real app instead had ~11
`*Resources.swift` enums, each conforming to a `TargetType`-style protocol — and **the `path` property
lived in a separate `extension`, not in the enum body**. Result: `router: null`, 0 endpoints, against
a note that legitimately held 97 rows.

The fix is a second pass that runs only when the first declares nothing, works **per file**, and
attributes a property to its enclosing `extension X` (falling back to the file's only enum, and
skipping files with several — guessing there attaches rows to the wrong endpoint). It now finds 90
endpoints with methods and `{param}`-normalised paths.

Two traps worth keeping:

- `var path: String { get }` is a **protocol requirement**, not a router. Counting it reports a gap
  that does not exist.
- The pass proves paths but not which screen calls them, because no call convention was assumed. It
  reports `pairing: "unproven"` and the note's Screen column renders `?` — an empty cell would read
  as "no screen", which is a different claim.

**Why:** it is the concrete case for the three-tier note model — a note needing judgement rarely means
every *column* does.

**How to apply:** when a scanner finds nothing, check whether the *shape* differs before assuming the
repo is empty, and add a shape-specific pass rather than loosening the existing one.
