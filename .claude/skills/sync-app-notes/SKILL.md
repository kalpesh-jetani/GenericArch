---
name: sync-app-notes
description: Build or refresh the living inventories in .claude/notes/ — features and screens, navigation and routes, image assets by group, color tokens with light/dark hex, fonts and their registration path, schemes and configurations, project targets. REQUIRES EXPLICIT USER APPROVAL — never invoke automatically or as a side effect; ask first and wait for a clear yes. Claude Code's built-in /init does NOT run this. Use at first-time setup, when asked to "update the notes" or "refresh the inventory", or after a large batch of insertions or deletions. Also reports gaps it finds. Do NOT use for a single-row note edit alongside a code change (edit the note directly), for CLAUDE.md, or for docs/modules/.
---

# Sync app notes

> ## ⛔ Ask before running
>
> **Never execute this skill on your own initiative.** It rewrites seven files wholesale, and a
> rescan against a half-finished tree overwrites correct rows with incomplete ones.
>
> When a sync looks warranted, **say what you'd sync and why, then wait for an explicit yes.**
> A user asking you to add a screen is not approval to regenerate the inventories.
>
> **This does not apply to targeted edits.** Adding one row to `FEATURES.md` because you added one
> screen is part of that change (DONE) — make it directly, no approval needed, no skill
> run. The approval gate is for the full rescan-and-rewrite only.

Seven inventories in `.claude/notes/`, regenerated from the code. **The code is the source of
truth** — never hand-write a row that isn't backed by a file.

| Note | Scan | Key output |
|---|---|---|
| `FEATURES.md` | `Sources/Feature*/Views/`, view models, `Feature*.md` | features → screens → routes, states implemented |
| `NAVIGATION.md` | `Route` enum, shell `navigationDestination`, deep-link parser | route inventory, flow diagram, entry points |
| `ASSETS-IMAGES.md` | `**/*.xcassets/**/*.imageset` | group, name, rendering mode, dark variant, owner |
| `ASSETS-COLORS.md` | `**/*.xcassets/**/*.colorset/Contents.json` | token, **light + dark hex**, contrast ratio |
| `FONTS.md` | `*.otf` / `*.ttf`, `Info.plist`, `Font.custom` call sites | family, PostScript names, **registration path**, type tokens |
| `SCHEMES.md` | `*.xcconfig`, `.xcodeproj` scheme list, `Info.plist` substitutions | DEV/TEST/BETA/PROD → configuration, bundle ID, base URL, signing |
| `PROJECT.md` | `project.pbxproj` targets, `*.entitlements`, `Info.plist`, package product links | targets, deployment targets, capabilities, plist keys, package links |

## Run it when

- First-time project setup, when the user asks for it. **Claude Code's `/init` does not run this**
  — it generates CLAUDE.md only. There is no automatic trigger, by design (see the gate above).
- **Any insertion or deletion** of a screen, route, image, color, or font — same change, not later.
- Before a release (`release-bump`), so the notes match the tag.

## How to scan

Read from the filesystem, not from memory of a previous run.

```bash
# Colors — token name + sRGB components per appearance
find . -name "Contents.json" -path "*.colorset/*"

# Images — every imageset, grouped by its parent folder
find . -type d -name "*.imageset"

# Fonts — files, then registration, then call sites
find . \( -name "*.otf" -o -name "*.ttf" \)
grep -rn "UIAppFonts\|ATSApplicationFontsPath" --include="*.plist"
grep -rn "Font.custom" --include="*.swift"

# Routes and screens
grep -rn "case " --include="Route.swift"
grep -rln ": View" --include="*.swift" Sources/
```

Colorsets store components as float strings or hex — normalize to `#RRGGBB` uppercase. Record the
**Any/Light** and **Dark** appearances separately; a colorset with only one appearance is a
finding, not a blank cell.

## Rules for every note file

1. **Preserve the file's structure and headers.** Replace table bodies, not the surrounding
   guidance — the "why" text in those files is hand-written and must survive a regeneration.
2. **Keep the commented-out example rows** while a table is still empty; delete an example only
   when real rows replace it.
3. **Never delete a row silently.** A removed asset or route is a deletion — take it out of the
   inventory in the same change that removes the code, so the diff shows both.
4. **Fill the `Gaps` table rather than omitting problems.** An inventory that hides a defect is
   worse than no inventory.
5. **Never edit CLAUDE.md.** If a scan reveals something that belongs in a rule, report it and let
   the user decide — CLAUDE.md is approval-gated ([STRUCTURE.md](../../../docs/STRUCTURE.md)).
6. Cross-check owners against CLAUDE.md §3 layering — an asset used by one feature but living in
   DesignSystem is worth flagging.

## Gaps to flag, per note

- **FEATURES** — screens with no route; routes with no screen; screens missing `empty`/`offline`;
  features with no `Feature<Name>.md`.
- **NAVIGATION** — routes absent from the shell switch; deep links with no route; a feature
  constructing another feature's view (CLAUDE.md §2.1).
- **IMAGES** — unused assets; assets referenced by raw string; `original`-mode assets with no dark
  variant; duplicates across packages.
- **COLORS** — colorsets with no dark appearance; literal `Color(...)` in a feature; text tokens
  below 4.5:1 in **either** appearance; tokens with no consumer.
- **FONTS** — font files never registered; `UIAppFonts` entries whose file is missing;
  **package-resource fonts relying on `Info.plist`, which silently does nothing**;
  `Font.custom` without `relativeTo:`; raw `Font.custom` at a feature call site.
- **SCHEMES** — a configuration with no scheme or a scheme with no `.xcconfig`; duplicate bundle
  IDs across configurations; `#if DEBUG` inside a feature package (CLAUDE.md §2.10); `DEBUG` set on
  a release-like configuration; a live analytics key outside PROD; PROD resolving a non-production
  base URL.
- **PROJECT** — build settings set in the project file instead of an `.xcconfig`; deployment target
  mismatched against `Package.swift`; a linked package no source file imports; a permission used
  with **no `NS*UsageDescription`** (crashes on call, not at build); entitlements diverging from the
  capability matrix; an extension importing the app; a background mode declared but unused; a
  package missing `PrivacyInfo.xcprivacy`.

That last font case is the one worth checking every time: `UIAppFonts` reads the **main bundle
only**, so a font shipped as an SPM package resource needs runtime
`CTFontManagerRegisterFontsForURL`. The symptom is a silent fallback to system font with no error.

## Report

After syncing, state what changed — added, removed, and gaps found — rather than "notes updated".
If a scan found nothing (no assets yet, no routes yet), say so explicitly and leave the scaffold
intact.
