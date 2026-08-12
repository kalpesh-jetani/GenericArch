---
description: Walk the Definition of Done against the current working diff and report what passes, fails, and was not checkable
argument-hint: [optional: path or feature to scope to]
allowed-tools: Bash, Read, Grep, Glob
---

Check the current change against the Definition of Done: @docs/DONE.md

Scope: `$ARGUMENTS` if given, otherwise the whole working diff.

## How to run it

1. **Get the diff first.** `git diff` and `git status` (or `git diff <base>...HEAD` on a branch).
   Everything below is judged against what actually changed — not the repo at large.

2. **Grep the mechanical rules.** These are the ones that decay without a check, so do them by
   search, not by reading:

   | Rule | Search |
   |---|---|
   | Raw user-facing string | string literals inside `Views/` |
   | `#if DEBUG` in a feature | `Packages/Features/` |
   | `resolve` outside its allowed sites | feature types, excluding `DI/*Assembly.swift` |
   | System alert | `.alert(`, `.confirmationDialog(` |
   | Literal design value | `Color(`, `Font.system`, numeric padding/radius outside DesignSystem |
   | Force-unwrap / `try?` / `fatalError` | changed Swift files, excluding tests |
   | Unjustified `unchecked Sendable` escape hatch | changed Swift files — the marker with no adjacent comment |

3. **Check the content states** for any screen in the diff — a screen missing `empty` or `offline`
   is the single most common miss.

4. **Check documentation currency**: did a module `.md` need updating, and did it get updated in
   this diff? Did a screen/route/asset/color/font change without its `.claude/notes/` row?

5. **Build only if asked.** Use `/build` for that — this command reads and greps.

## Report format

Three groups, in this order:

- **Failing** — the rule, the file:line, and the fix. Most severe first.
- **Not checkable here** — anything needing a device, a simulator, or a human eye (Dynamic Type
  XXXL, VoiceOver order, Mac window resize). **List these explicitly**; do not let them read as
  passing.
- **Passing** — one line, a count. No need to enumerate.

## Constraints

- **Do not fix anything.** This command reports. The user decides what to act on.
- **Do not run `sync-app-notes`.** If notes are stale, say which rows are missing and let the user
  decide — the full rescan needs explicit approval (CLAUDE.md §5).
- Never report a line as passing because it "looks fine". If it wasn't checked, it goes in
  *Not checkable here*.
