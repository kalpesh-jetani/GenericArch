---
description: Rebuild the inventories the active stack profile declares in .claude/notes/ from a filesystem scan, and report the gaps it finds
argument-hint: "[optional: a note name, e.g. FONTS]"
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

```bash
./Scripts/ga-step.sh require sync-app-notes      # sequence gate
```

**Exit 5 means an earlier step has not run.** Say which one, and stop — never pass `--force`, and
never work around it. Order and why: [SEQUENCE.md](/docs/operations/SEQUENCE.md)(/docs/SEQUENCE.md).

Rebuild the living inventories in `.claude/notes/` from what is actually on disk.

Scope: `$ARGUMENTS` if a note is named, otherwise all of them.

> **This is a command, not a skill, and that is the safety mechanism.** A full rescan rewrites the
> files wholesale; run against a half-finished tree it replaces correct rows with incomplete ones —
> worse than a stale note, because it looks current. As a command it can only run when you type it,
> so there is no path by which it fires as a side effect of another task.
>
> **Targeted edits are the normal case and do not belong here.** Adding one row to `FEATURES.md`
> because you added one screen is part of that change (CLAUDE.md §3) — edit the file directly.

**Run the command as written; do not improvise a substitute.** Each `⚠` marks a constraint that a
naive rewrite breaks. The evidence behind them is in
[SCAN-TRAPS.md](/docs/operations/SCAN-TRAPS.md)(/docs/SCAN-TRAPS.md) — read it before changing a scan, not before running one.

---

## S0. Before rewriting anything

```bash
git status --porcelain=v1 && git branch --show-current
```

A dirty tree is the case this command's warning exists for. If it prints anything, say so and let
the user decide.

### Scan what moved, not everything

**Default scope is the stale set, not all of them.** Most syncs follow a change that touched two or
three areas; rescanning the other six spends tokens to rewrite files with identical content.

Set the source root first — every scan in this command uses it. In a greenfield repo it is
`Packages`; in an adopted one it is whatever the notes' `Built from:` lines name:

```bash
SRC=Packages          # adopted repo: e.g. SRC=App/MyApp
./Scripts/notes-staleness.sh "$SRC"
```

It prints one row per note — `current`, `STALE` with a count and sample, or `NEVER`. The spread is
the scope decision: on one repo a two-week baseline gave 88 changed files for `FEATURES` and 3 for
`ASSETS-IMAGES`.

It reads **git** timestamps, not mtime, and its baseline is each note's `- **Last synced:**` line —
which is why S5.3 requires you to set it. Why not mtime:
[SCAN-TRAPS.md](/docs/operations/SCAN-TRAPS.md)(/docs/SCAN-TRAPS.md).

`$ARGUMENTS` overrides the staleness result: a named note is scanned whether or not it is stale, and
if the user asks for everything, do everything. Report what you skipped either way.

```bash
ls -la .claude/notes/
```

Then **state what you are about to scan and what it will replace, and wait for confirmation.**
Typing the command asks for a sync; it does not pre-approve discarding work in progress. Lead with
the staleness table, then the sizes for the notes you intend to touch — `FEATURES: 88 changed files,
115 screens` is the useful form, not "the notes".

Use `AskUserQuestion` for the confirmation when scope is genuinely open (the stale set vs all of them);
plain text is enough when the user named a note in `$ARGUMENTS` or only one note is stale.

## S1. What each note is built from

The note SET — which inventories a project keeps, and how each is scanned — is the **active stack
profile's** to declare (`profiles/<name>/`): the file taxonomy of one stack means nothing to another.
This command hardcodes no scan; it drives the profile's, through `Scripts/sync-notes.sh`. With no
profile declared there is no note set, and nothing to rebuild.

## S1b. Run the offline pass FIRST — most of this is not your work

Before scanning anything by hand, run the offline engine. It regenerates every inventory the profile
can derive deterministically and gathers candidate evidence for the ones that need judgement, so you
review rows instead of re-running scans:

```bash
./Scripts/sync-notes.sh --check       # what has drifted (exit 1 on drift); no profile → nothing
./Scripts/sync-notes.sh --evidence    # candidates for the judgement notes
./Scripts/sync-notes.sh --apply       # rewrite the managed rows it can fully generate
```

Only the rows a scan cannot settle — the ones the profile marks as needing judgement — are yours to
work through. Reviewing a candidate list is a fraction of scanning from scratch.

## S2. The scans are the profile's

There are no built-in scans here: which files feed which inventory, and how, is declared by the
active profile and run by `sync-notes.sh`. When a profile is declared, add or refine a scan in the
profile, not in this command. With none declared, there is nothing to scan.

## S3. Paths are the point — emit them, verified

`FEATURES.md`, `NAVIGATION.md` and `API-MAP.md` are indexes: someone should `grep` a screen, a route
or an endpoint there and get the file. So every row carries a **repo-relative path**, and every
graph node carries a `click` target. Note→note links use the same repo-relative form.

Verify the whole set before you finish — a wrong path is worse than a missing one:

```bash
python3 Scripts/check-note-links.py
```

### The row format is dense on purpose

A grep hit returns the row's **bytes**. Link syntax, a repeated root prefix and a thrice-restated
filename are overhead for a lookup that never opens the file (measured: −21% overall, −47% on
`FEATURES.md`).

```
before (171)  | `HomeScreen` | [HomeScreen.ext](src/App/Home/HomeScreen.ext) | `loading`, `empty`, `error` |
after   (99)  | `HomeScreen` | src/App/Home/ | loading, empty, error |
```

Four transformations, in order:

1. **No markdown links in a row** — write the bare path. The link syntax duplicates the basename and
   serves a reader who, by §S6, never opens the file. Whoever *reports* a row renders the link.
2. **Declare the root once in the header**, then write paths relative to it:
   `- **Root:** \`src/App/\`` — a repeated root prefix appeared 175 times across one project's notes.
3. **Drop the filename when the key derives it.** State the convention in the header
   (`file = <dir>/<Key>`) and the row carries the directory. Only spell the filename when it
   does *not* follow from the key.
4. **Backticks on the searchable key only.** They earn their two bytes on the column people grep for
   and nowhere else.

Rows stay one line ending in `|` (§S6) — density must never come from wrapping.

Four rules, because a wrong or unexplained path is worse than a missing one:

1. **Never emit an *unexplained* path.** Every path needs a clause saying what is there — but the
   clause can be a neighbouring column (`Kind`, `States`), not necessarily prose. What is forbidden
   is a path a reader cannot act on without opening it, not a path without link syntax. In mermaid,
   the clause is the third `click` argument (the tooltip). In shell recipes, a `#` comment on the
   same line.
2. **Verify every path resolves** before writing it — the script above. If the file isn't there, the
   row goes in `Gaps`; never emit a guess.
3. **A `:line` suffix is optional and only for a definition site.** Never put line numbers in a
   generated table — they rot on the first insertion. Prose may carry one.
4. **Keep every `click` line in the mermaid block.** They are what make the diagram findable by
   `grep` — a diagram without them is a picture, not an index.

## S4. Findings are claims — verify them like paths

Rule S3.2 protects paths. **Findings need the same discipline and are easier to get wrong**, because
a negative claim ("never used", "no consumer", "missing") is the kind people act on destructively.

> **Before writing any negative finding, run the positive search for the thing you claim is absent,
> and say which search you ran.**

The package name is not the module name — nor is the target name, the product name, or the folder
name. Worked example: [SCAN-TRAPS.md](/docs/operations/SCAN-TRAPS.md)(/docs/SCAN-TRAPS.md).

## S5. Rules for every note

1. **Preserve structure and prose.** Replace table bodies only — the guidance in those files is
   hand-written and must survive a regeneration. Prefer `Edit` on the table body over `Write` on the
   file; reach for `Write` only when the whole body is generated, and re-read the header first.
2. **Delete the scaffold marker on the first successful sync.** The `> Empty until … —
   /sync-app-notes populates it.` line is scaffolding, not prose. Leaving it on a populated note
   makes the note lie about itself. Rule 1 does not protect it.
3. **Set `Last synced:` to today's actual date**, in every note you touched **and no others**. This
   is not bookkeeping — it is the baseline the next run's staleness check reads (S0). Stamping a
   note you did not rescan hides real drift; leaving one unstamped after a rescan makes the next run
   redo it.
4. **Keep commented-out example rows** while a table is empty; delete an example only when real rows
   replace it.
5. **Never drop a row silently.** A removed asset or route is a deletion — take it out in the same
   change that removes the code, so the diff shows both.
6. **Fill the `Gaps` table rather than omitting problems.** An inventory that hides a defect is worse
   than no inventory. Close each note with a **Not checked:** paragraph naming what the scan could
   not see.
7. **Group long tables by folder, with the count in the heading** (`### \`Images/Device/\` — 28
   assets`). Never truncate without saying so in the same sentence.
8. **A note whose `Built from:` source does not exist records the absence.** Do not synthesise. If
   a note's declared source does not exist, the note records the absence and lists what it found as
   evidence — a registry nothing references is worse than an empty one.
9. **Never edit CLAUDE.md.** If a scan suggests a rule, report it and let the user decide — CLAUDE.md
   is approval-gated ([STRUCTURE.md](/docs/reference/STRUCTURE.md)(/docs/STRUCTURE.md)).
10. Cross-check owners against the active profile's layering — a shared asset owned by a single
    feature is worth flagging.

## S6. A note is a grep index, never a document

**Notes are searched, never read.** That is the whole reason they exist
([PATTERN-SEARCH.md](/docs/patterns/PATTERN-SEARCH.md)(/docs/PATTERN-SEARCH.md)): one `grep` returns the row, the row answers the
question, and the file never enters context. A note read end-to-end has cost more than the search it
was built to replace.

Three rules follow, and they bind this command as much as daily work:

1. **Never promote a note to a skill.** Not at any size. A skill loads its whole body when it fires;
   a note is grepped for one line. Converting one trades a cheap search for an expensive read, and
   the `description:` then costs tokens in *every* session. Size is not a reason — a 28 KB note that
   is only ever grepped costs the same as a 3 KB one.
2. **Never read a note in full**, including here. Read the header for its `Built from:` line and its
   scaffold marker; everything below that is written, not consulted.
3. **Maintain by insertion and deletion of rows** — a row appears when the thing appears, a row goes
   when the thing goes, in the same change (CLAUDE.md §3). This command's wholesale rewrite is the
   **only** exception, and it is why the command is user-typed.

### What that demands of a row

If the file is never read, then **every row must answer the question on its own**. A row that sends
the reader to the file has failed.

- **One fact, one line.** A row that wraps is two grep hits, each meaningless alone.
- **Self-contained** — the name, the path, and the clause saying what is there (S3.1).
- **Greppable by the word someone would actually search**: the screen name, the route case, the
  token, the endpoint path.

Check it, rather than assuming it:

```bash
# rows that wrap — a soft-wrapped table row defeats grep
awk 'BEGIN{FS=""} /^\| / && !/\|$/ {print FILENAME":"NR": row does not end in |"}' .claude/notes/*.md

# does a real lookup return a usable line?
grep -h "HomeScreen" .claude/notes/*.md | head -3
```

Report the sizes for information, never as a trigger for restructuring:

```bash
wc -c .claude/notes/*.md | sort -rn
```

## S7. Gaps to flag, per note

What is worth flagging in each inventory is the **active stack profile's** to define — a colour note
flags different things than an endpoint note, and both are stack-specific. The offline pass
(`sync-notes.sh --evidence`) surfaces the candidates the profile knows to look for; verify each per
S4 before it becomes a row. With no profile declared there is nothing to flag.

## S8. Report

Say what changed — added, removed, gaps found — not "notes updated". If a scan found nothing (no
assets yet, no routes yet), say so explicitly and leave the scaffold intact.

**State every finding you corrected mid-scan, and why.** A run that silently shows only its final
numbers hides that the method was tuned until it agreed with them. Disclosing "the first unused-asset
pass said 52, the verified figure is 42, here is what the first pass missed" is what makes the other
rows worth trusting.

Close with the commands the user should run themselves (CLAUDE.md §2.8) — this command never
builds, tests, or compiles.

## S9. Header discipline — a note is read to be looked something up in

Every note is written to be **grepped, not read**. A header earns its lines only if a reader looking
something up needs them. Exactly four things qualify:

1. `# Title`, and one line on what this note owns — plus what the companion note owns instead
2. `**Read it when**` — the lookups this note answers
3. `- **Last synced:** <date>` and `- **Tree hash:** <the value stamped below>`
4. a scope rule, where one exists ("no feature builds a URL")

**Audit narrative does not.** Why a table was *not* regenerated, which scan pass was wrong, what a
re-parse produced, what the first pass missed — that belongs in the commit message and the S8 report.
It reads as diligence and costs every future reader who wanted one row. Seen in the wild: twelve
header lines justifying a decision not to rescan, in a file whose job is to answer "which screens
call this endpoint?".

If the header runs past roughly eight lines, something in it is narrative.

Stamp the tree hash so the next run can tell staleness without re-reading every inventory:

```bash
./Scripts/notes-staleness.sh --stamp
```

## S10. Seal and record

```bash
./Scripts/sync-notes.sh --check       # must exit 0: the mechanical notes match the tree
./Scripts/ga-reseal.sh --apply
./Scripts/ga-step.sh record sync-app-notes "<which notes changed>"
./Scripts/ga-step.sh record ready
```

`ready` is what unblocks the skills and the day-to-day commands. Record it only when the inventories
actually reflect the tree — that is the whole value everything downstream is trusting.
