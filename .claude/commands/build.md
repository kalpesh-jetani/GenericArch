---
description: Build, test, or archive a scheme (DEV/TEST/BETA/PROD) for iOS or macOS
argument-hint: [DEV|TEST|BETA|PROD] [ios|macos|both] [build|test|archive]
allowed-tools: Bash, Read, Grep
---

```bash
./Scripts/ga-step.sh after install      # sequence gate
```

**Exit 5 means an earlier step has not run.** Say which one, and stop — never pass `--force`, and
never work around it. Order and why: [SEQUENCE.md](../../docs/SEQUENCE.md).

Build the project for the requested stage.

**This command is the sanctioned exception to CLAUDE.md §2.12** — typing it *is* the instruction to
build. Outside it, never build, run or test on your own initiative.

**Arguments:** `$ARGUMENTS` — scheme stage, platform, action. Defaults when omitted:
`DEV ios build`.

Scheme → configuration mapping and what each stage is *for*: @.claude/notes/SCHEMES.md

## Steps

1. **Resolve the arguments against what exists** — never against the mapping in your head. Scheme
   names drift, and `xcodebuild` fails slowly and unhelpfully on a name that is close but wrong:

   ```bash
   xcodebuild -list -workspace *.xcworkspace 2>/dev/null || xcodebuild -list -project *.xcodeproj
   ```

   Map stage → configuration: `DEV`→`Debug`, `TEST`→`Test`, `BETA`→`Beta`, `PROD`→`Release`. If the
   printed list has no scheme matching the stage, **stop and ask** — building PROD when DEV was
   meant wastes minutes and can touch signing.

   Pick a simulator that is actually installed, rather than hardcoding a device name:

   ```bash
   xcrun simctl list devices available | grep -E "iPhone|iPad" | head -5
   ```

2. **Packages first, they're the cheap signal.** Build only what the diff touched:

   ```bash
   BASE=$(git merge-base HEAD main 2>/dev/null || echo HEAD~1)
   git diff --name-only "$BASE"...HEAD -- 'Packages/*' | cut -d/ -f2 | sort -u | while read -r pkg; do
     echo "── $pkg"
     swift build --package-path "Packages/$pkg" || break
     swift test  --package-path "Packages/$pkg" || break
   done
   ```

   A package failure means the app build will fail slower and less clearly. Stop here if one fails.

3. **Then the app.** Substitute the scheme name from step 1 verbatim:

   ```bash
   xcodebuild -scheme "<SchemeFromStep1>" -configuration "<Config>" \
     -destination 'platform=iOS Simulator,name=<DeviceFromStep1>' \
     build 2>&1 | tail -40
   ```

   Destinations: iOS simulator `'platform=iOS Simulator,name=iPhone 17'` · iOS device/archive
   `'generic/platform=iOS'` · macOS `'platform=macOS'`.

   Surface warnings as well as errors — [DONE.md](../../docs/DONE.md) requires zero:

   ```bash
   xcodebuild ... 2>&1 | grep -E "warning:|error:" | sort -u
   ```

4. **Report faithfully.** Warnings count — [DONE.md](../../docs/DONE.md) requires zero under strict concurrency, so
   surface them even when the build succeeds. Quote the actual compiler output for failures; don't
   paraphrase.

The process around this command — choosing a stage, who runs what, what to do when it fails:
[BUILD-PROCESS.md](../../docs/BUILD-PROCESS.md).

## A package has no scheme

`/build` resolves scheme and destination for the app. A package is built directly, and this is the
only place those commands live:

```bash
swift build --package-path Packages/<Name>
swift test  --package-path Packages/<Name>
swift test  --package-path Packages/<Name> --filter <Pattern>   # one test
```

Every package must build and test standalone — that is what enforces the module boundaries
(CLAUDE.md §9).

## Constraints

- `archive` is only valid for BETA and PROD. If asked to archive DEV or TEST, say why it's wrong
  (`ENABLE_TESTABILITY`, unoptimized, dev signing) and offer `build` instead.
- Signing for TEST/BETA/PROD is **manual, via CI credentials** ([DELIVERY.md](../../docs/DELIVERY.md)).
  A local archive of those may fail on signing — that is expected, not a bug to fix here.
- Never disable a warning or add `-warnings-as-errors=NO` to make a build pass. Fix it or report it.
- If an extracted package has a `swift package edit` override active, say so before building — the
  result won't reflect the pinned version.
