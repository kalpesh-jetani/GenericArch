---
name: claude-md-section-numbers-are-load-bearing
description: CLAUDE.md's §N headings and §2 rule numbers are referenced ~380 times repo-wide — bodies may shrink, numbering may never move
metadata:
  type: project
---

Roughly 380 references to `§0`–`§12`, `§1.1`, `§2.7`, `§4.2` and the like are spread across `docs/`,
`.claude/skills/`, `.claude/commands/`, `.claude/SCRIPTS.tsv` and the `Scripts/` headers. The
most-cited are `§1` (30), `§2.12` (25), `§0` (25), `§2` (23), `§4.2` (20) and `§2.7` (20).

No script parses CLAUDE.md's structure — `check.sh` enforces the §2 rules against Swift source,
`survey-repo.sh` only tests the file's existence, and `05-apply-claude-edits.sh` edits it without
depending on a fixed heading set.

**Why:** it makes the two kinds of CLAUDE.md edit asymmetric in cost. Rewriting a section's *body*
touches one file. Deleting, renumbering or reordering a heading silently breaks citations in ~380
places, and nothing in `check.sh` catches it.

**How to apply:** when compressing or restructuring CLAUDE.md, keep every heading and every §2 rule
number exactly where it is — to move a section's content out to `docs/`, leave the heading in place
with a one-line pointer under it so the citation still resolves. Verify with
`diff <(git show HEAD:CLAUDE.md | grep -E '^#{1,3} ') <(grep -E '^#{1,3} ' CLAUDE.md)` before
finishing. Recount references with
`grep -rhoE '§ ?[0-9]+(\.[0-9]+)?' --include='*.md' --include='*.tsv' --include='*.sh' .`

Two linters gate the file and neither compiles, so both are safe to run:
`Scripts/claude-utils/claude-lint.sh CLAUDE.md` (100-char default line limit) and
`Scripts/claude-utils/validate-claude-links.sh CLAUDE.md`. Run the link check from the repo root —
relative links do not resolve from a scratchpad copy.
