---
description: Look something up in the .claude/notes/ index — a screen, route, endpoint, asset, colour, font, token, target — in one call, without opening a note
argument-hint: <a screen, route case, endpoint path, asset, colour token, or target>
allowed-tools: Bash, Grep
---

```bash
./Scripts/ga-step.sh after sync-app-notes      # sequence gate
```

**Exit 5 means an earlier step has not run.** Say which one, and stop — never pass `--force`, and
never work around it. Order and why: [SEQUENCE.md](../../docs/SEQUENCE.md).

Answer "where is `$ARGUMENTS`?" from the index, not from the codebase.

```bash
./Scripts/find.sh "$ARGUMENTS"
```

That is the whole command on the hit path. It prints the matching rows and nothing else — **no note
is opened**, which is the point ([PATTERN-SEARCH.md](../../docs/PATTERN-SEARCH.md)).

## Reading the result

Each row is self-contained by construction (`/sync-app-notes` §S3): the key, what kind of thing it
is, and the directory it lives in, relative to the `Root:` the script prints beside the note name.
Reconstruct a full path as `<root><row path><Key>.swift` unless the row spells a filename out.

**Render paths as links when you report them.** Rows store bare paths deliberately — link syntax is
overhead in a file that is only ever grepped — so whoever surfaces a row is the one who makes it
clickable.

## On a miss

The script exits non-zero and prints the code-search fallback. Two things must happen, in order:

1. **Search the code** for the term.
2. **Record the row** in the note that owns it, in the same change — one insertion, no rewrite
   (CLAUDE.md §5). This is what makes the *next* lookup cost one call instead of a tree walk.

A miss you don't record is a miss you pay for again. That is the only maintenance this index needs.

## When not to use it

- **You need the rules, not the location** — read the module doc. `grep -i <topic> .claude/MAP.tsv`
  routes you there; the script prints those rows on a miss for exactly this reason.
- **The thing is brand new and unrecorded** — a miss is expected, and step 2 above is the work.
- **You need to know *why*, not *where*** — notes carry facts, `docs/` carries reasoning.

Never widen this into a rescan. If many rows are missing, say so and let the user type
`/sync-app-notes` (CLAUDE.md §5).
