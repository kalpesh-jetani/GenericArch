---
name: openspec-upstream-moves-fast
description: OpenSpec ships often and is maintained by a group — five plan-relevant facts changed between v1.6 and v1.12; this is the list to re-verify, not re-derive
metadata:
  type: project
---

Upstream OpenSpec (`https://github.com/Fission-AI/openspec`) releases frequently and is maintained
by a group of people, so **the bridge's assumptions expire**. Verified against **v1.12.0** on
2026-09-07; five things had already changed since v1.6, four of them load-bearing:

| Assumption | What it was | What it became by v1.12 |
|---|---|---|
| `explore` writes nothing | true | still true — v1.11 added a *confirmation guardrail*, not artifacts. So no injection ever reaches it |
| `context:` accepts a sequence or file include | unknown | **string only**, no documented cap. The single-key ownership problem is permanent |
| We must add `Bash(openspec:*)` to `.claude/settings.json` | true | **false** — v1.6 puts it in every generated skill and command's frontmatter |
| `tasks` are plain checkboxes | true | v1.10 requires each to state how completion is verified; v1.8 counts indented sub-tasks |
| Reverse direction must parse their markdown | true | **false** — v1.11/v1.12 added `status --all`, `show --diff`, `validate --report findings`, all with `--json` |

**Why:** the install is deliberately unpinned (`docs/DECISIONS.md` — *OpenSpec install*), so a
session months from now meets a different tool than this one did. Re-deriving these five from their
docs costs an hour; re-checking them against this list costs minutes. The decision to stay unpinned
is recorded — this is the operational consequence of it.

**How to apply:** when `./Scripts/openspec-sync.sh` reports `SHAPE-UNRECOGNISED`, when
`--check` fails right after an upstream update, or before changing the bridge — walk this table
first, then update it with what you found and the version you found it at. Never copy their docs
into this repo to avoid the re-check; that is the trade `docs/OPENSPEC.md` takes
deliberately, and a copy of a file other people revise is what rots.
