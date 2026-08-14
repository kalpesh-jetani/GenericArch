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

# Path A — Existing repo

**Read [ADOPTION.md](../../docs/ADOPTION.md) and follow it.** It carries the whole reconciliation
procedure: the governing principle that their rules win by default, the conflict table, the four
options per conflict, the name-collision check, additive installation, and recording every override.

It lives there rather than here so a fresh-repo run does not load a procedure it will never use.

**Do not improvise a shortened version of it.** Adoption goes wrong quietly — a rule adopted without
being offered, or a file overwritten because a collision was not checked — and the detail is the
safeguard.

# Path B — Fresh repo: establish the base rules

## B1. Show what this repo already gives them

Present this before asking for anything — the answers change once they know what's on offer.

**Skills** — Claude applies these on its own when the situation matches:

| Skill | Fires when |
|---|---|
| `new-feature` | Adding a feature or screen — enforces the §0 asks and every content state |
| `debug` | Something is broken, blank, or silently wrong |

Only two ship, on purpose: a skill costs its description every session, and one that cannot fire in
an empty repo costs it for nothing. Six more are written and waiting in `docs/patterns/` — change,
style-guide, dark-light-mode, rtl-support, release-bump, feature-complete. Each becomes a skill
via `/learn <name>` once the code it describes exists.

**Commands** — only run when the user types them: `/build` · `/verify` · `/review` · `/decide` ·
`/gaps` · `/learn` · `/project-init` · `/upgrade-stack` · `/sync-app-notes`.

Then ask which they want kept. A skill they'll never use is always-on description cost for nothing.

Confirm the list against what is actually installed rather than reciting this table — it is a
description, and the filesystem is the fact:

```bash
ls .claude/skills .claude/commands
awk -F'\t' '$2=="pattern"{print $1}' .claude/MAP.tsv
```

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

## S0. Deduplicate rules across the four levels

A rule stated at two levels drifts, and the copy that goes stale is the one nobody is reading. Audit
before adding anything, because adoption is when duplicates get created.

```bash
ls .claude-plugin dist/*/. claude-plugin 2>/dev/null          # 1 plugin
find . -name CLAUDE.md -not -path '*/.git/*'; ls docs .claude/skills .claude/commands 2>/dev/null
ls ~/.claude/CLAUDE.md ~/.claude/projects/*/memory/*.md 2>/dev/null   # 3 user
ls "/Library/Application Support/ClaudeCode/managed-settings.json" 2>/dev/null  # 4 enterprise
```

**Keep the most specific copy; remove the broader duplicates, working inward** — Enterprise, then
User-Level, then project, then Plugin. The most specific copy is the one that ships with the thing
the rule governs, so it stays.

| Level | Reach | On a duplicate |
|---|---|---|
| Enterprise | every repo, every user | **Read-only — never touch it.** If it duplicates a lower rule, remove the lower one instead |
| User-Level | this user | Remove — the project or plugin copy already covers it |
| project | everyone who clones the repo | Keep, unless a plugin ships the same rule |
| Plugin | every repo that installs it | Keep for tooling rules; a product rule does not belong here |

Two cautions:

- **A project-scoped memory directory adds no reach over the repo itself.** If a rule sits in both
  `~/.claude/projects/<this>/memory/` and `CLAUDE.md`, the memory copy is pure duplication — drop it.
- **Check the copy you are keeping carries the reasoning**, not just the sentence. Deleting the
  fuller statement and keeping a one-line restatement loses the *why*, which is what stops the rule
  being argued again.

Report what was removed and from where. Removing a rule from `CLAUDE.md` still needs its own
approval ([STRUCTURE.md](../../docs/STRUCTURE.md)).

## S0b. Point the target's CLAUDE.md at the manifest

If `genericarch.installation.md` exists, the reference docs are **fetched on demand** — the skills
link to paths that are not on disk yet. Nothing tells the target's own CLAUDE.md that.

Propose adding these two lines, and **wait for approval** — it is still a CLAUDE.md edit
([STRUCTURE.md](../../docs/STRUCTURE.md)):

```markdown
Grep `.claude/MAP.tsv` to find any doc, note, skill or pattern. Architecture reference is fetched
on demand — a `docs/…` path that is not on disk is a fetch instruction, not a broken link; the
map's `# FETCH-BASE:` line says where to get it, and `genericarch.installation.md` is the full
index.
```

Without it, the first unresolved link reads as a missing file and the doc gets reinvented from
scratch — which is worse than not installing at all.

## S0c. Every routable path must resolve — installed, or fetchable

The map is what Claude greps to find anything. A row it cannot resolve is worse than a missing
row: it reads as "this exists here", and when the file isn't there the content gets invented.

Two classes, and they fail differently:

| Class | Must be | Why it cannot be fetched |
|---|---|---|
| `.claude/skills`, `.claude/commands`, `.claude/MAP.tsv`, `.claude/notes`, `.claude/memory`, `Scripts/` | **on disk** | Claude Code discovers skills and commands from the filesystem; a fetched skill never fires, and a map you must fetch first cannot route you to itself |
| everything under `docs/` | **on disk *or* fetchable** | Reference material — fetched when a task actually needs it |

Run this. It is read-only.

```bash
cd "$(git rev-parse --show-toplevel)"
for f in .claude/MAP.tsv .claude/INDEX.md .claude/memory/INDEX.md \
         Scripts/check.sh Scripts/find.sh Scripts/scan-api-map.py \
         Scripts/notes-staleness.sh Scripts/scan-colors.py \
         Scripts/scan-unused-assets.py Scripts/scan-fonts.py; do
  [ -e "$f" ] || echo "MISSING-LOCAL  $f"
done
[ -d .claude/skills ]   || echo "MISSING-LOCAL  .claude/skills"
[ -d .claude/commands ] || echo "MISSING-LOCAL  .claude/commands"
[ -d .claude/notes ]    || echo "MISSING-LOCAL  .claude/notes"

base=$(awk -F'\t' '/^# FETCH-BASE:/{print $2; exit}' .claude/MAP.tsv)
awk -F'\t' '!/^#/ && NF>1 {print $1}' .claude/MAP.tsv | while read -r p; do
  [ -e "$p" ] && continue
  [ -n "$base" ] && echo "FETCHABLE      $p" || echo "UNRESOLVABLE   $p"
done | sort | uniq -c | sort -rn
echo "FETCH-BASE: ${base:-<none — every missing row is unresolvable>}"

# A row that is not exactly 4 tab-separated columns is dropped by every awk/grep
# recipe that reads this file — silently, with no error anywhere.
awk -F'\t' 'NF!=4 && $0 !~ /^#/ && NF>0 {print "MALFORMED-ROW  line "NR": "NF" columns"}' .claude/MAP.tsv

# Every note the map advertises must exist, or the row routes into a void.
awk -F'\t' '$2=="note" {print $1}' .claude/MAP.tsv | while read -r n; do
  [ -f "$n" ] || echo "MISSING-NOTE   $n"
done
```

Then act on what it printed:

- **`MISSING-LOCAL`** — the install was partial. Re-run `install.sh --apply`, or copy the named
  paths from the source repo. Do not proceed; a missing skill is silently absent, not an error.
- **`UNRESOLVABLE`** — the map points at docs that are neither present nor fetchable, because no
  `# FETCH-BASE:` line was stamped. Add one as the first line of `.claude/MAP.tsv`, taking the URL
  from **`genericarch.installation.md`** (its *Pinned to* commit — use that exact ref, never
  `main`, or the docs will drift out from under the install):

  ```
  # FETCH-BASE:	https://raw.githubusercontent.com/<owner>/GenericArch/<pinned-sha>
  ```

- **`FETCHABLE`** — correct and expected. Nothing to do; those rows resolve when a task needs them.

**Report the counts to the user** rather than fixing silently — how many resolve locally, how many
are fetch-on-demand, and how many cannot be reached at all. The last number must be zero before
`/project-init` reports success.

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

**Ask which packages this product needs.** Default to Core + Navigation; add others only if the
product will use them. Packages with no consumer are instant drift.

| Package | Add when | Skip if |
|---|---|---|
| Core | Always | Never |
| DIKit | Any dependency injection in features | Trivial app, no features yet |
| DesignSystem | Any multi-screen UI | Web app, headless service |
| Navigation | Any multi-screen routing | Single-screen app |
| StorageKit | Any persistence (local or encrypted) | Read-only, no user data |
| LocalizationKit | Any user-facing string OR any language beyond English | Monolingual, hardcoded |
| LoggingKit | Any production logging or analytics | Debug-only logging |
| NotificationKit | Push notifications OR local notifications | No notifications |
| Messaging | Any system alert, sheet, or message surface | Direct UI, no popups |

**Explicitly do NOT ask about:**
- Wrappers/ (added as vendors require it)
- Features/ (added per `/new-feature`)
- The two extracted repos NetworkKit + ImageCache (separate repos; reuse test in §4.2)

Then scaffold:

1. `.gitignore` and `.claude/settings.json` — exactly the consented entries, merged not replaced.
2. **`Packages/Core` first** — zero dependencies, nothing compiles without it.
   a `platforms:` line copied from a sibling package, or from `./Scripts/detect-toolchain.sh`
   in a repo that has none yet.
3. Then the approved packages in §3's layering order.
4. The `.xcodeproj` shell with four configurations and their `.xcconfig` files, using the answered
   bundle ID and Team ID.
5. **Not** the two extracted repos — they're separate repositories and fail the "actually reused"
   test until a second product exists (CLAUDE.md §4.2).

## S2b. Install only skills that improve code generation and review

**Filter by Claude performance, not by product features.** Only install skills that help Claude
write or review code better. Remove deployment/workflow tools.

| Skill | Improves | Install if |
|---|---|---|
| `new-feature` | Code generation — scaffolds feature structure correctly | Always (adding features to this product) |
| `dark-light-mode` | Code generation — generates color/asset code that respects dark mode | Dark mode is shipped or planned |
| `rtl-support` | Code generation — generates layouts that work RTL | Any RTL language (ar, he, fa, ur) shipped or planned |
| `style-guide` | Code generation — uses design tokens instead of literals | DesignSystem package was approved in S2 |

**Explicitly remove** (not about code generation or review):
- `release-bump` — this is a CI/release workflow tool, not code generation. Remove unless the product
  is itself the extracted NetworkKit/ImageCache repos (rare).

**Do not install irrelevant module docs** — delete `docs/modules/<Package>.md` if the package was
not approved in S2. A doc for a package that doesn't exist is instant drift.

Record skill decisions in `DECISIONS.md` *Do not re-propose* section — if a skill is removed, note
why it was dropped so it doesn't get re-proposed next month.

## S3. Populate the notes

**Check if there's code to scan.** If scaffolding just created empty `Packages/`, offer
`/sync-app-notes` **only** when the user is ready to add the first feature or asset:

> "Once you add features to `Packages/Features/` or image/color assets to the catalog, run
> `/sync-app-notes` to populate the inventories. That command rewrites 9 files; it's best run
> once after you have real content."

**Do not run it here.** It is the user's command, and initialisation is not blanket consent to
rewrite nine files. Running it on empty `Packages/` produces scaffold-only inventories that look
current but are mostly blank.

**If the project already has code** (e.g. adopting into an existing codebase), ask:

> "The project already has code. Run `/sync-app-notes` now to inventory features, screens, routes,
> assets, and build config? (~X tokens, creates 9 `.claude/notes/*.md` files.)"

Then fill by hand what no scan can know: the marketing version in `Base.xcconfig`, signing rows in
[SCHEMES.md](../notes/SCHEMES.md), Team ID in [PROJECT.md](../notes/PROJECT.md).

**Link every note back to CLAUDE.md.** Each inventory should cite the relevant section so Claude
can find the authoritative rules: "Grep .claude/MAP.tsv for the module doc" or "See CLAUDE.md §2.3
on localization keys" or "See CLAUDE.md §8 on accessibility."

## S3b. Establish the pattern-search pattern

**The `.claude/notes/` files are your searchable index.** Claude does *not* load them automatically —
it finds them by grepping `.claude/MAP.tsv`, then reads only the one it needs, on every
turn — they live in context. Teach Claude to search them first before calling grep:

**Pattern recording:**
1. When Claude adds a feature, screen, route, component, or asset, the `.claude/notes/` row goes in the
   **same change** as the code (not a separate rescan).
2. Each row is complete: name · file path · description · status. Paths must be exact and verified.
3. Back-link to CLAUDE.md: "See CLAUDE.md §2.1 — features never import each other" or "See CLAUDE.md
   §8 on accessibility for every interactive element ≥44×44pt."

**Token-efficient workflow:**
1. **Search the notes first** — "Is FooFeature in FEATURES.md? Does NAVIGATION.md list the FooScreen
   route?"
2. **If found in notes**, use the path and description directly. Zero grep.
3. **If NOT found**, fall back to `grep`, then record the pattern in the relevant note.
4. **Over time**, the notes become more complete and reduce token spend per session.

**On every session:**
- Claude finds `.claude/notes/` by grepping `.claude/MAP.tsv` — one grep, then one targeted read
- First lookup: "Is this screen in FEATURES.md or NAVIGATION.md?"
- No grep unless the notes gap forces it
- New discoveries update the notes in the same commit as the code

This pattern applies to **all skills** — they should use notes as their source-of-truth before
falling back to grep.

## S2c. Clean up irrelevant docs

**Delete module docs for packages that were not approved.** The `local` commit ships all 12
`docs/modules/*.md` files; if StorageKit, LocalizationKit, or NotificationKit were not approved in
S2, delete their docs now.

```
rm -f docs/modules/<NotApprovedPackage>.md
```

A doc for a package that doesn't exist is instant drift — it reads as current, but describes code
that isn't there. Cleaner to delete it than to leave it with a "not used here" note.

Approved packages keep their docs; a feature will eventually need the infrastructure described
there, and when it does, the doc is immediately discoverable.

## S4. Report

State explicitly:

- What was created, and what was **left untouched** because it already existed.
- **Packages approved and packages skipped** — record in DECISIONS.md *Open* what "no StorageKit yet"
  blocks (e.g. "Blocks when user data persistence is added").
- **Skills installed and skills removed** — record removals in DECISIONS.md *Do not re-propose*.
- Every rule conflict (Path A only) and how it was resolved — including the ones resolved as "keep theirs".
- **What was skipped, and which unanswered question blocks it.**
- What was recorded in [DECISIONS.md](../../docs/DECISIONS.md), and what remains *Open*.

A report that reads as complete when a question went unanswered, or that omits a skill you removed,
or a package you didn't ask about, is the failure mode of this whole command.
