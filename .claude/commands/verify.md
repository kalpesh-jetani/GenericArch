---
description: Walk the Definition of Done against the current working diff and report what passes, fails, and was not checkable
argument-hint: [optional: path or feature to scope to]
allowed-tools: Bash, Read, Grep, Glob
---

```bash
./Scripts/ga-step.sh after project-init      # sequence gate
```

**Exit 5 means an earlier step has not run.** Say which one, and stop — never pass `--force`, and
never work around it. Order and why: [SEQUENCE.md](../../docs/SEQUENCE.md).

Check the current change against the Definition of Done.

**Token-efficient approach:** read [DONE.md](../../docs/DONE.md) once, up front. It is *not* in
context automatically — nothing under `docs/` is. Having read it, work from it — no
grep needed. It is the source of truth for what "done" means.

Scope: `$ARGUMENTS` if given, otherwise the whole working diff.

## How to run it

0. **Read `docs/DONE.md`.** Grep `.claude/MAP.tsv` for it if the path has moved (if running under
   GenericArch) or as `docs/DONE.md` directly. Use that checklist; no grep for "what is done?"

1. **Get the diff first.** Everything below is judged against what actually changed — not the repo
   at large. Capture the changed-file list once and reuse it:

   ```bash
   git status --porcelain=v1
   BASE=$(git merge-base HEAD main 2>/dev/null || echo HEAD~1)
   git diff --stat "$BASE"...HEAD
   CHANGED=$(git diff --name-only "$BASE"...HEAD -- '*.swift' | grep -v Tests/)
   echo "$CHANGED"
   ```

2. **Grep the mechanical rules.** These decay without a check, so do them by search, not by reading.
   Run each against `$CHANGED`, not the whole repo — a pre-existing violation is not this diff's
   finding.

   Define the helper once. **Do not substitute `xargs -r`** — `-r` is a GNU extension and errors on
   macOS, and `xargs` without it runs `grep` on an empty list, which then blocks reading stdin:

   ```bash
   scan() {   # scan <regex> [path-filter]
     filter="${2:-.}"
     printf '%s\n' "$CHANGED" | grep -v '^$' | grep -E "$filter" | while IFS= read -r f; do
       [ -f "$f" ] && grep -nHE "$1" "$f"
     done
   }
   ```

   ```bash
   scan '(Text|Label|Button)\(\s*"' '/Views/'          # raw user-facing string (§2.3)
   scan '#if DEBUG' 'Packages/Features/'               # build-flag branch in a feature (§2.10)
   scan '\.alert\(|\.confirmationDialog\(|UIAlertController'   # system alert (§2.4)
   scan 'Color\(red:|Font\.system|cornerRadius: *[0-9]'        # literal design value (§2)
   scan '\btry\?|\bfatalError\('                       # swallowed error / fatalError (§2.7)
   scan '@unchecked Sendable'                          # then read each hit for its justification (§2.8)

   # resolve() outside a DI assembly (§2.6) — an exclusion, so not expressible as a scan filter.
   # grep -E has no negative lookahead; filter the file list instead.
   printf '%s\n' "$CHANGED" | grep -v 'Assembly.swift' | while IFS= read -r f; do
     [ -f "$f" ] && grep -nH 'resolve(' "$f"
   done
   ```

   ⚠ **Bound short patterns with `\b`.** `try\?` unbounded also matches `regis`**`try?`**. Any
   pattern that is a common substring needs a boundary
   ([SCAN-TRAPS.md](../../docs/SCAN-TRAPS.md)).

   A recipe that prints nothing is a pass. A recipe that errors is **not** a pass — say so.

3. **Check the content states** for any screen in the diff — a screen missing `empty` or `offline`
   is the single most common miss:

   ```bash
   for f in $(echo "$CHANGED" | grep -E 'View\.swift|Screen\.swift'); do
     printf '%-60s %s\n' "$f" "$(grep -oE '\.(idle|loading|loaded|empty|offline|error)' "$f" | sort -u | tr '\n' ' ')"
   done
   ```

   Signals, not proof — a case named is not a case rendered. Open any screen missing `empty` or
   `offline` rather than reporting from the grep alone.

4. **Check documentation currency.** Did a module doc need updating, and did it get updated in this
   diff? Did a screen/route/asset/colour/font change without its `.claude/notes/` row?

   ```bash
   git diff --name-only "$BASE"...HEAD | grep -E '^docs/modules/|^\.claude/notes/'   # what moved
   git diff --name-only "$BASE"...HEAD | grep -E '\.xcassets/|Route.*\.swift|/Views/' # what should have
   ```

   If the second prints and the first does not, that is a finding.

5. **Build only if asked.** Use `/build` for that — this command reads and greps.

## Report format

Three groups, in this order:

- **Failing** — the rule, the file:line, and the fix. Most severe first.
- **Not checkable here** — anything needing a device, a simulator, or a human eye (Dynamic Type
  XXXL, VoiceOver order, Mac window resize). **List these explicitly**; do not let them read as
  passing.
- **Passing** — one line, a count. No need to enumerate.

## Constraints

- **Do not fix anything, and never commit.** This command reports; the user decides what to act
  on and when it lands (CLAUDE.md §2.11).
- **Do not run `/sync-app-notes`.** If notes are stale, say which rows are missing and let the user
  decide — the full rescan is theirs to start (CLAUDE.md §5).
- Never report a line as passing because it "looks fine". If it wasn't checked, it goes in
  *Not checkable here*.
