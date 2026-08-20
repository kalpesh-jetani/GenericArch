# Build process

- **When to read this:** you are about to build, test or archive, or a build failed and you need to
  know whose job the next step is. **Not** session reading — nothing here is needed to write code.
- **Owns:** the ordered process and who performs each step.
- **Does not own:** which scheme maps to which configuration — that is
  [.claude/notes/SCHEMES.md](../.claude/notes/SCHEMES.md), generated from the project. The command's
  own contract is [.claude/commands/build.md](../.claude/commands/build.md).

---

## The rule that shapes everything below

**Claude never builds, runs or tests** (CLAUDE.md §2.12) — including `./Scripts/check.sh`, whose
iOS-floor step compiles. It says what to run; you run it. Reading, grepping and editing are free;
minutes of your machine are not.

`/build` is the single sanctioned exception, because typing it *is* the instruction.

## Choosing a stage

| Stage | Configuration | Build it to | Never |
|---|---|---|---|
| **DEV** | Debug | Work. Unoptimized, assertions live | Ship it |
| **TEST** | Test | Hand to QA. Release-like, testability on | Assume it behaves like PROD |
| **BETA** | Beta | External testers, notarized Mac builds | Skip the version bump |
| **PROD** | Release | Release | Archive from a dirty tree |

`Test`, `Beta` and `Release` are all **release-like** — optimized, assertions compiled out. Only DEV
is unoptimized. A QA build compiled `-Onone` has tested nothing.

## The process

```bash
/build                      # DEV, iOS, build — the defaults
/build TEST ios test        # stage · platform · action
/build PROD both archive    # archive is valid for BETA and PROD only
```

1. **Resolve the stage** from the table above. If the request does not name one, DEV is assumed and
   said out loud.
2. **Build.** Warnings are surfaced even when the build succeeds; the actual compiler output is
   quoted, never paraphrased.
3. **On failure**, the compiler output is the finding. Nothing is disabled to make it pass — no
   `-warnings-as-errors=NO`, no silenced warning. Fix it or report it.
4. **A package has no scheme.** Build it directly; the commands live in
   [build.md](../.claude/commands/build.md).

## Before an archive

- The tree is clean and the version bumped — three numbers that are not interchangeable:
  [DELIVERY.md](DELIVERY.md) *Versioning*.
- Signing for TEST/BETA/PROD is **manual, via CI credentials**. A local archive of those may fail on
  signing; that is expected, not a bug to fix here.
- An extracted package with a `swift package edit` override active will not reflect the pinned
  version. Say so before building rather than after.

## What happens after a successful archive

That is a different process, with different gates: [DEPLOYMENT-PROCESS.md](DEPLOYMENT-PROCESS.md).
