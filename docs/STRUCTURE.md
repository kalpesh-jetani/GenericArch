# Documentation structure

How this repo's guidance is organised, and the rules for maintaining it. **This file exists so that
CLAUDE.md doesn't have to carry them** — CLAUDE.md holds rules for building the app, not notes about
itself.

- **When to read this:** before adding or moving any guidance; before editing CLAUDE.md.

---

## CLAUDE.md is approval-gated

**Never edit CLAUDE.md without explicit user approval — including when you are certain the change is
correct.**

Confidence is not the test. CLAUDE.md is loaded into every session, so a change there alters how
every future response behaves, silently and indefinitely. That is the user's call, not a side effect
of another task.

The procedure:

1. Say what you would add, remove, or change, and which section.
2. Show the exact text.
3. Say what it costs — always-on context is finite; a rule that isn't load-bearing is pure overhead.
4. **Wait for a yes.** Not an inference, not "the user seemed to want this".

This applies to *any* path that would touch it: a decision recorded via `/decide`, a rule that
emerges from `/project-init`, a §0 answer, or a cleanup you noticed in passing. All of them stop and
ask.

## No meta notes in CLAUDE.md

CLAUDE.md contains rules about **building the app**. It does not contain:

| Keep out | Belongs in |
|---|---|
| Notes about how the docs are organised | this file |
| Rules about where to put documentation | this file |
| Why a rule was chosen, or what it replaced | [DECISIONS.md](DECISIONS.md) |
| History — "X was removed", "this used to be Y" | [DECISIONS.md](DECISIONS.md) |
| Descriptions of skills and commands | their own frontmatter |
| Justification longer than the rule itself | the module doc |

State the rule. If the reason is short and prevents a specific mistake, one clause is fine. If it
takes a paragraph, the paragraph goes in the module doc and the rule gets a link.

## The five homes

| Home | Holds | Auto-loaded |
|---|---|---|
| `CLAUDE.md` | always-on rules for building the app | **yes** — keep it small |
| `docs/` | hand-written reasoning: module design, cross-cutting reference | no |
| `.claude/notes/` | inventories generated from the code | no |
| `.claude/skills/` | procedures Claude should recognise and apply on its own | descriptions only |
| `.claude/commands/` | things the user triggers explicitly | no |

Deciding where something goes:

- Specific to one module → `docs/modules/<Module>.md`. One index row in CLAUDE.md, nothing more.
- A repeatable multi-step procedure → a skill. **No CLAUDE.md edit** — it's found from its
  `description:`.
- Something the user runs → a command. **No CLAUDE.md edit.**
- Prose a human wrote → `docs/`. Something a script could produce → `.claude/notes/`.
- A rule that applies everywhere and shapes every response → CLAUDE.md, **and only with approval**.

**Skill vs command:** a skill fires when the model recognises the situation; a command only runs when
typed. If it must never trigger by inference, it is a command.

**Project vs directory scope:** a nested `CLAUDE.md` loads only when files in that directory are
touched. Anything true of one package belongs there, not at the root — it is cheaper and more
accurate. Same for directory-scoped skills.

## Module doc contract

Every `docs/modules/<Module>.md` opens with exactly three lines:

```markdown
- **Package:** `Packages/<Name>` (local)   |   `GenericArch-<Name>` — extracted repo
- **Used by:** …
- **When to read this:** …
```

`Used by:` is how something stays out of CLAUDE.md — if it's relevant to one module, say so there
rather than promoting it.

## Notes contract

Two ways a note changes, and they are not interchangeable:

| | Targeted edit | Full rescan |
|---|---|---|
| **What** | The rows your change touches | `/sync-app-notes` rewrites all eight from a filesystem scan |
| **When** | Every insertion or deletion, same change | First setup, or drift too large to fix by hand |
| **Who starts it** | Claude, as part of the change | **The user, by typing the command** |

`sync-app-notes` is a **command precisely because of the rule above** — it must never fire by
inference, so it is not a skill. That is the worked example: when a procedure's own description has
to say "never invoke automatically", the description is doing a job the file type should be doing.

A rescan against a half-finished tree overwrites correct rows with incomplete ones — which is worse
than a stale note, because it looks current.

## Writing a path

**Never write a bare file path.** Anywhere a path is meant to be searched or followed — a note row,
an index, a grep recipe, a mermaid `click` target, a cross-reference — pair it with a short note
saying what is there.

```markdown
✅ `Packages/Navigation/Sources/Navigation/Route.swift:12` — the case declaration
✅ click homeFeed "…/FeedView.swift" "Paged feed — ContentState<Paged<Item>>"
❌ `Packages/Navigation/Sources/Navigation/Route.swift`
```

A path answers *where*, not *what*. Without the note the reader opens every hit to find the one they
want, which is precisely the work an index exists to remove. One clause is enough; if there is
nothing useful to say, the row probably isn't worth listing.

Paths are repo-relative and must resolve to exactly one file — no `.../` abbreviations, because grep
cannot follow them.

## Writing a skill from working code

A skill distilled from a finished feature **points at the code; it does not retell it**.

```markdown
✅ 2. View model exposes `ContentState` —
      `Packages/Features/FeatureAuth/…/LoginViewModel.swift` — note how `failed` keeps the
      entered email rather than clearing the form.

❌ 2. The view model holds an enum with six cases. On failure it stores the error and keeps the
      email so the user doesn't retype it. It also…
```

The prose version is stale the moment the code changes, and it will still be followed. The pointer
lands on the living version — and if the file has moved, the skill is *visibly* wrong rather than
quietly wrong.

It follows that a derived skill is **short**. Running past roughly a screen means it is narrating,
and the code is the detail. Its `description` is for triggering only: the phrases that should fire
it and when not to. Same path rule as everywhere else — never a bare path, and verify each one
resolves before writing it.

## Keeping it honest

- **A doc that drifts from its code is worse than no doc.** Update it in the same change that changes
  the behaviour.
- A doc for a package that doesn't exist yet is instant drift. Write it when the package appears.
- If a rule is stated in two places, one of them will go stale. Pick the home and link to it.
- Always-on cost is real: CLAUDE.md plus every skill `description:` loads on every session. Before
  adding to CLAUDE.md, check whether a module doc, a skill, or a command would carry it instead.
