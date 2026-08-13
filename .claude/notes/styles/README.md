# styles/

One file per style that **is not yet code**, or that spans more files than a single path can name.

- **Indexed from:** [../STYLE-GUIDE.md](../STYLE-GUIDE.md) — every file here has a row there. A note
  nobody indexed is a note nobody will find.
- **Naming:** `<surface>-<variant>.md` — `navigation-bar-style1.md`, `card-elevated.md`.

## When a file belongs here

| Situation | Home |
|---|---|
| Implemented | **The code path.** Not a note — a note describing shipped code goes stale and still gets followed |
| Agreed, not built | Here, until it ships |
| Spans several files (a surface's whole treatment) | Here, listing each path with a note |

**When the code lands, delete the note and put the path in the index row.** Keeping both means two
sources of truth, and the one that rots is the one being read.

## What a style note contains

The decisions a reader cannot get from a screenshot: exact tokens used (by name, from
[../STYLE-GUIDE.md](../STYLE-GUIDE.md)), behaviour at each size class, what changes in dark and RTL,
and what was deliberately *not* done. Values go in as **token names, never raw numbers** — a raw
number here is a token that was never registered.
