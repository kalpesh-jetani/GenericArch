# Memory

What earlier sessions learned about **this repo**, kept in the repo so it survives a clone, a moved
checkout, and a second developer.

- **Read this when:** starting work. It is the cheapest context in the repo — one line per fact.
- **Maintained by:** Claude, as it learns. Every write is a tracked file change you see in the diff.
- **One fact per file**, `<slug>.md`, indexed by one row below. A memory with no row is a memory
  nobody finds.

## What belongs here — and what does not

| Type | Goes here? | Why |
|---|---|---|
| `project` | **Yes** | Ongoing work, goals, constraints not derivable from the code or git history |
| `reference` | **Yes** | Pointers to external resources — URLs, dashboards, tickets |
| `feedback` | **Yes** | Guidance on how to work in *this repo*, with the reason it was given |
| `user` | **No** | Who a developer is, and their preferences, is per-person — it stays in Claude's own machine-local store and is never committed |

**Do not store what the repo already records.** Hard rules are CLAUDE.md §2, doc conventions are
[STRUCTURE.md](../../docs/STRUCTURE.md), code conventions are
[CONVENTIONS.md](../../docs/CONVENTIONS.md), settled decisions are
[DECISIONS.md](../../docs/DECISIONS.md). A rule written in two places drifts, and the copy that goes
stale is the one nobody is reading.

## Format

```markdown
---
name: <short-kebab-case-slug>
description: <one line — this is what gets scanned for relevance>
metadata:
  type: project | reference | feedback
---

The fact. For feedback and project, follow with **Why:** and **How to apply:** lines.
Link related memories with [[their-slug]].
```

Convert relative dates to absolute — "last week" is unreadable in six months.

---

## Index

| Memory | What it holds |
|---|---|
| [`claude-md-section-numbers-are-load-bearing.md`](claude-md-section-numbers-are-load-bearing.md) | ~380 repo-wide §N citations — shrink CLAUDE.md bodies, never move a heading |
