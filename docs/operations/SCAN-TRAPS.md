# Scan traps — why a scan is shaped the way it is

**Read this only when you are about to change a scan**, or when a scan's result surprises you. It is
deliberately *not* loaded by `/sync-app-notes`: this is evidence, and evidence costs tokens on every
run while the constraint it justifies costs one line.

Scans are the active stack profile's — which files feed which inventory, and how, is declared per
stack. What follows is **not** stack-specific: it is the discipline any scan must follow, learned
from scans that returned a **confidently wrong answer**. Observations, not instructions — the
instruction lives in the scan the profile declares.

---

## The rule: verify a negative before you write it

**Before writing any negative finding — "never used", "no consumer", "missing", "dead" — run the
positive search for the thing you claim is absent.** A negative claim is the kind people act on
destructively; an "unused, safe to delete" list that is half wrong deletes live code.

Three ways a negative goes wrong, on any stack:

- **A reference the scan cannot see.** A name built at runtime, a generated symbol, a name with a
  separator the tokenizer splits on — the thing is live and the scan reports it dead. When a scan
  cannot see every reference, its output is **candidates**, never a verdict, and it says so.
- **The scan matching its own source.** A bare recursive grep for a literal, run from inside the
  tree it scans, matches the line it is written on. Route every probe through a filtered helper that
  admits only the files it means to search.
- **Counting the wrong unit.** A dependency's package name is not its module name; one remote
  dependency carries several markers. Count the unit the question is about, or read the resolved
  manifest.

## A probe that finds nothing must not read as a probe that found an answer

A probe assuming the project sits at the repo root returns nothing when it sits one directory down —
and a scan that then reports its *fallback* as a *finding* is silently wrong. Derive the roots,
prune dependency and build directories (a vendored dependency must not answer questions about this
repo), and make "found nothing" distinguishable from "found this".

## Shell — three portability defects, all caught by running the recipe

| Written | Fails because |
|---|---|
| `xargs -r` | `-r` is a GNU extension; not available on all systems. Bare `xargs` then runs its command on an empty list, which blocks reading stdin |
| `grep -E '^(?!…)'` | Negative lookahead is PCRE. `grep -E` has no equivalent — filter the file list instead |
| `A && B \|\| echo msg` | Also fires when `A` is false. A check written this way reports a finding for input that has none. Use an explicit `if` |

And one regex defect of the same family: an unbounded short pattern matches inside longer words. Any
pattern that is a common substring needs a `\b` boundary — and count the false positives before
trusting the number.

## `.gitignore` does not apply to tracked files

A secret ignored by pattern can still sit in `HEAD` because it was tracked before the rule existed.
The ignore rule reads as protection and is not. Check `git ls-files`, never the ignore file.

## Staleness — mtime is not a change signal

A clone or a branch switch rewrites every file's mtime to checkout time, which reports the whole tree
as stale on a fresh machine — turning every run back into a full rescan. `Scripts/notes-staleness.sh`
reads **git** timestamps, plus `git status` for uncommitted work.

## Row density — measured, not estimated

Dropping link syntax, the repeated root prefix, the restated filename and decorative backticks
measured **−21% across the inventories, −47% on the largest**. One row went 171 → 99 bytes. The trade
is clickability inside the note, which is deliberate — the reader never opens the file, so whoever
*reports* a row renders the link.
