# The CLAUDE.md task pipeline

Nine phases and five utilities for editing a markdown document — usually a `CLAUDE.md` — under a
record. Intake → locate → audit → plan → edit → verify → test → present → commit.

- **When to read this:** driving the pipeline, adding a phase, or working out why a phase refused.
- **Entry point:** `./Scripts/claude-workflows/run-task.sh <project> <task-id> <action>`
- **Driven by:** the [new-feature](../.claude/skills/new-feature/SKILL.md) skill, or by hand.

---

## Why a pipeline and not a prompt

The logic lives in scripts so it does not live in a skill body. A skill body loads into
context every time the skill fires; a script loads only when it runs. Moving nine phases
of parsing, validation and diffing out of the prompt is the difference between a skill
that costs a page and one that costs a paragraph.

The second reason is the record. Each phase writes one artifact, so the next phase greps a row
instead of re-deriving it, and a human can read what happened without re-running anything.

## Scripts are called, not read

Every script under `Scripts/` carries a `#@` metadata header declaring its contract, and
[`.claude/SCRIPTS.tsv`](../.claude/SCRIPTS.tsv) collects them into one greppable registry —
generated, never hand-edited:

```bash
grep -i lint .claude/SCRIPTS.tsv                      # which script covers this
awk -F'\t' '$4!="call"' .claude/SCRIPTS.tsv           # what is gated
awk -F'\t' '$1=="Scripts/find.sh" {print $7"\n"$8}' .claude/SCRIPTS.tsv   # its in/out
./Scripts/claude-utils/register-scripts.sh            # regenerate
./Scripts/claude-utils/register-scripts.sh --check    # CI: fail if stale
```

**The row is the contract. Do not read a script's body to learn what it does** — that spends the
tokens the row exists to save, and the row states inputs, outputs, exit codes and side effects
precisely enough to call it blind. Rely on the declared output rather than re-reading the files it
just summarised.

**Read the body only when a call fails.** Then fix it, in the same change, and re-run
`register-scripts.sh` if the fix changed the contract. A script whose declared output no longer
matches its behaviour is worse than one with no header at all.

The `claude` column says what is safe to invoke:

| Value | Means |
|---|---|
| `call` | run it |
| `emit-only` | it prints commands it deliberately does not run (phases 7, 9) |
| `needs-approval` | it writes; requires an explicit `--approve` / `--yes` (phase 5, rollback) |
| `never:<reason>` | Claude must not run it — `check.sh` compiles the iOS floor (§2.12) |

Header fields, all required, one per line as `#@<field><spaces><value>`, and no value may contain a
tab: `kind` `platform` `claude` `purpose` `usage` `in` `out` `exit` `effects`.
`register-scripts.sh` fails loudly on a script missing any of them — a script with no row
is a script nobody will call.

## macOS only

These scripts run on a Mac and are written to that assumption, not hedged for portability: bash 3.2
(no associative arrays, no `mapfile`, no `${var^^}`), BSD `sed -i ''`, BSD awk, `shasum`, and the
Xcode command-line tools. `_common.sh` checks `uname` and exits **78** on anything else.

The guard exists because the failures would otherwise not look like a platform problem. GNU `sed -i`
takes no argument, so `sed -i ''` silently eats the next one; and BSD awk counts `length()` in bytes
where GNU counts characters, so a line-length rule reports different numbers on each. Both read as
bad data rather than the wrong machine.

That byte-counting is also why `claude-lint.sh` measures with its own `dlen()` — an em-dash would
otherwise inflate a line by two, which produced a page of false positives on these docs.

## Xcode

The pipeline never builds (§2.12). What it does instead:

- `init-claude-env.sh` records the project's `.xcworkspace`/`.xcodeproj` and its **shared** scheme
  names, read off the filesystem — `xcodebuild -list` would be authoritative and would also
  be a build invocation. A scheme stays user-local until it is ticked Shared in Xcode ▸
  Product ▸ Scheme ▸ Manage Schemes, and an unshared scheme cannot be named on an
  `xcodebuild` command line; the script warns when it finds none.
- Phase 7 emits `xcrun swiftc -parse` rather than bare `swiftc`, and the project's real
  `xcodebuild test -workspace … -scheme …`. On a Mac with several Xcodes installed those are
  different toolchains, so a snippet can pass with the bare binary and fail in the IDE. The emitted
  script names the active `xcode-select -p` for that reason.
- Findings print `xed -l <line> <file>`, so a reported line opens in Xcode where it lives instead of
  being hunted for. Printed, never run — a script that seized the editor would be a surprise.

## Two gates that never open on their own

| Gate | Rule | What the script does |
|---|---|---|
| **Phase 5 writes** | [STRUCTURE.md](STRUCTURE.md) — CLAUDE.md is approval-gated | Refuses without `--approve`; prints what it would do and exits 4 |
| **Phase 9 commits** | CLAUDE.md §2.11 — never commit or push | Never runs git. Writes `09-commit.sh` for you to run |

Phase 7 is the third: CLAUDE.md §2.12 forbids this tooling from invoking a compiler, so it extracts
snippets and **prints** the check commands into `07-commands.sh`. Nothing there is executed.

These are not configurable. A flag that turned them off would make the rules advisory.

## Setup

```bash
./Scripts/claude-utils/init-claude-env.sh --add <name> <path>   # register a project
./Scripts/claude-utils/init-claude-env.sh --scan ~/code         # or find every CLAUDE.md
./Scripts/claude-utils/init-claude-env.sh --list
```

The registry (`.claude/claude-tasks/projects.tsv`) records each project's root, its CLAUDE.md
path, its detected test command, the glob phase 7 greps for symbols, and its Xcode container
plus shared scheme names. Detection is best-effort and recorded rather than enforced — phase 7
prints what it found, so a wrong guess is visible rather than silent.

## Running

```bash
run-task.sh <project> <task> 1 --text "<the request>"   # one phase
run-task.sh <project> <task> all --approve              # 1→9
run-task.sh <project> <task> status                     # what ran, what is next
run-task.sh <project> <task> next                       # the first unfinished phase
run-task.sh list
```

Actions also accept phase names (`parse find audit plan apply verify test present commit`) and the
utilities (`rollback lint links sync clean`).

Arguments after the action are forwarded to whichever phase accepts them, so one `all`
invocation can carry `--text`, `--edit` and `--approve` to phases 1, 4 and 5. In `all`,
`--type` goes to phase 1; pass it to phase 9 directly to override the commit type.

`all` stops before phase 5 unless `--approve` is present, and stops at the first phase that fails.

## The phases

| # | Script | Writes | Fails when |
|---|---|---|---|
| 1 | `01-parse-claude-task.sh` | `01-task.env`, `01-request.txt` | no request given |
| 2 | `02-find-claude-file.sh` | `02-file.env` | target missing (unless `--allow-missing`) or unreadable |
| 3 | `03-audit-claude-sections.sh` | `03-sections.tsv`, `03-symbols.tsv`, `03-issues.tsv` | target unreadable |
| 4 | `04-plan-claude-edits.sh` | `04-plan.tsv`, `04-outline.md`, payloads | any edit is rejected |
| 5 | `05-apply-claude-edits.sh` | `05-applied.tsv`, `05-backup/` | no `--approve`, digest drift, or any edit fails |
| 6 | `06-verify-claude-syntax.sh` | `06-verify.txt` | front matter, table or link errors |
| 7 | `07-test-claude-artifacts.sh` | `07-commands.sh`, `07-api-check.tsv` | — (reports, never fails) |
| 8 | `08-present-claude-diff.sh` | `08-diff.patch`, `08-summary.md` | — |
| 9 | `09-commit-claude-changes.sh` | `09-message.txt`, `09-commit.sh` | phase 5 has not applied anything |

**Phase 3 always exits 0** when it could read the file. Its issues describe the document as it
already was — findings for the planner, not failures. Exiting non-zero would abort `all` on any
document that already had a duplicate heading, which is most of them.

**Phase 6 does fail**, because it is a gate rather than a diagnostic: it asserts the
document is still valid after the edit. Lint findings only warn; front matter, tables and
links error.

## Writing a plan

An `--edit` is five `|`-separated fields — `SECTION|ACTION|OLD|NEW|NOTE`:

| Action | Needs | Effect |
|---|---|---|
| `replace` | OLD + NEW | exact-literal, must match exactly once |
| `delete` | OLD | same matching rule |
| `append` | NEW | end of the section, before the next heading |
| `insert-after` | NEW | straight after the section heading |
| `new-section` | NEW | end of file, or after `NOTE: after: <section>` |

OLD and NEW are literal single-line text, or `@path` to a file. Use `@file` for anything multi-line
or containing a `|`. Phase 4 normalises both into `04-payload-N.{old,new}` so phase 5 only ever does
exact-literal file reads — no regex, no quoting surprises.

`--template` generates a skeleton plan from phase 1's section hints, resolved against real headings.
`--from <tsv>` reads a plan file.

**Phase 4 is where a wrong edit is meant to die.** It rejects an OLD that is absent, an OLD that
matches more than once, and a section that does not exist — and it warns when a `delete`
would orphan anchor links pointing at that heading. Matching twice is the classic way a
`str_replace` lands in the wrong section, and catching it costs nothing here.

## Exit codes

| Code | Means |
|---|---|
| 0 | completed, nothing wrong |
| 1 | ran, found a real problem |
| 2 | bad arguments |
| 3 | a prior phase has not run, or its artifact is missing |
| 4 | refusing to proceed without `--approve` / `--yes` |

A caller has to distinguish "found problems" from "could not run" from "needs approval".
One code for all three is what makes a pipeline undebuggable.

## Undo

```bash
run-task.sh <project> <task> rollback          # preview
run-task.sh <project> <task> rollback --yes    # restore
```

Restores from the phase-5 backup, **not** git. Phase 2 may have found the document
already dirty, and `git checkout` would discard those unrelated edits too. The backup
holds exactly the bytes that were there immediately before phase 5 wrote. `--from-git`
restores the committed version instead, and refuses when phase 2 recorded the file as
already dirty unless you add `--force`.

The state discarded by a rollback is itself saved, because rolling back a rollback is a
real request.

## Utilities

| Script | Does |
|---|---|
| `init-claude-env.sh` | register projects, detect per-project config |
| `validate-claude-links.sh` | resolve internal links and anchors; never fetches the network |
| `claude-lint.sh` | formatting; `--fix` touches only what cannot change meaning |
| `rollback-claude.sh` | undo phase 5 |
| `sync-claude-skill.sh` | find skills and docs quoting what the task changed |
| `_common.sh` | exit codes, artifact layout, `md_sections`, `md_symbols`, counters |

`sync-claude-skill.sh` reports and changes nothing by default. A skill body is a procedure someone
wrote; rewriting it from a diff would be guessing at intent. What it can do honestly is list every
file that names a changed section or quotes text the edit removed. `--write` appends a dated marker
(backing the file up first) — a marker is not the fix.

## Adding a phase

In this order:

1. **Write the `#@` header first**, then the body. The header is the contract; writing it afterwards
   is how a body ends up doing something the row does not describe. If you cannot state `#@in` and
   `#@out` exactly, the operation is not ready to be a script.
2. `_common.sh` next — anything two phases need lives there. `md_symbols` is there because phases 3
   and 7 must classify identically while reading *different* versions of the file. Source it; never
   reimplement `die`, `kv_*`, `count_*` or `md_*`.
3. Take preconditions through `need_artifact`, and write `|| exit $?`. It returns rather than dies:
   inside `$(…)` an `exit` kills only the subshell, so without the guard the script prints the error
   and carries on with an empty variable.
4. Use `count_rows` / `count_match`, never `$(grep -c … || echo 0)` — `grep -c` prints `0` *and*
   exits non-zero, so that idiom emits `"0\n0"` and every later arithmetic expansion dies.
5. `usage_text() { usage_from "$0"; }` — never a hardcoded `sed -n '2,17p'`. Those ranges truncate
   silently the moment a line is added above them.
6. Register the phase in `run-task.sh`: `phase_title`, `phase_script`, `normalize_action`, and
   `accepts` for its flags.
7. Pass colours into `awk` with `-v`; a hardcoded escape ignores `NO_COLOR`.
8. `printf -- '- …'` when a format string starts with a dash, or printf reads it as an option.
9. Run `./Scripts/claude-utils/register-scripts.sh`, then `--check` to confirm it is in sync.
10. Reference it from the skill that needs it, in that skill's step-0 script list, and add a
    `.claude/MAP.tsv` row. A script nothing calls is a script nobody finds.

`/learn --script` walks this sequence for an operation done by hand twice, and applies the same
earned-it test a skill gets.

## What is not tracked

`.claude/claude-tasks/` is gitignored — per-run working state. The scripts are tracked; what a
particular run produced is not. `clean --yes` deletes a task's artifacts, and warns first when it
would take the phase-5 backups with them.
