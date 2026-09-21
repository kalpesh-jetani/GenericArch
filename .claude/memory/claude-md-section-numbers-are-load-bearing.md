---
name: claude-md-section-numbers-are-load-bearing
description: CLAUDE.md's §N headings and §2 rule numbers are referenced ~190 times repo-wide — bodies may shrink, numbering may never move
metadata:
  type: project
---

Roughly 190 references to `§N` citations — `§0`–`§4` and the `§2.1`–`§2.8` rule numbers — are spread
across `docs/`, `.claude/skills/`, `.claude/commands/`, `.claude/SCRIPTS.tsv` and the `Scripts/`
headers. The most-cited are `§2` (38), `§0` (30), `§3` (21) and `§2.8` (21).

No script parses CLAUDE.md's structure — `check.sh` dispatches the active profile's checks against
the project's source, and `05-apply-claude-edits.sh` edits CLAUDE.md without depending on a fixed
heading set.

**Why:** it makes the two kinds of CLAUDE.md edit asymmetric in cost. Rewriting a section's *body*
touches one file. Deleting, renumbering or reordering a heading silently breaks citations in ~190
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
