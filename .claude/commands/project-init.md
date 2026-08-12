---
description: Initialize or adopt GenericArch in a repo — detects whether the repo is fresh or already has its own CLAUDE.md, skills, or source; reconciles conflicting rules with explicit approval before changing anything; then scaffolds only what is missing and approved
argument-hint: [optional: product name]
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, AskUserQuestion
---

Initialize this project, or adopt this structure into an existing one.

**This command's whole discipline is asking, not assuming.** Nothing is created, overwritten, or
overridden without an explicit yes.

> Named `/project-init`, not `/init` — Claude Code's built-in `/init` generates CLAUDE.md and would
> shadow a custom command with that name. The built-in does **not** run this.

---

## Step 0 — Detect the mode before asking anything

Scan first, then branch. Do not write anything in this step.

```bash
ls -la; git log --oneline -5 2>/dev/null | head
find . -name "CLAUDE.md" -not -path "*/.git/*"          # root AND nested
ls .claude/skills .claude/commands 2>/dev/null
cat .claude/settings.json 2>/dev/null
find . -name "Package.swift" -o -name "*.xcodeproj" -o -name "Podfile" \
       -o -name "Project.swift" -o -name "project.yml" | head -20
./Scripts/detect-toolchain.sh 2>/dev/null || true
```

**The stack is acquired, never assumed or copied.** Precedence: the **project wins** (its settings
are the shipped contract), the **machine** fills the gaps, and whatever neither answers gets
**asked** — see S1a.

Never carry GenericArch's numbers or framework choices into another repo.

**If the detector reports a BLOCKING mismatch — a deployment target above the installed SDK, or a
language mode the compiler cannot provide — raise it before anything else and stop.** That build
cannot succeed as configured, and adopting docs onto a repo that doesn't build wastes the session.
Hand off to `/upgrade-stack`, which asks twice before changing any project setting. Do not fix it
inline here: initialisation and mutating someone's build settings are different acts with different
consent.

| Signal | Mode |
|---|---|
| A `CLAUDE.md`, `.claude/skills/`, `.claude/commands/`, or real source exists | **Path A — existing repo** |
| Empty, or docs only, or a single commit | **Path B — fresh repo** |

**Report what you found before proceeding**, and if it's ambiguous — a `CLAUDE.md` but no code, or
code but no `CLAUDE.md` — say which path you're taking and why, and let the user redirect.

---

# Path A — Existing repo: reconcile before you touch anything

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
| Different min iOS / macOS | iOS 17 / macOS 26.6 (§1) | **Hard** — changes what compiles |
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
([STRUCTURE.md](../../docs/STRUCTURE.md)). When approved, add rules only: never rewrite their prose,
never renumber their sections, never add meta notes about the docs.

## A4. Name collisions — check before installing

A skill or command whose name already exists would shadow or duplicate theirs.

For each of ours — skills `new-feature`, `release-bump`, `sync-app-notes`, `dark-light-mode`,
`rtl-support`; commands `build`, `verify`, `decide`, `project-init` — check for an existing file or
directory of that name.

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

# Path B — Fresh repo: establish the base rules

## B1. Show what this repo already gives them

Present this before asking for anything — the answers change once they know what's on offer.

**Skills** — Claude applies these on its own when the situation matches:

| Skill | Fires when |
|---|---|
| `new-feature` | Adding a feature or screen — enforces the §0 asks and every content state |
| `dark-light-mode` | Adding a color/asset, or "this looks wrong in dark" |
| `rtl-support` | Adding a language, or auditing layout mirroring |
| `release-bump` | Releasing one of the two extracted packages |
| `sync-app-notes` | Full inventory rescan — **approval-only, never automatic** |

**Commands** — only run when the user types them: `/build` · `/verify` · `/decide` ·
`/project-init`.

Then ask which they want kept. A skill they'll never use is always-on description cost for nothing.

## B2. Ask for their rules — and separate the two kinds

These are different things, and conflating them is why rule lists decay:

| Kind | Meaning | Lands in |
|---|---|---|
| **Hard rules** | Never broken. A violation blocks the change | CLAUDE.md §2 — **approval-gated** |
| **Base rules** | Defaults. Overridable with a stated reason | the relevant `docs/` file |

Ask for each, and for every proposed **hard** rule ask one more question: **how would we know it was
broken?** A hard rule that can't be checked by grep, a test, or a build failure is a base rule
wearing a costume — it will decay within a sprint. Say that plainly; §2's existing eleven are all
checkable, which is why they hold ([DONE.md](../../docs/DONE.md),
[DELIVERY.md](../../docs/DELIVERY.md) enforcement table).

Offer this structure's §2 rules as a starting set, individually declinable — not as a package.

Writing the agreed hard rules into CLAUDE.md is itself an **approval-gated** step: show the final
section as exact text and wait for a yes before writing it ([STRUCTURE.md](../../docs/STRUCTURE.md)).

## B3. Ask the scope of each rule — project or directory

Claude Code loads a nested `CLAUDE.md` when files in that directory are touched. That makes scope a
real choice, not a formality:

| Scope | File | Use for |
|---|---|---|
| **Project** | root `CLAUDE.md` | Rules that apply everywhere. Always-on cost for every session |
| **Directory** | `Packages/<Name>/CLAUDE.md` | Rules only true inside that package — loaded only when it's touched |

Directory-level is the right home for anything package-specific, and it keeps the root file small
(§5). Two worked examples to offer:

- `Packages/Features/CLAUDE.md` — "no `#if DEBUG`", "no `resolve` outside `DI/`", "no sibling
  feature import". These are only meaningful inside a feature.
- `Packages/DesignSystem/CLAUDE.md` — "`#if os(...)` is allowed here and nowhere else".

Skills and commands can be directory-scoped the same way. Ask whether any should be.

---

# Shared — both paths continue here

## S1a. Resolve the stack — detect first, ask only the remainder

```bash
./Scripts/detect-toolchain.sh              # what the project and machine already answer
./Scripts/detect-toolchain.sh --options    # the valid choices, derived from this machine
```

**Ask only the rows the detector reports `unresolved`.** Re-asking something the project already
answers is how an adoption starts overwriting decisions it was told to respect.

| Ask | Options come from | Recommend |
|---|---|---|
| UI framework | SwiftUI · UIKit/AppKit · mixed | SwiftUI — the module docs assume it |
| Dependencies | SPM · CocoaPods · Carthage | SPM |
| Project files | SPM only · Tuist · XcodeGen · checked-in `.xcodeproj` | SPM only |
| Concurrency | async/await strict · async/await minimal · Combine · completion handlers | async/await strict |
| Swift language mode | **whatever the compiler accepts** — the script probes, never guesses | the latest available |
| Testing | Swift Testing · XCTest · both | Swift Testing; XCTest for UI |
| Platforms | **the SDKs actually installed** | the ones the product ships |

Two rules for this round:

- **Recommend the latest the machine supports, don't impose it.** A team on Swift 5 mode with a
  large codebase has a reason; ask for it rather than assuming a migration.
- **Say what a divergent choice invalidates.** UIKit means [DesignSystem.md](../../docs/modules/DesignSystem.md)
  and the `dark-light-mode`/`rtl-support` skills no longer fit as written. Combine means §6 does not
  apply. Naming that up front is the difference between an informed choice and a broken adoption.

Record every answer with `/decide`, then propose the §1 table from `--markdown` — **and wait for
approval before writing it to CLAUDE.md** ([STRUCTURE.md](../../docs/STRUCTURE.md)).

## S1b. Ask what cannot be inferred at all

Batch in one round, with a recommendation each. Skip anything Path A already established.

**Identity** — product name (`$ARGUMENTS` if given) · bundle ID prefix (`com.<org>.<product>`) ·
Apple Team ID. Note when asking: the bundle ID appears in four `.xcconfig` files with per-stage
suffixes ([SCHEMES.md](../notes/SCHEMES.md)); renaming later means re-provisioning. **Never
fabricate a Team ID.**

**Languages at v1** — base language *and* the full set. Highest-cost deferral in the list: §2.3
requires localization from day one, so adding a language later means auditing every catalog instead
of filling one column. If any is RTL (ar, he, fa, ur), say that `/rtl-support` applies from the first
screen.

**Open decisions** — read [DECISIONS.md](../../docs/DECISIONS.md) *Open* and offer each: the
iOS 17 / macOS 26 visual language, and confirming the macOS 26.6 minimum (it excludes every Mac that
can't run macOS 26 — [GAPS.md](../../docs/GAPS.md) E1). Do **not** ask the §0 per-feature questions
here; those belong to `/new-feature`.

**Permissions** — ask whether to create or merge `.claude/settings.json`, approving each group
separately. Never write a permission the user didn't name.

| Group | Contains | Note |
|---|---|---|
| Swift build/test | `swift build`, `swift test`, `swift package resolve` | Low risk |
| Xcode | `xcodebuild` build/test/archive | Slow; archive can touch signing |
| Read-only git | `status`, `diff`, `log`, `show` | Low risk |
| Mutating git | `add`, `commit`, `push` | **Ask separately** — never bundle with read-only |

`swift package edit` is deliberately excluded: it changes what a build resolves, so it stays visible.

**`.gitignore`** — ask, and show the contents first: `.build/`, `.swiftpm/`, `DerivedData/`,
`*.xcuserdatad`, `xcuserdata/`, `.DS_Store`. **Never** add `Package.resolved` — it is committed and
is the record of what ships ([REPO.md](../../docs/REPO.md)).

## S2. Scaffold only what was approved

1. `.gitignore` and `.claude/settings.json` — exactly the consented entries, merged not replaced.
2. **`Packages/Core` first** — zero dependencies, nothing compiles without it.
   `platforms: [.iOS(.v17), .macOS("26.6")]`.
3. Then `DIKit`, `LocalizationKit`, `LoggingKit`, `DesignSystem`, `Navigation`, in the order §3's
   layering implies. **Don't create a package with no consumer** — add each when something needs it
   ([REPO.md](../../docs/REPO.md)).
4. The `.xcodeproj` shell with four configurations and their `.xcconfig` files, using the answered
   bundle ID and Team ID.
5. **Not** the two extracted repos — they're separate repositories and fail the "actually reused"
   test until a second product exists (CLAUDE.md §4.2).

## S3. Populate the notes

Once there's code to scan, run `sync-app-notes`. The approval it requires is satisfied by the user
having asked for this command — but **state what you're about to scan first**, and populate rather
than rewrite: the prose in each note is hand-written and must survive.

Then fill by hand what no scan can know: the marketing version in `Base.xcconfig`, signing rows in
[SCHEMES.md](../notes/SCHEMES.md), Team ID in [PROJECT.md](../notes/PROJECT.md).

## S4. Report

State explicitly:

- What was created, and what was **left untouched** because it already existed.
- Every rule conflict and how it was resolved — including the ones resolved as "keep theirs".
- **What was skipped, and which unanswered question blocks it.**
- What was recorded in [DECISIONS.md](../../docs/DECISIONS.md), and what remains *Open*.

A report that reads as complete when a question went unanswered, or that omits a rule you dropped,
is the failure mode of this whole command.
