# Adoption Guide

Installing GenericArch into an existing project.

## Quick Start

```bash
# 1. Get the layer
curl -fsSLO https://raw.githubusercontent.com/kalpesh-jetani/GenericArch/HEAD/bootstrap.sh
less bootstrap.sh
bash bootstrap.sh --apply

# 2. Declare your stack
# Run /declare-profile in Claude Code — it asks four questions, all optional

# 3. Initialize
# Run /project-init in Claude Code (or read the next section for what it does)

# 4. Index your code
# Run /sync-app-notes

# Then ready: use /build, /verify, /find, /decide, /learn, etc.
```

## The Three Steps

### 1. Install

```bash
/path/to/GenericArch/install.sh /path/to/YourRepo
```

**What it does:**
- Checks your machine (SHA-256 tool available)
- Checks your repo (is it a git repo?)
- Lists what will be added (skills, commands, notes scaffolds)
- Waits for your yes
- Writes `.genericarch/`, `.claude/`, `profiles/`, and lifecycle tracking

**What it preserves:**
- Your `CLAUDE.md` (or creates one empty if you don't have it)
- Your existing `.claude/` files (skills, commands)
- Your codebase (nothing is edited)

**Next step:** Run `/declare-profile`, then `/project-init`

See: [SHARING.md](/docs/adoption/SHARING.md) — what travels, what doesn't, why.

### 2. Project-Init

In Claude Code, run `/project-init`.

**What it does:**
- Reads your `CLAUDE.md` in full
- Identifies conflicts (build system, concurrency, patterns)
- Asks you per conflict: "keep yours (default), take mine, or skip?"
- Records your choices in `docs/decisions/DECISIONS.md`
- Sets the active stack profile in `.genericarch/PROFILE.tsv`

**Result:** The layer knows what you're built with and can now run stack-specific commands.

See: [ADOPTION.md](/docs/adoption/ADOPTION.md) — how conflicts are resolved.

### 3. Sync App Notes

In Claude Code, run `/sync-app-notes`.

**What it does:**
- Scans your code (based on the active profile)
- Fills in `.claude/notes/` with your features, routes, endpoints, etc.
- Respects edits you've made between the markers

**Result:** You have a searchable index of your codebase structure.

**Then ready:** Skills, commands, and searches now work.

## Stack Profiles

A **stack profile** declares what your project is built with: language, build system, patterns.

**Nothing ships — not even an example.** The layer recognises no ecosystem, so there is no
reference profile to copy and no built-in list of build markers. `/declare-profile` asks you
instead, and records the answers in `.genericarch/PROFILE.tsv`.

A `profiles/<platform>-<language>/` directory is **optional**, and only worth authoring once you
want more than the four answers:

| File | Holds |
|---|---|
| `profile.tsv` | `key<TAB>value` rows — toolchain commands, source globs, note taxonomy, and `detect_marker_<path>` rows naming the files that prove this stack |
| `CLAUDE.md` | rules true only for your stack |
| `scaffold/` | templates for files the layer generates |

Once the `detect_marker_*` files all exist, `./Scripts/ga-profile.sh --extract` recognises the
profile and reads its declared values — so the inference becomes **your** recorded rule rather
than an assumption baked into the layer.

See: [profiles/CLAUDE.md](/profiles/CLAUDE.md)

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Install refused: "not a git repo" | Initialize git first: `git init && git add . && git commit -m "init"` |
| A command says "no profile declared" | Run `/declare-profile` — it records the stack, and needs no `profiles/` directory |
| `/sync-app-notes` produces empty notes | Check that your profile's `build_command` actually runs and produces output |
| A command says "Stack — no stack profile declared" | Run `/declare-profile` first — it sets `.genericarch/PROFILE.tsv` |

## What's Next?

- [Lifecycle steps](/docs/operations/SEQUENCE.md) — what each `/` command does and when to run it
- [Where things live](/docs/reference/STRUCTURE.md) — directory layout and ownership
- [Making notes searchable](/docs/patterns/PATTERN-SEARCH.md) — how to keep `.claude/notes/` efficient
