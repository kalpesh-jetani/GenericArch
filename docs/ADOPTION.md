# Adopting into an existing codebase

How to reconcile this architecture with a repo that already has its own rules. `/project-init`
detects an existing repo and follows this; it is written out here rather than in the command so a
fresh-repo run does not load it.

- **When to read this:** adopting the base into a codebase that already exists, or reviewing how a
  past adoption resolved a conflict.
- **Getting the files there first:** [SHARING.md](SHARING.md) · `Scripts/adopt.sh` · `install.sh`.

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
- Always-on size. If their `CLAUDE.md` is large, the §5 four-way split is worth *offering* as a
  separate follow-up — never as part of adoption.

Then inventory `.claude/skills/` and `.claude/commands/`: name, description, and what each triggers on.

## A2. Build the conflict table — show it before asking

One row per real conflict. Do not pad it with cosmetic differences.

| Their rule | This structure | Conflict type |
|---|---|---|
| CocoaPods / Carthage | SPM only (§1) | **Hard** — mutually exclusive |
| Tuist / XcodeGen | SPM-generated (§1, REPO.md) | **Hard** |
| UIKit / storyboards | SwiftUI only (§1) | **Hard** at scale — existing screens can't be converted by a rule |
| Combine / completion handlers | async/await only (§1, §6) | **Hard** for existing code, adoptable for new |
| `.alert` used directly | one `MessagePresenting` (§2.4) | **Migration** — every call site |
| Hardcoded or differently-keyed strings | `<feature>_<screen>_<element>_<role>` (§2.3) | **Convention** — renaming shipped keys breaks translators |
| Swinject / Factory / other DI | own typed registry (DIKit) | **Hard** — DI is pervasive |
| Different min iOS / macOS | whatever `Package.swift` declares (§1.1) | **Hard** — changes what compiles |
| VIPER / Clean / MVC / MVVM-C | MVVM + `@Observable`, layered (§0, §3) | **Structural** |
| XCTest throughout | Swift Testing for new (§9) | **Soft** — both can coexist |
| Multi-repo or different layout | single repo + two extracted (§4) | **Structural** |

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
([STRUCTURE.md](STRUCTURE.md)). When approved, add rules only: never rewrite their prose,
never renumber their sections, never add meta notes about the docs.

## A4. Name collisions — check before installing

A skill or command whose name already exists would shadow or duplicate theirs.

For each of ours — skills `new-feature`, `release-bump`, `dark-light-mode`, `rtl-support`; commands
`build`, `verify`, `decide`, `gaps`, `project-init`, `upgrade-stack`, `sync-app-notes` — check for an
existing file or directory of that name.

On a collision, ask: **keep theirs** · **install ours under a prefixed name** (`ga-build`) ·
**merge the two** · **skip ours**. Do not overwrite. Also flag *description* overlap without a name
clash — two skills triggering on the same phrases means neither fires predictably.

## A5. Install additively, only what's missing and approved

- **Create only what does not exist.** Never overwrite a file they wrote.
- `docs/modules/*.md` for packages they actually have — not the full set. A doc for a package that
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

---
