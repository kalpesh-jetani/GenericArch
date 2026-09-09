---
name: tool-profile
description: Use when work touches an external platform reached through a connector, an MCP server, a URL or credentials — a design reference, a ticket tracker, a CI or delivery pipeline, an observability platform, any Claude Connector — and the session needs to know what that platform actually exposes. In scope: asking whether a profile for a tool exists yet; first contact with a newly connected or unconfigured one, including working out what is knowable from a pasted URL alone and what the user must hand over instead; capturing observed attributes, units and connectivity after a real response; and correcting, extending or retiring what a profile claims once it turns out wrong or stale. Use it even when the user only pastes a URL and never says profile. Not for reading published API documentation to decide whether to adopt something, and not for anything inside this repo.
---

# External platform profile

**If the resource is inside this repo, stop and say so** — a local file, a package, `git`, the
simulator and the repo's own `Scripts/` are not platforms, and none of them earns a profile.
Recording *why* a vendor was adopted is `/learn`'s job, not this one.

This file is the decision procedure. The detail lives outside it so it is not re-read on every
fire — go to the one you need:

| Read | When |
|---|---|
| [`references/generated-skills-note.md`](references/generated-skills-note.md) | **First, always** — the registry of platforms already profiled |
| [`.claude/tools/<tool>.md`](../../tools/) | The registry named one — it holds that platform's attributes and connectivity |
| [TOOL-PROFILES.md](../../../docs/TOOL-PROFILES.md) | Writing, extending or retiring a profile: the schema, the failure thresholds, the removal rule |
| [`.claude/tools/CLAUDE.md`](../../tools/CLAUDE.md) | Editing anything in that directory |

One profile per platform, so the per-platform files *are* the variant layer — a new platform adds
a file, never a new skill.

## 0. Find it first — never generate on a hit

```bash
./Scripts/ga-tool-note.sh --find <tool>        # 0=hit 1=miss or stale
grep -i <tool> .claude/skills/tool-profile/references/generated-skills-note.md
```

`.claude/SCRIPTS.tsv` gives the script's inputs, outputs and exit codes; call it and rely on the
result rather than reading its body. Never run `./Scripts/check.sh` — it compiles.

| Result | What to do |
|---|---|
| Exit 0 | Read the profile it names, use it as recorded, **stop.** Nothing is written |
| Exit 1, ledger says `stale` | Treat as a miss — re-observe and re-enter step 3 |
| Exit 1, ledger says `retired` | **Do not resurrect.** Say it was retired, and why. Stop |
| Exit 1, no row | Continue to step 1 |

## 1. Is this in scope?

The test: **the resource lives outside this repo and is reached through a connector, a URL, or
credentials.** The full table is in the reference doc. In, in short: design tools and design
references, mockup and layout references, ticket trackers, CI/CD and delivery platforms,
observability systems, any Claude Connector.

## 2. Only after a successful use

A call that failed or was refused teaches nothing except that it failed. An unauthenticated
connector is a **connectivity** fact to record on an existing profile — not a reason to open a
new one, and never a reason to describe a platform that was never reached.

## 3. Same platform, different input or output? Extend

One profile per platform, always.

```bash
./Scripts/ga-tool-note.sh <tool> --extend      # appends rows and a recipe mode
```

A second file for the same platform means two records of one thing, and one of them will rot.

## 4. Fill the fields from observation only

Every cell comes from a response actually received in this session. Anything not seen is
written `not observed` and left there — not inferred from the vendor's API, not carried over
from a similar platform, not completed because the value looks obvious.

Four honest rows beat twelve plausible ones: a wrong unit is worse than a missing one, because
a wrong one is trusted.

A shape read off the connector's tool definition is worth recording, but mark `Accessible` as
`not observed` — the profile then shows it as `contract`, meaning *we know the shape, we never
asked the platform*. `--apply` counts only **retrieved** rows, so contracts alone cannot stand
in for having reached the platform.

## 5. Draft, show, wait

```bash
./Scripts/ga-tool-note.sh <tool>               # dry run — writes nothing
./Scripts/ga-tool-note.sh <tool> --apply       # profile, recipe, ledger, all four index rows
```

Show both files and **wait for approval.** A profile and a registered script are things every
future session is told to call.

## 6. When a recorded recipe fails

Read the report under `.genericarch/failures/`, **not** the script body.

```bash
./Scripts/ga-tool-note.sh <tool> --fail --cause "<what was wrong>"
```

One failure flags it `suspect`; two make it `stale`, which sends step 0 back to step 3; three
means proposing retirement.

## 7. Retiring one

```bash
./Scripts/ga-tool-note.sh <tool> --retire --reason "<why>"
```

Never `rm`. This moves the file to `.genericarch/safetodelete/` and tombstones it so no later
run re-creates it (CLAUDE.md §2.15).

## Before finishing

- [ ] `--find` was run **first**, and a hit stopped the work
- [ ] Every cell is observed, or says `not observed` — nothing inferred
- [ ] `Observed` carries a real date on every filled row
- [ ] Connectivity records both branches — wired, and what is reachable unwired
- [ ] All four index rows landed: `SCRIPTS.tsv`, `MAP.tsv`, `INDEX.md`, the registry note
- [ ] No credentials, tokens or response bodies anywhere in the profile (CLAUDE.md §8)
- [ ] No meta-commentary in the profile or the script — that went to `.claude/log.md`:
      `./Scripts/ga-log.sh --decided "…" --why "…" --how "…"`
- [ ] `./Scripts/claude-utils/register-scripts.sh --check` exits 0
- [ ] `./Scripts/ga-reseal.sh --apply` if installed files were rewritten
