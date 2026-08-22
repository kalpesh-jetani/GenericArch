---
description: Apply the removals /project-init only reported — retire declined GenericArch files and duplicated memory rows through ga-remove.sh, asking per candidate
argument-hint: "[optional: a path, or `memory` | `docs` | `skills` to scope it]"
allowed-tools: Read, Edit, Grep, Glob, Bash, AskUserQuestion
---

```bash
./Scripts/ga-step.sh show      # project-init must already have run — it produces the candidate list
```

**If `project-init` is still `pending`, stop and say so.** This command applies decisions that
command reports; run out of order it is guessing at what the product declined. It is deliberately
**not** a lifecycle step — nothing waits behind it, and a repo that never needs it never runs it.

Retire what this product does not use: declined GenericArch files, and rule copies duplicated across
the four levels.

Scope: `$ARGUMENTS` if given — a path, or `memory` · `docs` · `skills` to take one class at a time.
Otherwise every candidate `/project-init` reported.

---

## Why this is its own command

`/project-init` removes nothing, on purpose. A removal is **four coupled writes**, and only the first
is the file itself:

1. the file moves to `.genericarch/safetodelete/<path>` — nothing is destroyed
2. a tombstone lands, so the next `install.sh` does not re-create it
3. its rows are pruned from `.claude/MAP.tsv` and `.claude/SCRIPTS.tsv`
4. a `DECISIONS.md` *Do not re-propose* row records the reason

Step 3 is the one that makes this dangerous to interleave: **pruning a path strips it out of the
index and memory directories every later lookup depends on.** Do that in the middle of rule
reconciliation and the run becomes impossible to review, and impossible to undo cleanly if a
conflict answer changes. Separating it also means the token cost is paid once, deliberately, instead
of on every adoption run.

**`./Scripts/ga-remove.sh` is the only way to delete an installed file** (CLAUDE.md §2.15). Never
`rm`. A file deleted by hand carries no record saying it was declined, so the next install cannot
tell it from a file that was never there — that flip happened four times in one adoption.

---

## 1. Rebuild the candidate list from disk

Never work from memory of what `/project-init` said — re-derive it, because the repo may have moved.
**One script does the whole derivation.** It is read-only, offline, and decides nothing:

```bash
./Scripts/ga-cleanup-scan.sh                 # every class, with the evidence per row
./Scripts/ga-cleanup-scan.sh --memory        # one class at a time: --memory --docs --skills --index
./Scripts/ga-cleanup-scan.sh --tsv           # machine-readable, for piping
```

Every row is `CANDIDATE` or `REFUSE`, with the evidence and the reason. **A `REFUSE` row is the
script having already ruled something out** — do not re-litigate it, and do not propose it to the
user. `0 candidates` is a real and useful answer.

It reports rather than decides, so the two halves stay separate: the greps are a fixed cost paid
once, and the judgement below is the part that needs reading.

Two things that are **not** candidates, however they look:

- **A `:remote` row.** It names a surface that exists upstream and this product did not take. That is
  the row doing its job — it is how Claude learns the surface exists without paying for it.
- **A `docs/` path that is not on disk.** Reference docs are fetched on demand; a missing one is a
  fetch instruction, not a missing file. The `# FETCH-BASE:` line in `MAP.tsv` says where from.

## 2. The memory levels — report before touching

A rule stated at two levels drifts, and the copy that goes stale is the one nobody reads. But the
memory directories are also where discoverability lives, so **find the inbound references first**:

`ga-cleanup-scan.sh --memory` already swept the levels — it finds the machine-local store by walking
up from the install root (it is keyed on the directory Claude was *started* in, which is usually an
ancestor), skips `type: user` as per-person, and flags an in-repo memory with no `INDEX.md` row.
What it cannot judge is what a removal would cost, so check the inbound references yourself:

```bash
./Scripts/ga-cleanup-scan.sh --memory              # the sweep, with verdicts
grep -rn "<the-memory-slug>" .claude docs CLAUDE.md 2>/dev/null   # what points at it
```

| Level | Reach | On a duplicate |
|---|---|---|
| Enterprise | every repo, every user | **Read-only. Never touch it.** If it duplicates a lower rule, the lower one is the candidate |
| User-Level | this user | Candidate — the project or plugin copy already covers it |
| project | everyone who clones | Survives, unless a plugin ships the same rule |
| Plugin | every repo that installs it | Survives for tooling rules; a product rule does not belong here |

- **A project-scoped memory directory adds no reach over the repo itself.** A rule in both
  `~/.claude/projects/<this>/memory/` and `CLAUDE.md` is pure duplication — the memory copy goes.
- **A memory without an index row is a memory nobody finds.** Removing one means removing its
  `.claude/memory/INDEX.md` row in the same change — and removing *only* the row orphans the file.
- **Check the surviving copy carries the reasoning**, not just the sentence. Keeping a one-line
  restatement over the fuller statement loses the *why*, which is what stops the rule being argued
  again. If that is the trade, say it and let the user choose.

## 3. Ask per candidate — never batch

One question per candidate, with the reason it is one and what breaks if it goes. **A decline is a
judgement about relevance, not about the content being wrong**, and it gets reversed often enough
that the bytes are worth keeping — which is why nothing is destroyed.

Dry run first, always. Without `--apply` it prints the plan and writes nothing:

```bash
./Scripts/ga-remove.sh <path> --reason "<why this product declines it>"
./Scripts/ga-remove.sh <path> --reason "<why this product declines it>" --apply
```

**Removing a rule from `CLAUDE.md` needs its own explicit approval** — show the exact text and wait
(§12, [STRUCTURE.md](../../docs/STRUCTURE.md)). A rule is not a file, and this command's authority
over files does not extend to it.

`ga-remove.sh` reports prose references it cannot safely rewrite, with file and line. **Those are
work, not noise** — a sentence pointing at a retired file is worse than no sentence, because it
resolves and misleads. Fix them in the same change.

## 4. Reversing one

```bash
./Scripts/ga-remove.sh --revive <path> --apply
```

Byte-identical, from `safetodelete/`, with no network and no reference checkout. Say this exists when
someone hesitates over a candidate — the reversibility is the reason it is safe to decide now.

## 5. Seal and report

```bash
./Scripts/ga-reseal.sh --apply
```

Skipping the reseal turns every file this command touched into an orphan no uninstall can remove.

Then report, and be specific:

- **What was retired**, and the reason recorded for each.
- **What was kept**, and why — a candidate declined is as much a decision as one taken.
- **Prose references left to fix**, with file and line, or explicitly none.
- **What this command refused to touch**: the Enterprise level, `:remote` rows, fetch-on-demand docs.
- **Net token effect**, honestly. That is the point of the command, so quantify it: bytes of
  always-loaded text removed, and what it costs per use if a lookup now has to fetch instead.

A report that says "cleaned up" without naming what survived is the failure mode of this command.
