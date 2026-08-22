---
description: Bring an install up to date with the GenericArch base and promote the patterns this repo's code now justifies — reviews per file and per skill, applies only what is approved
argument-hint: "[optional: --ref <tag> | base | skills to run one half]"
allowed-tools: Read, Edit, Grep, Glob, Bash, AskUserQuestion
---

```bash
./Scripts/ga-step.sh show      # project-init must already have run
```

**If `project-init` is still `pending`, stop and say which step is missing.** Syncing a repo whose
rule conflicts are unsettled means offering it surfaces it already declined. This command is
deliberately **not** a lifecycle step — nothing waits behind it, and a repo that never drifts never
runs it.

Two halves, in this order. `$ARGUMENTS`: `base` or `skills` runs one; `--ref <tag>` pins the
comparison; nothing runs both.

- **A. Base sync** — the install is behind upstream. Which updates does this product want?
- **B. Skill matching** — the code has grown. Which patterns can now actually fire?

They are one command because they share the same question: *what does this repo justify carrying
today?* Running only A leaves reference material that could be working; running only B promotes
skills against a stale base.

---

# A. Base sync

## A1. Establish what is installed, and against what

**One script gathers all of this.** Offline, read-only, and it stops on its own if the checkout
carries two install roots:

```bash
./Scripts/ga-sync-scan.sh                          # install facts + patterns; no base needed
./Scripts/ga-sync-scan.sh --base /tmp/ga-base      # adds the per-file drift half
./Scripts/ga-sync-scan.sh --base-only | --patterns  # one half at a time
```

**It exits 1 on two install roots** and prints both. That is a stop, not a warning — a sync would
faithfully update whichever one it was pointed at. Consolidating is its own decision.

The manifest is the authority for the version, not `MAP.tsv` and not any doc; the script reads it
there. To check by hand:

```bash
ls .genericarch/manifest-*.json
awk -F'"' '/"source_ref"/{print $4}' .genericarch/manifest-*.json
```

**More than one manifest is normal** — each release leaves its own, and the newest is current. **More
than one manifest at different roots in the same checkout is not.** Check one level up and one level
down before comparing anything:

```bash
find "$(git rev-parse --show-toplevel)" -maxdepth 3 -name '.genericarch' -not -path '*/.git/*'
```

Two live installs duplicate every command and skill, only one can be uninstalled, and a sync will
faithfully update the wrong one. `install.sh` refuses to create the second, but an older installer
did not, so a repo can still be carrying one. **Stop and report it** — consolidating is its own
decision, not a step to fold into a sync.

Then get a base to compare against. `adopt-review.sh` defaults `--base` to its own checkout, which in
an installed target does not exist, so clone the ref explicitly rather than letting it guess:

```bash
git clone -q --depth 1 --branch "<tag>" https://github.com/kalpesh-jetani/GenericArch.git /tmp/ga-base
```

Use the tag the user named, or the newest one. **Never `main`** — the docs would drift out from under
an install pinned to a tag.

## A2. Review, and let the user choose

```bash
./Scripts/adopt-review.sh . --base /tmp/ga-base            # numbered, read-only
./Scripts/adopt-review.sh . --base /tmp/ga-base --diff 3   # with context, when a row is unclear
```

**Claude must never pass `--take`.** That is the tool's own contract: overwriting a file in a shipping
repo is a human decision, and an approval never carries from one run to the next. Present the numbers
with a recommendation per row and let the user answer — then run exactly the list they gave.

Classify every row before recommending. Three kinds, and they are not interchangeable:

| Row | Recommend | Why |
|---|---|---|
| **A shared library** (`#@kind lib` — `ga-lifecycle.sh`, `ga-handoff.sh`, `claude-utils/_common.sh`) | **Take** | Every script beside it *sources* it. An old copy is not a conservative choice, it is callers whose functions do not exist — failing with `command not found` while exiting 0. `install.sh` upgrades these in lockstep now; a lib appearing here means it was edited locally, so say plainly what may break |
| **A file with a load-bearing local edit** | **Do not take** | Taking it reverts the fix. Name the edit and what it solves. Diff before assuming a row is cosmetic |
| **Everything else** | Take unless it re-adds something declined | Commands and indexes are usually pure gain — `/project-init` and `/sync-app-notes` grow by hundreds of lines between releases |

Check the declined list first, or a sync quietly reverses recorded decisions:

```bash
./Scripts/ga-remove.sh --list                       # tombstoned — must not come back
grep -A20 'Do not re-propose' docs/DECISIONS.md
```

A row that would restore a tombstoned path is **not a candidate**. Say so and move on.

## A3. Verify after, never assume

Taking files can break things that were working. Prove it did not:

```bash
./Scripts/claude-utils/register-scripts.sh --check   # new scripts registered, headers in sync
./Scripts/ga-init-scan.sh . --write                  # route issues MUST be 0
head -1 .claude/MAP.tsv                              # FETCH-BASE stamp still present
./Scripts/ga-step.sh show                            # no `command not found`
./Scripts/ga-reseal.sh --apply                       # last, always
```

`adopt-review.sh` carries the `FETCH-BASE` stamp across now, because the base does not have one and
copying it over dropped every fetched `docs/` route silently. **Verify it anyway** — that failure
leaves the rows in place, pointing nowhere, and reads as working.

Without the reseal, every file taken becomes an orphan no uninstall can remove.

**This half removes nothing.** A file the sync makes redundant is a candidate for
[`/clean-up-genericarch-extra-memory`](clean-up-genericarch-extra-memory.md), reported here and
retired there.

---

# B. Skill matching

## B1. What ships un-promoted, and why

`docs/patterns/` holds patterns that **cannot fire in an empty repo**, so they ship as reference
rather than as skills — a skill costs its description in every session, and one that fires on nothing
costs it for nothing.

`/learn <pattern>` does the promoting and owns the three-part earned-it test. **This command's job is
narrower: work out which patterns the code now justifies, and hand each one over.** Do not
reimplement the test, and do not write a `SKILL.md` here.

```bash
ls .claude/skills/                                        # already promoted
awk -F'\t' '$2=="pattern"{print $1}' .claude/MAP.tsv      # available, un-promoted
```

## B2. Derive each candidate from the code

**`./Scripts/ga-sync-scan.sh --patterns` computes every row below.** Run it instead of running the
signals by hand; it prints `PROMOTE`, `NOT-YET` or `REFUSE` per pattern with the count that decided
it, and falls back to the known upstream set on a lean install whose `MAP.tsv` carries no pattern
rows — which is most of them.

The table is the contract it implements, kept here so a wrong verdict can be argued with. Evidence,
not intent: a pattern with no signal is not a candidate, and "not yet" is a result worth printing.
**Quote the globs** if you do run one by hand — an unquoted `--include=*.swift` is expanded by the
shell before grep sees it and the command *fails* rather than returning zero, which reads as "no
signal":

| Pattern | Promote when | Signal |
|---|---|---|
| `dark-light-mode` | dark variants actually exist | `grep -rl '"dark"' --include='Contents.json' .` · `grep -rl colorScheme --include='*.swift' .` · rows in `.claude/notes/ASSETS-COLORS.md` |
| `rtl-support` | an RTL language ships | `find . -name '*.lproj' \| grep -cE '/(ar\|he\|fa\|ur)\.lproj'` · RTL locales in an `.xcstrings` |
| `style-guide` | tokens exist to use instead of literals | `grep -c '^\| `' .claude/notes/STYLE-GUIDE.md` |
| `feature-complete` | features ship often enough to have a close-out | rows in `.claude/notes/FEATURES.md` · `ls Packages/Features` |
| `change` | there is code to change | any Swift outside a scaffold |
| `release-bump` | this repo publishes versioned releases | `git tag \| tail -3` · a CI config · **skip unless the product IS a distributed package** — for an app it is a release-workflow tool, not code generation |

**`wrapper` is not promotable.** It is the reference behind CLAUDE.md §7, cited by the module docs.
Leave it as a pattern.

## B3. Hand over one at a time

For each candidate, say what fired it — the actual signal, with counts — then run `/learn <pattern>`
and let it apply its own test and its own approval gate. **One at a time.** Promoting three skills in
one pass changes behaviour in every future session with no way to attribute a regression.

If a pattern has a signal but fails `/learn`'s "needed at least twice" test, that is a real answer:
report it as *not yet*, with what would change it.

---

# Report

- **Base**: installed version → compared ref. Rows taken, rows declined **and why**, rows refused for
  restoring a tombstoned path.
- **Verification**: register-scripts, route issues (must be 0), FETCH-BASE present, reseal applied.
- **Skills**: promoted, and — as explicitly — the candidates with a signal that did *not* qualify.
- **Cleanup candidates** found, handed to `/clean-up-genericarch-extra-memory`. This command removed
  nothing; say so.
- **Net token effect**, honestly: description bytes added per session by each promoted skill, against
  what it saves per use. Say when it is an increase.

A report that says "synced" without naming what was declined is the failure mode of this command.
