---
description: Declare the project's stack profile — tech-stack, architecture, dependency managers and build system — by extracting them from an existing codebase or asking on a new one
argument-hint: (no arguments — it asks, or extracts)
allowed-tools: Bash, Read, AskUserQuestion
---

```bash
./Scripts/ga-step.sh require declare-profile      # sequence gate
```

**Exit 5 means an earlier step has not run.** Say which one, and stop — never pass `--force`, and
never work around it. Order and why: [SEQUENCE.md](/docs/operations/SEQUENCE.md)(../../docs/SEQUENCE.md).

This step records **four answers**, and **every one of them is optional**. None blocks the step,
none blocks the next one, and all are revisable later with
`./Scripts/ga-profile.sh --set <key> <value>`. A first answer is not a commitment.

| # | Answer | Key(s) | Optional |
|---|---|---|---|
| 1 | Base tech-stack | `platform`, `language`, `language_version` | yes |
| 2 | Architecture requirement | `architecture` | yes |
| 3 | Dependency manager(s) — one or more | `dependency_managers` | yes |
| 4 | Build system | `build_system`, `build_command` | yes |

What the step records is that the question was **put**, not that it was answered. A deferred answer
is written as `not yet` rather than left out, so a later session can tell "asked, deferred" from
"never asked" — which is the whole difference this step exists to make. Never press for an answer
the user does not have; `not yet` is a complete response to all four.

It does **not** require authoring a `profiles/<name>/` directory. That stays optional, for a
project that later wants scaffold templates and note generators.

## S1. Extract first — what it finds decides the path

```bash
./Scripts/ga-profile.sh --extract
```

Every row is `key⇥value⇥evidence`. **The layer recognises no ecosystem.** It ships no table of
build markers, because such a table is stack content: it would be permanently incomplete, and it
would decide for every consumer which ecosystems the layer treats as first-class. So the only
thing extract can observe is a profile *this project* authored — the `detect_marker_*` rows in
`profiles/<name>/profile.tsv`. Everything else is `not observed`, which means **ask**.

| What extract returned | Path |
|---|---|
| Every row `not observed` — no authored profile matches | **declare** — ask all four |
| An `active` row — a profile's markers all present | **extract** — confirm its declared values |

`architecture` is always `not observed`: no scan establishes it, on any stack.

Read the scan's `## mode` line as corroboration, not as the rule:

```bash
sed -n '/^## mode/,/^## /p' .claude/notes/.evidence/INIT-SCAN.md 2>/dev/null | head -5
```

It answers *has this repo been worked in*, which is a different question from *does this repo have
a stack a scan can see* — a one-commit repo holding only a README reports `existing`. Branching on
it alone would send a brand-new repo down the extract path to confirm a table of `not observed`.
`/project-init` reads the same artifact and is likewise expected to say which path it took and let
the user redirect.

## S2. Confirm, or ask

**Extract path — a profile matched.** Show the rows as a table, evidence column included, and ask
once to confirm or correct them. Do not ask question-by-question when the profile already answered.

**Declare path — nothing matched.** This is the normal case, and it is the intended one: the
answers belong to the project, not to the layer. Ask the four questions with `AskUserQuestion`, in
one round. Offer "decide later" on **every one** of them — not just the ones that look hard — and
record a deferral as `not yet`. Four `not yet` answers is a valid outcome of this step.

**Never infer an answer from what you see in the tree.** Recognising a build file and concluding a
stack from it is exactly the guessing this step exists to replace, and it is wrong as often as it
is convenient. If the user wants that inference to happen automatically next time, the answer is
for them to author a profile with `detect_marker_*` rows — then it is their rule, recorded in
their repo, rather than the layer's assumption.

## S3. Write the answers

One `--set` per answer. The script writes `.genericarch/PROFILE.tsv`, which is tracked in a
consumer repo — so these answers are shared with everyone who clones, not per-developer.

```bash
./Scripts/ga-profile.sh --set platform            <value>
./Scripts/ga-profile.sh --set language            <value>
./Scripts/ga-profile.sh --set dependency_managers "<one or more, space separated>"
./Scripts/ga-profile.sh --set build_system        <value>
./Scripts/ga-profile.sh --set build_command       "<value>"
./Scripts/ga-profile.sh --set architecture        "<value>"
./Scripts/ga-profile.sh --set declared            yes
```

**Only `declared` is always written.** Run a line above it only for an answer the user actually
gave; for a deferred one write `not yet` as the value, and for an answer that came back
`not observed` from extract and was not confirmed, write nothing at all. `--check` requires none
of the six.

If this repo genuinely has no stack — a docs-only repo, or the layer itself — record that instead.
It is an answer, not a skip:

```bash
./Scripts/ga-profile.sh --declare-none "<why this repo has no stack>"
```

**Never write `active` to `none`.** Every reader of `ga_profile_active` treats an empty value as
"no stack here"; `active=none` sends all of them looking for `profiles/none/`. `--declare-none`
writes the `declared` key and leaves `active` alone, which is the whole reason it exists.

Set `active` only when a `profiles/<name>/` directory actually exists — `--extract` reports one as
`active` when every `detect_marker_*` it declares is present.

## S4. Record the architecture answer as a decision

The architecture answer is a §0 choice, so it belongs in the decision log as well as the
projection — the projection is what tooling reads, `DECISIONS.md` is what a person reads:

```
/decide architecture — <the answer> — <why>
```

Skip this only when the answer was "decide later".

## S5. Seal and record

```bash
./Scripts/ga-profile.sh --check       # must exit 0
./Scripts/ga-step.sh record declare-profile "<profile name, or: none — reason>"
```

`--check` warns when `.genericarch/PROFILE.tsv` is untracked or uncommitted. That is the one way
two developers end up with different answers, so tell the user to commit `.genericarch/` — do not
commit it yourself (CLAUDE.md §2.2).
