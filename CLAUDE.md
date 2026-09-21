# CLAUDE.md — Generic Development Layer

A tech-stack-agnostic layer for managing a development environment as **shared memory with Claude**:
the rules, indexes, notes, memory, decision record and skills that let Claude work consistently in
any repo. The layer ships **no stack content of its own** — language, build system, architecture
pattern and their rules come from a **stack profile** a project authors when it adopts the layer
([profiles/](profiles/CLAUDE.md)); **none ships by default**.

**Session material only.** Setup, build, ship, project settings — none of it is here.
**Before any task that is not writing code, grep the map** (§3): it routes all of them, and a topic
missing there is one to ask about, not improvise. A failed script writes its own report to
`.genericarch/failures/` — read that, never the script.

---

## 0. Decisions Claude must ASK about, never assume

Check [DECISIONS.md](/docs/decisions/DECISIONS.md)(docs/DECISIONS.md) first; if a row answers it, follow it without re-asking.
Otherwise offer the options with a recommendation plus **Other** and (where meaningful) **Skip**,
wait, then record it with `/decide`.

**Which decisions need asking is the active profile's to state** — architecture pattern, persistence,
caching, and the like. Two hold on any stack: a **new external dependency** is always asked before
it is added, and until a profile is declared, treat **any** architectural choice as a §2.1 "no
silent choice" and ask.

Ask **once per feature**, not once per file. Don't start while the question is open — do the
answer-independent work first (models, interfaces, keys), then ask.

---

## 1. Stack — declared by the active profile

The layer fixes no stack. The active stack profile ([profiles/](profiles/CLAUDE.md)) declares the
language, build system, UI/runtime, concurrency model and test framework, and supplies the
stack-specific rules, architecture principles, conventions and definition-of-done that a stack needs.
**None ships by default** — a project authors one when it adopts the layer.

**Never quote a version from memory or from this file.** Versions are acquired from the project and
recorded in [PROJECT.md](.claude/notes/PROJECT.md).

---

## 2. The rules that must never be broken

These hold on **every** stack — they govern how Claude works in the layer, not how any app is built.
A profile adds its own rules at its own numbers; it may not weaken these.

1. **No silent architectural choice.** If it's a §0 decision, ask.
2. **Never `commit` or `push`** — not to "save progress", not because the work looks finished. Leave
   it in the working tree and say what changed. Only an explicit "commit"/"push" counts; a release
   or `/project-init` run is not one.
3. **Follow the matching skill and name it before starting.** Skipping one of its steps means saying
   which step and why. If none fits, say that — a wrong skill is worse than none.
4. **Stop on a vague instruction.** If a request admits readings that lead to materially different
   work, settle it before doing anything — never pick silently, never ship a "safe subset". Ask for
   a **reference** (repo, file, doc URL, the existing thing it should resemble — building from the
   name of a thing produces something plausible and wrong), a **focused goal** ("first paint under
   300 ms", not "improve this"), or **which reading**, listed, with your recommendation. Ask only
   what the user alone can answer; whatever the code, the docs or [DECISIONS.md](/docs/decisions/DECISIONS.md)(docs/DECISIONS.md)
   already settles, look up instead.
5. **Never delete an installed file with `rm`.** `./Scripts/ga-remove.sh <path> --reason "…"` records
   the tombstone that stops the next install re-creating it and the DECISIONS row that stops it being
   re-proposed. Any command that rewrites installed files closes with `./Scripts/ga-reseal.sh --apply`.
6. **Every component carries its own `CLAUDE.md`.** A component is any directory that owns a concern.
   Write it **before the code**, opening with the boundary (owns · may depend on · never imports),
   then only rules true inside that directory. **Never write a list of components** — the rule
   follows the directory that exists → [STRUCTURE.md](/docs/reference/STRUCTURE.md)(docs/STRUCTURE.md)
7. **Doc comments, not meta comments.** No comment that restates the code or narrates the edit;
   anything about the change belongs in the commit message. Every function or initialiser you write
   or change carries a doc comment stating what the signature cannot.
8. **Build to validate on your own initiative; ask before you run or test.** Compiling is how a
   change gets checked, so build freely and report what the build printed. **Running and testing
   need the user's consent** — any test run, or launching the app on a simulator or device. Consent
   is per request and never standing. Don't rebuild gratuitously: minutes of their machine are not
   free.

---

## 3. Index

**Look it up before you read or search for it.** Four greps replace a table of contents:

```bash
grep -i navigation .claude/MAP.tsv     # which doc, note, pattern or skill covers a topic
grep -i lint .claude/SCRIPTS.tsv       # which script does this, and its contract
./Scripts/find.sh <name>               # where is this screen/route/endpoint/asset/token?
./Scripts/ga-step.sh show              # which step is next, and why a command refused
```

Commands run in a fixed order — install → `/project-init` → `/sync-app-notes` → ready —
enforced by each command's first step. Exit 5 means an earlier one has not run →
[SEQUENCE.md](/docs/operations/SEQUENCE.md)(docs/SEQUENCE.md).

[`MAP.tsv`](.claude/MAP.tsv) carries every doc, note, pattern and skill.
[`SCRIPTS.tsv`](.claude/SCRIPTS.tsv) is each script's contract — **never read a
script's body to learn what it does**; read it only when a call fails, then fix it in the same
change.

**What earlier sessions learned:** [`.claude/memory/INDEX.md`](.claude/memory/INDEX.md) — in-repo
and tracked, so it survives a clone. Never write to a machine-local store. What may be written, and
where **new** material belongs: [STRUCTURE.md](/docs/reference/STRUCTURE.md)(docs/STRUCTURE.md).

**In a repo with `openspec/`, look it up here before exploring.** `/opsx:explore` and
`/opsx:propose` answer from the four indexes above first — a spec written against something this
repo already settled is worse than no spec. They are the only OpenSpec commands nothing can inject
into, so this line is the whole mechanism → [OPENSPEC.md](/docs/reference/OPENSPEC.md)(docs/OPENSPEC.md).

Both indexes are pruned per install, so **a row that is not here may still exist upstream** —
declined, or a layer this product did not take. Check `.genericarch/TOMBSTONES.tsv` before
concluding something does not exist ([INSTALL-MANIFEST.md](/docs/reference/INSTALL-MANIFEST.md)(docs/INSTALL-MANIFEST.md)).

`.claude/notes/` is generated from the actual project. **Edit the affected rows in the same change
as every insertion or deletion.** A full rescan is the user's **`/sync-app-notes`**; never start one
yourself.

---

## 4. For Claude specifically

- **Never edit this file without explicit approval** — including when certain. Show the exact text
  and wait. Where new guidance belongs instead: [STRUCTURE.md](/docs/reference/STRUCTURE.md)(docs/STRUCTURE.md).
- **An existing repo's structure wins.** Never impose the layer's conventions on a repo that has its
  own; `/project-init` reconciles by asking, and installs nothing on your own initiative.
- **The active profile owns stack rules.** Architecture, concurrency, dependency wrapping, testing,
  conventions and the definition-of-done come from the declared profile — read it, don't assume a
  stack. If no profile is declared, say so rather than guessing one.
- **Before calling a change done**, walk the active profile's definition-of-done (or `/verify`);
  never declare completion from memory of a checklist. If something can't be checked (device,
  environment, tooling), say what was skipped.
- If a requirement conflicts with a §2 rule, or §0 has no recorded answer, **raise it** — don't
  silently work around it, and don't choose the scope of a broad instruction yourself (§2.4).
