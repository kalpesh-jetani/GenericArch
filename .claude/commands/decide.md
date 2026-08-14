---
description: Record a settled architecture decision in docs/DECISIONS.md in the right section and format
argument-hint: <scope> — <decision> [— why]
allowed-tools: Read, Edit, Grep
---

Target file: @docs/DECISIONS.md

Record the decision described by: `$ARGUMENTS`

## Steps

1. **Check it isn't already answered.** Search before reading, then read the section you hit:

   ```bash
   grep -niE "<scope-keyword>" docs/DECISIONS.md
   grep -n "^## " docs/DECISIONS.md          # the four sections and where they start
   ```

   If a row covers this scope, say so and stop — re-recording a decision under slightly different
   words is how a log stops being trusted.

2. **Pick the right section.** They are not interchangeable:

   | Section | For |
   |---|---|
   | **Settled** | A choice now in force. One row: scope · decision · why (one clause) · where the detail lives |
   | **Do not re-propose** | An option rejected, with a pointer to the reasoning |
   | **Open** | A question not yet answered — needs a `Blocks` value |
   | **Per feature** | A §0 answer scoped to one feature: date, feature, presentation, persistence, caching |

3. **Write it in the existing table format.** Match the surrounding rows exactly — no new columns,
   no prose paragraphs. The `Why` is **one clause**, not a paragraph: the log says *what* was decided
   and points at the detail; it does not restate it.

4. **Point `Detail` at the real home** — a CLAUDE.md section number, or a `docs/modules/*.md` file.
   If the detail doesn't exist anywhere yet, say so: the decision may need a module doc before it
   needs a log row.

5. **If this decision supersedes an existing one**, move the old entry to *Do not re-propose* with a
   note that it was tried and reversed. Do not delete it — the value of the log is preventing
   re-litigation.

## Constraints

- **Never invent the "why".** If the reasoning wasn't given and isn't in the conversation, ask for
  it. A row with a plausible-sounding but fabricated rationale is worse than no row, because it will
  be cited later.
- Don't record decisions still under discussion. Settled means settled.
- **Never edit CLAUDE.md here** — not even when the decision plainly changes a rule, and not even
  when you are certain. Say which section would change, show the exact text, and wait for an
  explicit yes ([STRUCTURE.md](../../docs/STRUCTURE.md)). CLAUDE.md loads into every session, so a
  change there is the user's call, never a side effect of recording a decision.
- No meta notes in the log either: the `Why` is one clause. History goes in *Do not re-propose*.
