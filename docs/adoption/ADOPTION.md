# Adopting into an existing codebase

How to reconcile this architecture with a repo that already has its own rules. `/project-init`
detects an existing repo and follows this; it is written out here rather than in the command so a
fresh-repo run does not load it.

- **When to read this:** adopting the base into a codebase that already exists, or reviewing how a
  past adoption resolved a conflict.
- **Getting the files there first:** [SHARING.md](/docs/adoption/SHARING.md)(/docs/adoption/SHARING.md) · `Scripts/adopt.sh` · `install.sh`.

---

## The governing principle

**It is their repo and their rules. This blueprint yields unless the user says otherwise.**

An existing `CLAUDE.md` reflects decisions made with context you don't have, and a codebase that
already violates one of these rules at scale cannot adopt it by editing a doc. Your job here is to
surface conflicts and let the user choose — not to install a better architecture over theirs.

## A1. Inventory what exists

Read their root `CLAUDE.md` **in full**, plus every nested one. Note for each:

- Rules that **conflict** with something in this structure.
- Rules they have that this structure **lacks** — these are candidates to keep verbatim, and often
  the most valuable thing in the repo.
- Always-on size. If their `CLAUDE.md` is large, the §3 four-way split is worth *offering* as a
  separate follow-up — never as part of adoption.

Then inventory `.claude/skills/` and `.claude/commands/`: name, description, and what each triggers on.

## A2. Build the conflict table — show it before asking

One row per real conflict. Do not pad it with cosmetic differences.

| Their convention | The active profile's rule it contradicts | Conflict type |
|---|---|---|
| *(one row per real conflict)* | *(the profile rule)* | Hard · Migration · Convention · Structural · Soft |

A conflict exists only where a **declared** profile's rule contradicts a convention the target
already follows — the layer itself imposes nothing, so with no profile declared this table is empty.
Classify each real conflict by cost: a mutually-exclusive build system is **Hard**; a call-site
migration is **Migration**; a naming rule is **Convention**; a layering change is **Structural**; a
new-code-only rule that can coexist is **Soft**.

Classify honestly. Calling a migration "soft" so adoption looks easy is the failure mode here.

## A3. Ask per conflict — four options, every time

For each row, offer:

1. **Keep theirs** *(default, and recommend it unless they've said they want to migrate)* — this
   structure's rule is dropped, and the rule stays out of their CLAUDE.md.
2. **Adopt for new code only** — their existing code is grandfathered. **Usually the right answer
   for a `Hard`/`Migration` row**, because it's the only option that is honest about existing code.
   Requires stating where the boundary is: which directories, from which date.
3. **Adopt fully, with a migration** — only if they'll commit to the work. Say roughly what it
   costs (how many call sites, from a grep) before they choose.
4. **Skip / decide later** — record it in DECISIONS.md *Open* so it isn't silently dropped.

Batch these with `AskUserQuestion`. **Every CLAUDE.md write needs its own explicit approval**, shown
as exact text before it is applied — the conflict resolution is not that approval
([STRUCTURE.md](/docs/reference/STRUCTURE.md)(/docs/reference/STRUCTURE.md)). When approved, add rules only: never rewrite their prose,
never renumber their sections, never add meta notes about the docs.

## A4. Name collisions — check before installing

A skill or command whose name already exists would shadow or duplicate theirs.

For each of ours — the `tool-profile` skill and every command under `.claude/commands/` — check for
an existing file or directory of that name.

On a collision, ask: **keep theirs** · **install ours under a prefixed name** (`ga-build`) ·
**merge the two** · **skip ours**. Do not overwrite. Also flag *description* overlap without a name
clash — two skills triggering on the same phrases means neither fires predictably.

## A5. Install additively, only what's missing and approved

- **Create only what does not exist.** Never overwrite a file they wrote.
- a module doc only for a package they actually have — never the full set. A doc for a package that
  doesn't exist is instant drift.
- `.claude/notes/*` scaffolds are safe to add (they're new inventories) — but do **not** run
  `sync-app-notes` yet; that's Step S3, and only with approval.
- Their `.claude/settings.json`: **merge**, never replace. Show the diff of added permissions.
- Skip anything whose conflict was resolved as "keep theirs".

## A6. Record every override

One `/decide` row per resolution, in both directions:

- A blueprint rule dropped → *Do not re-propose*, so nobody re-suggests it next month.
- A blueprint rule adopted → *Settled*, with the boundary if it's "new code only".
- Anything deferred → *Open*, with what it blocks.

An override that isn't recorded gets re-litigated, which is worse than never having asked.

**This is now enforced, not merely required.** `/project-init` S5 lists every conflict from
`INIT-CONFLICTS.tsv` that has no row in `DECISIONS.md` and refuses to record the step until each
one does. The failure it closes was observed on a real adoption: the profile's rules had been declined, the
resolution lived only in that session's transcript, and the next run asked again — forever
([DECISIONS.md](/docs/decisions/DECISIONS.md)(/docs/decisions/DECISIONS.md), *Recording a resolution*).

**"Keep theirs" is a resolution.** It is the one most often left unrecorded, because nothing
changed on disk — and it is exactly the one that gets re-litigated.

---
