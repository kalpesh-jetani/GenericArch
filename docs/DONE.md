# Definition of Done

**Read this before saying a change is finished.** Run `/verify` to walk it against the working diff.

Not every line is machine-checkable, and pretending otherwise is how a checklist gets rubber-stamped:

| Marker | Meaning |
|---|---|
| 🤖 | Enforced by `./Scripts/check.sh`, SwiftLint, or the build. If it passes, it passes |
| 👁 | Needs a device, a simulator, or a human eye. **Must be stated as verified or skipped** — never assumed |

`/verify` reports 👁 items under *Not checkable here* rather than letting them read as passing.

---

## Builds

- [ ] 🤖 Clean build for **iOS, iPadOS, and macOS** with **zero warnings** under Swift 6 strict
      concurrency
- [ ] 🤖 Shared code compiles against the **iOS 17** floor; every newer API gated (CLAUDE.md §1.1)
- [ ] 🤖 `swift test` passes standalone for every package touched — not only through the app
- [ ] 👁 Extracted-package change? Tagged there, `Package.resolved` bumped here
      ([REPO.md](REPO.md))

## Rules that are mechanically checkable

- [ ] 🤖 No raw user-facing string; keys added to the catalog **in every supported language**
      ([LocalizationKit.md](modules/LocalizationKit.md))
- [ ] 🤖 No new `@unchecked Sendable` without its justification comment
- [ ] 🤖 No force-unwrap outside tests, no `try?` that swallows, no `fatalError` in a shipping path
- [ ] 🤖 No `#if DEBUG` or build-flag branch inside a feature package
      ([SCHEMES.md](../.claude/notes/SCHEMES.md))
- [ ] 🤖 No `.alert` / `.confirmationDialog` / system-styled message surface
      ([Messaging.md](modules/Messaging.md))
- [ ] 🤖 No `resolve` call inside a feature type — only root, `Assembly`, previews, tests
      ([DIKit.md](modules/DIKit.md))
- [ ] 🤖 No literal color, font, spacing, radius, or duration outside DesignSystem

## Behavior

- [ ] 👁 **Every content state implemented** — loading / empty / offline / error / loaded, plus the
      footer states if the list is paged ([Core.md](modules/Core.md))
- [ ] 👁 Errors mapped to `AppError` with `isRetryable` set deliberately
- [ ] 👁 Any external library touched only through its wrapper (CLAUDE.md §7)
- [ ] 🤖 Dependencies injected by protocol; a mock ships beside each one
- [ ] 👁 Long-running work is cancellable and honors `Task.isCancelled`

## Platforms & accessibility

- [ ] 👁 Works in **compact and regular** width; verified on iPhone, iPad, and Mac
- [ ] 👁 Dark Mode verified — run `/dark-light-mode` if colors or assets changed
- [ ] 👁 RTL verified — run `/rtl-support` if layout or strings changed
- [ ] 👁 Dynamic Type to **XXXL** with no truncation or clipping
- [ ] 👁 Localized `accessibilityLabel`, correct trait, ≥44×44pt target on every interactive element

## Tests

- [ ] 🤖 View models, mappers, and services unit-tested against mocks; **no network**
- [ ] 👁 Snapshots within scope: full matrix for DesignSystem components; screens get `loaded` + one
      failure state ([DesignSystem.md](modules/DesignSystem.md))
- [ ] 👁 Contract tests updated if a wrapper or an extracted package changed

## Documentation — same change, not later

- [ ] 🤖 The module's `.md` updated if behavior changed
- [ ] 👁 `.claude/notes/` **rows** updated for every insertion or deletion — screen, route, image,
      color, font, scheme, target, **design token or component variant**. Targeted edits; **not** a
      `/sync-app-notes` run
- [ ] 👁 Any §0 decision made in this change recorded in [DECISIONS.md](DECISIONS.md) — `/decide`

---

## After it passes

`feature-complete` closes it out and asks what to keep, in the user's terms: *this can be used in
future — so save it* · *just close* · *continue* · *skip*. Most work should just close with a note —
saving it as a skill is only worth the cost when the next similar feature would follow the same
sequence.

## When something can't be checked

Say so explicitly and name what was skipped. "Verified on iPhone; iPad and Mac not checked" is a
useful report. Silently omitting a line is the failure this file exists to prevent.
