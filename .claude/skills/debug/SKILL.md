---
name: debug
description: Diagnose broken or unexpected behaviour by narrowing the symptom to a layer before reading code. Fires on "fix this crash", "it crashed", "why is it blank", "nothing happens", "renders as the raw key", "silently does nothing", "fine locally but wrong in TestFlight", or a stack trace. Starts from an index mapping known symptoms to their cause, names the layer, then reads only that layer.
---

# Debugging

**If this is really a styling, dark-mode, RTL or release question, stop and say so** — those
patterns live in `docs/patterns/` and are not promoted to skills in this repo yet. Read the pattern
file instead of improvising, and offer `/learn <pattern>` if it is now worth promoting.

**Narrow to a layer before opening a file.** The symptom usually names the layer; reading code first
means reading the wrong file.

## 1. Symptom index — check here first

Most reported symptoms in this architecture have one likely cause, and it is rarely where the
symptom appears.

| Symptom | Likely cause | Confirm in |
|---|---|---|
| A string renders as its raw key | Wrong bundle — inside a package it is `.module`, not `.main` | [LocalizationKit.md](../../../docs/modules/LocalizationKit.md) |
| Custom font renders as system | Package fonts need runtime registration; `UIAppFonts` reads the **main bundle only** | [FONTS.md](../../notes/FONTS.md) |
| Blank screen, no error | A `ContentState` case not handled — usually `empty` or `idle` | [Core.md](../../../docs/modules/Core.md) |
| Rows vanish when a page fails | `PageState.failed` collapsed into `ContentState.failed` | [Core.md](../../../docs/modules/Core.md) |
| Fine in light, unreadable in dark | Colorset with only an Any appearance, or shadow-based elevation | `dark-light-mode` |
| Layout inverts wrongly, or does not | `.left`/`.right` instead of leading/trailing; custom drawing ignores `layoutDirection` | `rtl-support` |
| Push works in DEV, silent in TestFlight | APNs sandbox vs production — TestFlight always uses production | [SCHEMES.md](../../notes/SCHEMES.md) |
| Crash the instant a permission is requested | Missing `NS*UsageDescription` — crashes on call, not at build | [PROJECT.md](../../notes/PROJECT.md) |
| Background transfer never resumes | The `handleEventsForBackgroundURLSession` completion handler was dropped | [NetworkKit.md](../../../docs/modules/NetworkKit.md) |
| Signed out unexpectedly under load | Token refresh is not single-flight; concurrent 401s raced | [NetworkKit.md](../../../docs/modules/NetworkKit.md) |
| Works on device, fails to compile for iOS | A macOS-only API in shared code — `swift build` on a Mac never checks the iOS floor | CLAUDE.md §1.1 |
| Feature reads a stale flag in a test build | Build-flag branching instead of injected `AppEnvironment` | [SCHEMES.md](../../notes/SCHEMES.md) |

**Check the notes index before grepping** ([PATTERN-SEARCH.md](../../../docs/PATTERN-SEARCH.md)) —
`FEATURES.md` and `NAVIGATION.md` map a screen name to its files without a search.

## 2. If it is not in the table

Narrow by layer, in this order — each step rules out everything above it:

1. **Is the data right?** Log the value at the service boundary. If it is wrong here, stop; nothing
   downstream matters.
2. **Is the mapping right?** DTO → domain, and error → `AppError`. Most "wrong value on screen" bugs
   die here.
3. **Is the state right?** Which `ContentState` case is the view model in? A wrong case renders a
   correct view of the wrong thing.
4. **Is the view right?** Only now open the SwiftUI file.

State which layer you concluded and why, before proposing a fix. A fix without a named layer is a
guess.

## 3. Reproduce before fixing

- **Write the failing test first** where the bug is in a view model, mapper, or service — the mock
  makes it reproducible in milliseconds ([DIKit.md](../../../docs/modules/DIKit.md) `testValue`).
- If it only reproduces on a device, say so, and say what you could not verify.
- A bug you cannot reproduce is a bug you cannot confirm you fixed. Say that rather than shipping a
  plausible change.

## 4. Fix at the layer that owns it

The temptation is to patch where the symptom appeared. A missing localization key gets "fixed" with
a literal in the view; a nil gets a `??`. Both hide the bug and violate a §2 rule.

- Localized text missing → add the key, never a literal (§2.3).
- Unexpected nil → fix the mapping or make it a typed `AppError`, never `try?` (§2.7).
- A state not handled → add the case, never an `if` in the view (§2.5).

## Before finishing

- [ ] Named the layer, not just the file
- [ ] Reproduced it — or said plainly that you could not
- [ ] Fixed at the owning layer, not at the symptom
- [ ] A regression test exists where the layer is testable
- [ ] If the cause was a known one, the symptom index above already covered it — if not, **add the
      row**, so the next person starts from the answer
