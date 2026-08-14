# Scan traps — why the scan scripts are shaped the way they are

**Read this only when you are about to change a scan**, or when a scan's result surprises you. It is
deliberately *not* loaded by `/sync-app-notes`: this is evidence, and evidence costs tokens on every
run while the constraint it justifies costs one line.

Each entry records a scan that returned a **confidently wrong answer**, and what fixed it. They are
observations, not instructions — the instruction lives in the script or the command.

---

## Images — "unused asset" was wrong three times running

`Scripts/scan-unused-assets.py`. Against one app the same question produced **52, then 15, then 42**
before the method was right. Four independent failure modes:

| # | Trap | Symptom |
|---|---|---|
| 1 | References written with an extension — `"background_2.png"` | A token boundary that includes `.` never matches `background_2`. 8 live assets reported dead |
| 2 | The catalog's own `Contents.json` contains the asset name | Including `.xcassets` in the corpus makes every asset look referenced **by itself**. All 320 came back used |
| 3 | Names with spaces — `"Doo logo colored"` | Token-splitting never matches. It was referenced from three storyboards and reported dead |
| 4 | Runtime-composed names — `"asset\(i)"`, an enum returning one of nine literals | Invisible to any static scan. Unfixable, so it is disclosed rather than solved |

Traps 1–3 are fixed by a **bounded literal search** with the corpus excluding `.xcassets`. Trap 4 is
why the output is labelled *candidates*: one run listed four time-of-day greeting images as dead, and
a set of four that neatly covers a day is a composed name, not four dead files.

## Routes — `grep "case "` overcounts 4×

`grep -rn "case " --include="Route.swift"` returned **56 hits for 14 real routes**: it also matches
the `switch` cases in `hash(into:)`, `==`, and the view builder. Scope to the enum body.

## Screens — two Swift shapes hide real screens

- `struct LiveVideoPreviewScreen<ViewModel: …>: View` is not matched by `struct \w+: View`. Two route
  destinations were missing from `FEATURES.md` until the generic parameter list was allowed for.
- View controllers inherit **project** base classes, not `UIViewController`. Matching only the latter
  dropped all four tab roots — Home, Groups, Smart and Menu. Discover the base-class set first.

## Findings — the package name is not the module name

An SPM package was reported linked-but-unused. The *package* is `Charts`, the *product* is
`DGCharts`, and `import DGCharts` appears in four files. Nothing about the package name predicts the
module name — nor does the target name, the product name, or the folder name.

This generalises: **before writing any negative finding — "never used", "no consumer", "missing" —
run the positive search for the thing you claim is absent.** A negative claim is the kind people act
on destructively.

## Secrets — `.gitignore` does not apply to tracked files

A repo had `**/Configurations/*Secrets.xcconfig` ignored and `DevSecrets.xcconfig` sitting in `HEAD`,
because it was tracked before the rule existed. The ignore rule reads as protection and is not.
Check `git ls-files`, never the ignore file.

## Shell — three portability defects, all caught by running the recipe

| Written | Fails because |
|---|---|
| `xargs -r` | `-r` is a GNU extension; errors on macOS. Bare `xargs` then runs `grep` on an empty list, which blocks reading stdin |
| `grep -E '^(?!…)'` | Negative lookahead is PCRE. `grep -E` has no equivalent — filter the file list instead |
| `A && B \|\| echo msg` | Also fires when `A` is false. A note-row check written this way reports a missing row for a diff that touches no tracked code. Use an explicit `if` |

And one regex defect of the same family: `try\?` without `\b` matches `regis`**`try?`**. On one diff
that was **68 hits, every one a false positive**, against 0 for `\btry\?`. Any pattern that is a
common substring needs a boundary.

## Staleness — mtime is not a change signal

A clone, a branch switch or a `pod install` rewrites every file's mtime to checkout time, which
reports the whole tree as stale on a fresh machine — turning every run back into a full rescan.
`Scripts/notes-staleness.sh` reads **git** timestamps, plus `git status` for uncommitted work.

## Row density — measured, not estimated

Dropping link syntax, the repeated root prefix, the thrice-restated filename and the decorative
backticks: **−21% across nine notes, −47% on `FEATURES.md`**. One row went 171 → 99 bytes. The trade
is clickability inside the note, which is deliberate — the reader never opens the file, so whoever
*reports* a row renders the link.
