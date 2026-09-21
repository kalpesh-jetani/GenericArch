# Documentation Index

Navigate GenericArch documentation by purpose.

## Adopt a New Project

**Start here if you're installing GenericArch into an existing repo.**

- [Adoption flow](/docs/adoption/ADOPTION.md) — reconcile your rules with this layer's
- [What travels in adopt.sh](/docs/adoption/SHARING.md) — files and directories, and why
- After install: run `/declare-profile`, then `/project-init`, then `/sync-app-notes`, then you're ready

## Run Commands & Understand the Lifecycle

**Start here if a command failed, you want to know what step is next, or you're debugging the sequence.**

- [Lifecycle steps](/docs/operations/SEQUENCE.md) — the order: install → declare-profile → project-init → sync-app-notes → ready
- [Scanning pitfalls](/docs/operations/SCAN-TRAPS.md) — why generic scans fail and how the layer works around them
- [Authoring and versioning](/docs/operations/CLAUDE-TASKS.md) — tasks that touch CLAUDE.md, releasing, deprecating

## Build Notes as a Searchable Index

**Start here if you're learning about the pattern-search discipline that makes notes efficient.**

- [Pattern search](/docs/patterns/PATTERN-SEARCH.md) — how to use `.claude/notes/` as a searchable index instead of a document

## Look Up Structure, Tools, or Decisions

**Start here if you know what you're looking for but not where it lives.**

- [Where things live](/docs/reference/STRUCTURE.md) — the directory layout and what each part owns
- [Tool profiles](/docs/reference/TOOL-PROFILES.md) — what external platforms expose and how the layer captures it
- [OpenSpec boundary](/docs/reference/OPENSPEC.md) — where spec-driven workflows fit
- [Manifest format](/docs/reference/INSTALL-MANIFEST.md) — version record structure
- [Decisions](/docs/decisions/DECISIONS.md) — why this layer was designed the way it was

## By File Type

| File | Purpose | Read When |
|---|---|---|
| `CLAUDE.md` (root) | The 8 rules true everywhere — no stack, no defaults | Before editing any code or rules |
| `.claude/commands/*.md` | How to use `/project-init`, `/decide`, etc. | Running a command and want more detail |
| `profiles/*/CLAUDE.md` | Rules true only for one stack (language, build system, etc.) | Authoring a new profile or understanding one |
| `.claude/notes/*.md` | Inventory of your project (features, routes, endpoints, etc.) | Looking up what code exists |
| `docs/adoption/*.md` | How to install and reconcile existing rules | Installing or adopting |
| `docs/operations/*.md` | Lifecycle, scanning, versioning | Understanding what happened or what's next |
| `docs/patterns/*.md` | Discipline for keeping notes searchable | Writing or editing notes |
| `docs/reference/*.md` | Structure, tools, decisions | Deep dive on how the layer works |
| `docs/decisions/*.md` | Why each design choice was made | Understanding the philosophy |
