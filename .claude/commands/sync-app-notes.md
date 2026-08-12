---
description: Rebuild the seven inventories in .claude/notes/ from a filesystem scan — features and screens, navigation and routes, image assets, colour tokens, fonts and registration, schemes, project targets. Reports the gaps it finds.
argument-hint: [optional: a note name, e.g. FONTS]
allowed-tools: Bash, Read, Edit, Grep, Glob
---

Rebuild the living inventories in `.claude/notes/` from what is actually on disk.

Scope: `$ARGUMENTS` if a note is named, otherwise all eight.

> **This is a command, not a skill, and that is the safety mechanism.** A full rescan rewrites eight
> files wholesale; run against a half-finished tree it replaces correct rows with incomplete ones —
> worse than a stale note, because it looks current. As a command it can only run when you type it,
> so there is no path by which it fires as a side effect of another task.
>
> **Targeted edits are the normal case and do not belong here.** Adding one row to `FEATURES.md`
> because you added one screen is part of that change (CLAUDE.md §5) — edit the file directly.

---

## Before rewriting anything

**State what you are about to scan and what it will replace**, then wait for confirmation. Typing
the command asks for a sync; it does not pre-approve discarding work in progress.

Check the tree is in a coherent state first — `git status`. A rescan mid-refactor is exactly the
case this warning exists for. If it's dirty, say so and let the user decide.

## What each note is built from

| Note | Scan | Key output |
|---|---|---|
| `FEATURES.md` | `Packages/Features/*/Sources/**/Views/`, view models | features → screens → routes, states, **file paths** |
| `NAVIGATION.md` | `Route` enum, shell `navigationDestination`, deep-link parser | route inventory, entry points, flow, deep links, **file paths** |
| `ASSETS-IMAGES.md` | `**/*.xcassets/**/*.imageset` | group, name, rendering mode, dark variant, owner |
| `ASSETS-COLORS.md` | `**/*.xcassets/**/*.colorset/Contents.json` | token, **light + dark hex** |
| `FONTS.md` | `*.otf`/`*.ttf`, `Info.plist`, `Font.custom` call sites | family, PostScript names, **registration path**, tokens |
| `SCHEMES.md` | `*.xcconfig`, scheme list, `Info.plist` substitutions | DEV/TEST/BETA/PROD → config, bundle ID, base URL |
| `PROJECT.md` | `project.pbxproj`, `*.entitlements`, `Info.plist`, package links | targets, deployment targets, capabilities, links |
| `STYLE-GUIDE.md` | token declarations in `DesignSystem/Tokens/`, components + their `#Preview` blocks | spacing, radius, elevation, motion, type scale, component variants |

```bash
find . -name "Contents.json" -path "*.colorset/*"        # colours
find . -type d -name "*.imageset"                        # images
find . \( -name "*.otf" -o -name "*.ttf" \)              # fonts
grep -rn "UIAppFonts\|ATSApplicationFontsPath" --include="*.plist"
grep -rn "Font.custom" --include="*.swift"
grep -rn "case " --include="Route.swift"
```

Colorsets store components as float strings or hex — normalise to `#RRGGBB` uppercase, and record
**Any/Light** and **Dark** separately. A colorset with one appearance is a finding, not a blank cell.

## Paths are the point — emit them, verified

`FEATURES.md` and `NAVIGATION.md` are indexes: someone should `grep` a screen or a route there and
get the file. So every row carries a **repo-relative path**, and every graph node carries a
`click` target.

```bash
# a route case and the line that defines it
grep -rn "case .*:" --include="Route.swift" Packages | sed 's/:.*case /  /'
# the view that renders it — from the shell's switch
grep -rn "navigationDestination" -A40 App | grep -E "case \.|Assembly"
```

Four rules, because a wrong or unexplained path is worse than a missing one:

1. **Never emit a bare path.** Every path gets a clause saying what is there —
   `Route.swift:12 — the case declaration`, `LoginView.swift — email/password form, owns field
   state`. A path answers *where*, not *what*; without the note the reader opens every hit. In
   mermaid, that clause is the third `click` argument (the tooltip). In shell recipes, a `#` comment
   on the same line.
2. **Verify every path resolves** before writing it. If the file isn't there, the row goes in `Gaps`
   — never emit a guess.
3. **A `:line` suffix is optional and only for a definition site.** Omit it rather than let it rot;
   a stale line number sends the reader to the wrong place with full confidence.
4. **Keep every `click` line in the mermaid block.** They are what make the diagram findable by
   `grep`, not decoration — a diagram without them is a picture, not an index.

If there is nothing useful to say about a path, that is a signal the row may not be worth listing.

## Rules for every note

1. **Preserve structure and prose.** Replace table bodies only — the guidance in those files is
   hand-written and must survive a regeneration.
2. **Keep commented-out example rows** while a table is empty; delete an example only when real rows
   replace it.
3. **Never drop a row silently.** A removed asset or route is a deletion — take it out in the same
   change that removes the code, so the diff shows both.
4. **Fill the `Gaps` table rather than omitting problems.** An inventory that hides a defect is worse
   than no inventory.
5. **Never edit CLAUDE.md.** If a scan suggests a rule, report it and let the user decide — CLAUDE.md
   is approval-gated ([STRUCTURE.md](../../docs/STRUCTURE.md)).
6. Cross-check owners against CLAUDE.md §3 layering — an asset used by one feature but living in
   DesignSystem is worth flagging.

## Gaps to flag, per note

- **FEATURES** — screens with no route; routes with no screen; screens missing `empty`/`offline`;
  features with no `Feature<Name>.md`.
- **NAVIGATION** — routes absent from the shell switch; deep links with no route; a feature
  constructing another feature's view (CLAUDE.md §2.1).
- **IMAGES** — unused assets; raw-string references; `original`-mode assets with no dark variant;
  duplicates across packages.
- **COLORS** — colorsets with no dark appearance; literal `Color(...)` in a feature; text tokens
  below 4.5:1 in **either** appearance; tokens with no consumer.
- **FONTS** — files never registered; `UIAppFonts` entries whose file is missing; **package-resource
  fonts relying on `Info.plist`, which silently does nothing**; `Font.custom` without `relativeTo:`.
- **SCHEMES** — a config with no scheme or a scheme with no `.xcconfig`; duplicate bundle IDs;
  `#if DEBUG` in a feature (CLAUDE.md §2.10); a live analytics key outside PROD.
- **STYLE-GUIDE** — a literal spacing/radius/duration in a feature; two tokens within ~20% of each
  other (a near-duplicate nobody will reconcile); a component with no preview matrix; a token
  declared but never used; motion that ignores Reduce Motion.
- **PROJECT** — build settings in the project file instead of an `.xcconfig`; deployment target
  mismatched against `Package.swift`; a linked package nothing imports; a permission with **no
  `NS*UsageDescription`** (crashes on call, not at build); an extension importing the app.

## Report

Say what changed — added, removed, gaps found — not "notes updated". If a scan found nothing
(no assets yet, no routes yet), say so explicitly and leave the scaffold intact.
