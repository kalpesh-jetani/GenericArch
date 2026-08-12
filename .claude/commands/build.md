---
description: Build, test, or archive a scheme (DEV/TEST/BETA/PROD) for iOS or macOS
argument-hint: [DEV|TEST|BETA|PROD] [ios|macos|both] [build|test|archive]
allowed-tools: Bash, Read, Grep
---

Build the project for the requested stage.

**This command is the sanctioned exception to CLAUDE.md §2.12** — typing it *is* the instruction to
build. Outside it, never build, run or test on your own initiative.

**Arguments:** `$ARGUMENTS` — scheme stage, platform, action. Defaults when omitted:
`DEV ios build`.

Scheme → configuration mapping and what each stage is *for*: @.claude/notes/SCHEMES.md

## Steps

1. **Resolve the arguments.** Map stage → configuration: `DEV`→`Debug`, `TEST`→`Test`,
   `BETA`→`Beta`, `PROD`→`Release`. If the stage is ambiguous, ask rather than guessing — building
   PROD when DEV was meant wastes minutes and can touch signing.

2. **Packages first, they're the cheap signal.** Any package the diff touched:
   ```
   swift build --package-path Packages/<Name>
   swift test  --package-path Packages/<Name>
   ```
   A package failure means the app build will fail slower and less clearly. Stop here if one fails.

3. **Then the app:**
   ```
   xcodebuild -scheme GenericArch-<STAGE> -configuration <Config> \
     -destination '<destination>' <action>
   ```
   Destinations: iOS simulator `'platform=iOS Simulator,name=iPhone 17'` · iOS device/archive
   `'generic/platform=iOS'` · macOS `'platform=macOS'`.

4. **Report faithfully.** Warnings count — [DONE.md](../../docs/DONE.md) requires zero under strict concurrency, so
   surface them even when the build succeeds. Quote the actual compiler output for failures; don't
   paraphrase.

## Constraints

- `archive` is only valid for BETA and PROD. If asked to archive DEV or TEST, say why it's wrong
  (`ENABLE_TESTABILITY`, unoptimized, dev signing) and offer `build` instead.
- Signing for TEST/BETA/PROD is **manual, via CI credentials** ([DELIVERY.md](../../docs/DELIVERY.md)).
  A local archive of those may fail on signing — that is expected, not a bug to fix here.
- Never disable a warning or add `-warnings-as-errors=NO` to make a build pass. Fix it or report it.
- If an extracted package has a `swift package edit` override active, say so before building — the
  result won't reflect the pinned version.
