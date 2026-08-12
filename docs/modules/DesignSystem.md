# DesignSystem

Tokens, components, and `ContentStateView`. The only package allowed to contain `#if os(...)`
for visual divergence.

- **Package:** `Packages/DesignSystem` (local)
- **Used by:** every feature. Depends on [Core](Core.md) and
  [LocalizationKit](LocalizationKit.md) only.
- **When to read this:** building any view, adding a token, adding a component, rendering a
  content state, or gating a platform-specific API.

---

**The registry of what exists is [STYLE-GUIDE.md](../../.claude/notes/STYLE-GUIDE.md)** — every
spacing, radius, elevation, motion and type token, plus the component inventory. Check it before
writing a value; the `style-guide` skill does that lookup and proposes an existing token when one
fits, rather than letting a near-duplicate in.

## Zero raw values in features

No literal colors, fonts, spacing, corner radii, or durations outside this package. A feature
that needs a value it can't find here needs a **token added here**, not a literal.

```swift
Color.appPrimary      Color.surfaceElevated     Color.textSecondary
Font.appTitle         Font.appBody              Font.appCaption
Spacing.xs .sm .md .lg .xl                      Radius.card  Radius.control
Motion.standard       Motion.emphasized
```

Naming is **semantic, not descriptive**: `surfaceElevated`, not `grayLight`. A descriptive name
becomes a lie the first time Dark Mode disagrees with it. Light and Dark values are defined
together, in the same declaration, so one can't be added without the other.

## ContentStateView — the reason features stay small

`ContentState<Value>` is defined in [Core](Core.md). This package renders all six cases, once, so
no feature writes an empty state or an error state by hand.

```swift
ContentStateView(state: model.state,
                 empty: .init(symbol: "tray",
                              title: L10n.Home.Feed.emptyTitle,
                              body: L10n.Home.Feed.emptyBody),
                 retry: { await model.reload() }) { items in
    FeedList(items: items)          // the feature supplies ONLY this
}
```

What the component guarantees, so features don't re-litigate it:

| State | Rendering |
|---|---|
| `idle` | nothing; no flash of empty before the first load |
| `loading` | **skeleton/shimmer** shaped like the real content — not a bare spinner, for both list and detail |
| `loaded` | the feature's content closure |
| `empty` | symbol + localized title + localized body + optional localized action |
| `offline` | cached content if available, plus a **persistent banner** and auto-retry on reconnect |
| `failed` | localized message from `AppError.messageKey`; Retry shown only if `isRetryable` |

**Offline is a state, not an alert.** It never routes through
[Messaging](Messaging.md) — a connectivity drop is a property of the screen, not an interruption.

### Paged lists

For `ContentState<Paged<Item>>` ([Core.md](Core.md)), the footer renders the inner `PageState` while
the loaded content stays on screen:

| `PageState` | Footer |
|---|---|
| `idle` | nothing; trigger the next page on approach |
| `loadingMore` | inline spinner — **never** replace the list with a skeleton |
| `failed` | inline message + Retry, scoped to the footer |
| `exhausted` | nothing; footer removed so the list ends cleanly |
| `stale` | optional refresh banner above the list |

A failed page must never blank the rows already loaded. That is the failure this split exists to
prevent.

Every placeholder needs a symbol/illustration, a localized title, a localized body, and — where
there is something to do — a localized primary action. A bare "No data" is a bug.

## Platform gating lives here

CLAUDE.md §1.1: shared code compiles against **iOS 17**, while macOS is on **26.6**. Every gate
for that gap belongs inside a component in this package, never in a feature. A feature must not
know which OS it is on.

```swift
public struct AppToolbar<Content: View>: View {
    public var body: some View {
        #if os(macOS)
        macOSToolbar          // free to use macOS 26 APIs — never compiled for iOS
        #else
        iOSToolbar            // iOS 17 floor
        #endif
    }
}
```

Use `if #available` only when both branches ship on the same platform, and only with a working
fallback. Never both mechanisms in one place silently.

> **Open decision** — whether the app adopts each platform's native look (divergent) or one owned
> visual language across both. Until it's recorded in [../DECISIONS.md](../DECISIONS.md), **keep
> tokens platform-neutral** and don't introduce a token that only makes sense on one platform.

## Every component previewable in every state

A component is not done until its `#Preview` block covers: default · loading · empty · error ·
disabled · Dynamic Type XXXL · Dark Mode · RTL. That preview set *is* the snapshot suite
(CLAUDE.md §8) — write it once, get both.

**The full matrix applies to components only.** Screens snapshot `loaded` plus one failure state.
Multiplied across every screen the matrix is 40+ snapshots each, and that suite reliably becomes
the flakiest, highest-maintenance thing in the repo. Components are where it earns its cost —
every screen inherits their correctness for free.

```swift
#Preview("States") {
    ForEach(ContentStatePreviewCase.allCases) { PrimaryButton.preview(for: $0) }
}
```

## Accessibility is built into the component, not added by the caller

Because features never construct raw controls, accessibility can be guaranteed here:

- Every interactive component: localized `accessibilityLabel`, correct trait, ≥44×44pt target.
- Respect Reduce Motion (`Motion.*` collapses to instant), Reduce Transparency, Increase
  Contrast, Bold Text.
- Contrast ≥ 4.5:1 for body text, asserted by a token test — not by eye.
- Never encode meaning in color alone; pair every semantic color with a symbol or text.

## Do not create a near-duplicate

Extend an existing component before adding a new one. Two components that differ by a corner
radius are one component and a parameter.
