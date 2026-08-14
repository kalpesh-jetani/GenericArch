---
description: Rebuild the nine inventories in .claude/notes/ from a filesystem scan — features and screens, navigation and routes, API map, image assets, colour tokens, fonts and registration, schemes, project targets. Reports the gaps it finds.
argument-hint: "[optional: a note name, e.g. FONTS]"
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

Rebuild the living inventories in `.claude/notes/` from what is actually on disk.

Scope: `$ARGUMENTS` if a note is named, otherwise all nine.

> **This is a command, not a skill, and that is the safety mechanism.** A full rescan rewrites nine
> files wholesale; run against a half-finished tree it replaces correct rows with incomplete ones —
> worse than a stale note, because it looks current. As a command it can only run when you type it,
> so there is no path by which it fires as a side effect of another task.
>
> **Targeted edits are the normal case and do not belong here.** Adding one row to `FEATURES.md`
> because you added one screen is part of that change (CLAUDE.md §5) — edit the file directly.

**Run the command as written; do not improvise a substitute.** Each `⚠` marks a constraint that a
naive rewrite breaks. The evidence behind them is in
[SCAN-TRAPS.md](../../docs/SCAN-TRAPS.md) — read it before changing a scan, not before running one.

---

## S0. Before rewriting anything

```bash
git status --porcelain=v1 && git branch --show-current
```

A dirty tree is the case this command's warning exists for. If it prints anything, say so and let
the user decide.

### Scan what moved, not everything

**Default scope is the stale set, not all nine.** Most syncs follow a change that touched two or
three areas; rescanning the other six spends tokens to rewrite files with identical content.

Set the source root first — every scan in this command uses it. In a greenfield repo it is
`Packages`; in an adopted one it is whatever the notes' `Built from:` lines name:

```bash
SRC=Packages          # adopted repo: e.g. SRC=App/MyApp
./Scripts/notes-staleness.sh "$SRC"
```

It prints one row per note — `current`, `STALE` with a count and sample, or `NEVER`. The spread is
the scope decision: on one repo a two-week baseline gave 88 changed files for `FEATURES` and 3 for
`ASSETS-IMAGES`.

It reads **git** timestamps, not mtime, and its baseline is each note's `- **Last synced:**` line —
which is why S5.3 requires you to set it. Why not mtime:
[SCAN-TRAPS.md](../../docs/SCAN-TRAPS.md).

`$ARGUMENTS` overrides the staleness result: a named note is scanned whether or not it is stale, and
if the user asks for everything, do everything. Report what you skipped either way.

```bash
ls -la .claude/notes/
```

Then **state what you are about to scan and what it will replace, and wait for confirmation.**
Typing the command asks for a sync; it does not pre-approve discarding work in progress. Lead with
the staleness table, then the sizes for the notes you intend to touch — `FEATURES: 88 changed files,
115 screens` is the useful form, not "the notes".

Use `AskUserQuestion` for the confirmation when scope is genuinely open (the stale set vs all nine);
plain text is enough when the user named a note in `$ARGUMENTS` or only one note is stale.

## S1. What each note is built from

**The note's own `Built from:` line wins over this table.** Adoption rewrites those lines
([ADOPTION.md](../../docs/ADOPTION.md)), and in an adopted repo none of the greenfield paths below
exist. Read the note's header first; this table is the default for a fresh GenericArch repo.

| Note | Scan | Key output |
|---|---|---|
| `FEATURES.md` | `Packages/Features/*/Sources/**/Views/`, view models | features → screens → routes, states, **file paths** |
| `NAVIGATION.md` | `Route` enum, shell `navigationDestination`, deep-link parser | route inventory, entry points, flow, deep links, **file paths** |
| `API-MAP.md` | router enum + `callAPI(path:method:)` call sites | path → method → screen → controller, **file paths** |
| `ASSETS-IMAGES.md` | `**/*.xcassets/**/*.imageset` | group, name, rendering mode, dark variant, owner |
| `ASSETS-COLORS.md` | `**/*.xcassets/**/*.colorset/Contents.json` | token, **light + dark hex** |
| `FONTS.md` | `*.otf`/`*.ttf`, `Info.plist`, `Font.custom` call sites | family, PostScript names, **registration path**, tokens |
| `SCHEMES.md` | `*.xcconfig`, scheme list, `Info.plist` substitutions | DEV/TEST/BETA/PROD → config, bundle ID, base URL |
| `PROJECT.md` | `project.pbxproj`, `*.entitlements`, `Info.plist`, package links | targets, deployment targets, capabilities, links |
| `STYLE-GUIDE.md` | token declarations in `DesignSystem/Tokens/`, components + their `#Preview` blocks | spacing, radius, elevation, motion, type scale, component variants |

## S2. The scans

`$SRC` was set in S0. Run only the scans for the notes S0 marked stale.

### Colours

```bash
find . -type d -name "*.colorset" -not -path "*/Pods/*" -not -path "*/build/*" | wc -l
```

Normalise to `#RRGGBB` uppercase; record **Any/Light** and **Dark** separately:

```bash
python3 Scripts/scan-colors.py "$SRC"
```

A colorset with one appearance is a finding, not a blank cell.

### Images, and deciding an asset is unused

```bash
find . -type d -name "*.imageset" -not -path "*/Pods/*" -not -path "*/build/*" | wc -l
```

⚠ Four failure modes make a naive name search wrong — [SCAN-TRAPS.md#images](../../docs/SCAN-TRAPS.md):

```bash
python3 Scripts/scan-unused-assets.py "$SRC"
```

> **An "unused asset" list is a deletion proposal.** Label every row a **candidate**, state the
> method's blind spot in the note, and never present it as a verdict. Runtime-composed names are
> invisible to this scan.

### Fonts

```bash
find . \( -name "*.otf" -o -name "*.ttf" \) -not -path "*/Pods/*" -not -path "*/build/*"
grep -rn "UIAppFonts\|ATSApplicationFontsPath" --include="*.plist" . | grep -v /build/
grep -rn "Font.custom\|UIFont(name:" --include="*.swift" . | grep -v Pods | wc -l
```

⚠ **Read PostScript names from the file, never the filename** — a mismatch fails silently at runtime:

```bash
python3 Scripts/scan-fonts.py "$SRC"
```

### Routes

⚠ `grep "case "` overcounts ~4× — it matches `hash(into:)`, `==` and the view builder too. Scope to
the enum body:

```bash
# declarations only: stop at the first closing brace after the enum
awk '/^enum .*Route/,/^}/' $(fd -g 'Route*.swift' . 2>/dev/null || find . -name "Route*.swift" -not -path "*/Pods/*") \
  | grep -E '^\s{4}case ' 
# the destination for each case — from the shell's switch
grep -rn "navigationDestination" -A40 App | grep -E "case \.|Assembly"
# who pushes each route
grep -rn "\.push(\.\|startRoute:" --include="*.swift" . | grep -v Pods
```

### Screens

⚠ Two Swift shapes defeat the obvious regexes and silently drop screens:

```bash
# Generic screens: `struct LiveVideoPreviewScreen<ViewModel: …>: View` is NOT matched
# by `struct \w+: View`. Two route destinations went missing before this was fixed.
grep -rnE 'struct\s+\w+\s*(<[^>]*>)?\s*:\s*View\b' --include="*.swift" . | grep -v Pods

# View controllers usually inherit a PROJECT base class, not UIViewController.
# Discover the real set first, then match on it — otherwise the four tab roots vanish.
grep -rhoE "class [A-Za-z0-9_]*ViewController *: *[A-Za-z0-9_]*" --include="*.swift" . \
  | grep -v Pods | sed 's/.*: *//' | sort | uniq -c | sort -rn
```

### API map

```bash
python3 Scripts/scan-api-map.py "$SRC" "$SRC/Resources/en.lproj/Localizable.strings" --markdown
```

Drop the output under `## Endpoints` in [API-MAP.md](../notes/API-MAP.md). Without `--markdown` it
emits JSON, which is what you want when you need the `never_called` list for the Gaps table.

The script **discovers the router from the call sites, not from its name.** That matters: one real
repo has an `APIRouter.swift` that still compiles and is called exactly once, while every live call
goes through a differently-named enum. Trusting the filename would have documented the dead one.

If the project's API entry point is not `callAPI(path:method:)`, change `CALL_FN` at the top of the
script rather than hand-rolling a scan.

### Schemes, project, style

```bash
find . -name "*.xcconfig" -not -path "*/Pods/*" -not -path "*/build/*"
grep -rn "IPHONEOS_DEPLOYMENT_TARGET\|PRODUCT_BUNDLE_IDENTIFIER\|CODE_SIGN_ENTITLEMENTS" \
  *.xcodeproj/project.pbxproj | sort -u
grep -n "UsageDescription\|UIBackgroundModes\|UIUserInterfaceStyle" **/Info.plist
grep -rn "static let \(spacing\|radius\|cornerRadius\|duration\|elevation\)" --include="*.swift" . | grep -v Pods
grep -rc "accessibilityReduceMotion" --include="*.swift" . | grep -v ':0' | wc -l
```

⚠ **Check secrets with `git ls-files`, not `.gitignore`** — an ignore rule has no effect on a file
tracked before the rule existed:

```bash
git ls-files | grep -i "secret\|\.env"        # tracked despite any ignore rule
git check-ignore -v $(find . -name "*Secrets*") 2>/dev/null
```

## S3. Paths are the point — emit them, verified

`FEATURES.md`, `NAVIGATION.md` and `API-MAP.md` are indexes: someone should `grep` a screen, a route
or an endpoint there and get the file. So every row carries a **repo-relative path**, and every
graph node carries a `click` target. Note→note links use the same repo-relative form.

Verify the whole set before you finish — a wrong path is worse than a missing one:

```bash
python3 Scripts/check-note-links.py
```

### The row format is dense on purpose

A grep hit returns the row's **bytes**. Link syntax, a repeated root prefix and a thrice-restated
filename are overhead for a lookup that never opens the file (measured: −21% overall, −47% on
`FEATURES.md`).

```
before (171)  | `SmartLockHomeView` | SwiftUI | [SmartLockHomeView.swift](App/MyApp/Features/SmartLock/Home/SmartLockHomeView.swift) | `loading`, `empty`, `error` |
after   (99)  | `SmartLockHomeView` | SwiftUI | Features/SmartLock/Home/ | loading, empty, error |
```

Four transformations, in order:

1. **No markdown links in a row** — write the bare path. The link syntax duplicates the basename and
   serves a reader who, by §S6, never opens the file. Whoever *reports* a row renders the link.
2. **Declare the root once in the header**, then write paths relative to it:
   `- **Root:** \`App/MyApp/\`` — that prefix appeared 175 times across one app's notes.
3. **Drop the filename when the key derives it.** State the convention in the header
   (`file = <dir>/<Key>.swift`) and the row carries the directory. Only spell the filename when it
   does *not* follow from the key.
4. **Backticks on the searchable key only.** They earn their two bytes on the column people grep for
   and nowhere else.

Rows stay one line ending in `|` (§S6) — density must never come from wrapping.

Four rules, because a wrong or unexplained path is worse than a missing one:

1. **Never emit an *unexplained* path.** Every path needs a clause saying what is there — but the
   clause can be a neighbouring column (`Kind`, `States`), not necessarily prose. What is forbidden
   is a path a reader cannot act on without opening it, not a path without link syntax. In mermaid,
   the clause is the third `click` argument (the tooltip). In shell recipes, a `#` comment on the
   same line.
2. **Verify every path resolves** before writing it — the script above. If the file isn't there, the
   row goes in `Gaps`; never emit a guess.
3. **A `:line` suffix is optional and only for a definition site.** Never put line numbers in a
   generated table — they rot on the first insertion. Prose may carry one.
4. **Keep every `click` line in the mermaid block.** They are what make the diagram findable by
   `grep` — a diagram without them is a picture, not an index.

## S4. Findings are claims — verify them like paths

Rule S3.2 protects paths. **Findings need the same discipline and are easier to get wrong**, because
a negative claim ("never used", "no consumer", "missing") is the kind people act on destructively.

> **Before writing any negative finding, run the positive search for the thing you claim is absent,
> and say which search you ran.**

The package name is not the module name — nor is the target name, the product name, or the folder
name. Worked example: [SCAN-TRAPS.md](../../docs/SCAN-TRAPS.md).

## S5. Rules for every note

1. **Preserve structure and prose.** Replace table bodies only — the guidance in those files is
   hand-written and must survive a regeneration. Prefer `Edit` on the table body over `Write` on the
   file; reach for `Write` only when the whole body is generated, and re-read the header first.
2. **Delete the scaffold marker on the first successful sync.** The `> Empty until … —
   /sync-app-notes populates it.` line is scaffolding, not prose. Leaving it on a populated note
   makes the note lie about itself. Rule 1 does not protect it.
3. **Set `Last synced:` to today's actual date**, in every note you touched **and no others**. This
   is not bookkeeping — it is the baseline the next run's staleness check reads (S0). Stamping a
   note you did not rescan hides real drift; leaving one unstamped after a rescan makes the next run
   redo it.
4. **Keep commented-out example rows** while a table is empty; delete an example only when real rows
   replace it.
5. **Never drop a row silently.** A removed asset or route is a deletion — take it out in the same
   change that removes the code, so the diff shows both.
6. **Fill the `Gaps` table rather than omitting problems.** An inventory that hides a defect is worse
   than no inventory. Close each note with a **Not checked:** paragraph naming what the scan could
   not see.
7. **Group long tables by folder, with the count in the heading** (`### \`Images/Device/\` — 28
   assets`). Never truncate without saying so in the same sentence.
8. **A note whose `Built from:` source does not exist records the absence.** Do not synthesise. If
   there is no `DesignSystem/Tokens/`, `STYLE-GUIDE.md` says so and lists the literals it found as
   evidence — a token registry nothing references is worse than an empty one.
9. **Never edit CLAUDE.md.** If a scan suggests a rule, report it and let the user decide — CLAUDE.md
   is approval-gated ([STRUCTURE.md](../../docs/STRUCTURE.md)).
10. Cross-check owners against CLAUDE.md §3 layering — an asset used by one feature but living in
    DesignSystem is worth flagging.

## S6. A note is a grep index, never a document

**Notes are searched, never read.** That is the whole reason they exist
([PATTERN-SEARCH.md](../../docs/PATTERN-SEARCH.md)): one `grep` returns the row, the row answers the
question, and the file never enters context. A note read end-to-end has cost more than the search it
was built to replace.

Three rules follow, and they bind this command as much as daily work:

1. **Never promote a note to a skill.** Not at any size. A skill loads its whole body when it fires;
   a note is grepped for one line. Converting one trades a cheap search for an expensive read, and
   the `description:` then costs tokens in *every* session. Size is not a reason — a 28 KB note that
   is only ever grepped costs the same as a 3 KB one.
2. **Never read a note in full**, including here. Read the header for its `Built from:` line and its
   scaffold marker; everything below that is written, not consulted.
3. **Maintain by insertion and deletion of rows** — a row appears when the thing appears, a row goes
   when the thing goes, in the same change (CLAUDE.md §5). This command's wholesale rewrite is the
   **only** exception, and it is why the command is user-typed.

### What that demands of a row

If the file is never read, then **every row must answer the question on its own**. A row that sends
the reader to the file has failed.

- **One fact, one line.** A row that wraps is two grep hits, each meaningless alone.
- **Self-contained** — the name, the path, and the clause saying what is there (S3.1).
- **Greppable by the word someone would actually search**: the screen name, the route case, the
  token, the endpoint path.

Check it, rather than assuming it:

```bash
# rows that wrap — a soft-wrapped table row defeats grep
awk 'BEGIN{FS=""} /^\| / && !/\|$/ {print FILENAME":"NR": row does not end in |"}' .claude/notes/*.md

# does a real lookup return a usable line?
grep -h "SmartLockHomeView" .claude/notes/*.md | head -3
```

Report the sizes for information, never as a trigger for restructuring:

```bash
wc -c .claude/notes/*.md | sort -rn
```

## S7. Gaps to flag, per note

- **FEATURES** — screens with no route; routes with no screen; screens missing `empty`/`offline`;
  features with no `Feature<Name>.md`; a screen whose only state is `loaded`.
- **NAVIGATION** — routes absent from the shell switch; deep links with no route; a feature
  constructing another feature's view (CLAUDE.md §2.1); **a route declared, hashed, compared and
  built but never pushed**, and its inverse — a screen reached by bypassing its own route.
- **API-MAP** — endpoints declared but never called (candidates, per S2); a call site whose method
  could not be read; two enums that both look like routers, one of them legacy; a path built by
  string concatenation inside a feature.
- **IMAGES** — unused assets (**candidates**, never a verdict); raw-string references;
  `original`-mode assets with no dark variant; duplicates across packages.
- **COLORS** — colorsets with no dark appearance; literal `Color(...)` in a feature; text tokens
  below 4.5:1 in **either** appearance; tokens with no consumer; **two names resolving to one value,
  and a name whose value contradicts it** (`blueSwitchAlpha08` resolving to grey).
- **FONTS** — files never registered; `UIAppFonts` entries whose file is missing; **package-resource
  fonts relying on `Info.plist`, which silently does nothing**; `Font.custom` without `relativeTo:`;
  **one typeface fragmented across several family names**, which breaks anything enumerating by
  family.
- **SCHEMES** — a config with no scheme or a scheme with no `.xcconfig`; duplicate bundle IDs;
  `#if DEBUG` in a feature (CLAUDE.md §2.10); a live analytics key outside PROD; **a secrets file
  tracked in git despite a matching ignore rule** (check `git ls-files`, per S2).
- **STYLE-GUIDE** — a literal spacing/radius/duration in a feature; two tokens within ~20% of each
  other (a near-duplicate nobody will reconcile); a component with no preview matrix; a token
  declared but never used; motion that ignores Reduce Motion.
- **PROJECT** — build settings in the project file instead of an `.xcconfig`; deployment target
  mismatched against `Package.swift`; a linked package nothing imports (**verify per S4** — the
  product name is not the package name); a permission with **no `NS*UsageDescription`** (crashes on
  call, not at build); an extension importing the app; **`aps-environment = development` in a
  Release entitlement**; **an `.lproj` on disk absent from `knownRegions`**.

## S8. Report

Say what changed — added, removed, gaps found — not "notes updated". If a scan found nothing (no
assets yet, no routes yet), say so explicitly and leave the scaffold intact.

**State every finding you corrected mid-scan, and why.** A run that silently shows only its final
numbers hides that the method was tuned until it agreed with them. Disclosing "the first unused-asset
pass said 52, the verified figure is 42, here is what the first pass missed" is what makes the other
rows worth trusting.

Close with the commands the user should run themselves (CLAUDE.md §2.12) — this command never
builds, tests, or compiles.
