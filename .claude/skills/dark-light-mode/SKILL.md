---
name: dark-light-mode
description: Implement and verify Dark Mode and Light Mode in a GenericArch app — paired colour tokens, colorset dark appearances, asset dark variants, elevation, and 4.5:1 contrast in both appearances. Use when asked to add dark mode, support light and dark, fix dark mode, or when told something looks wrong in dark; also whenever a colour token or image asset is added. Catches colorsets with only an Any appearance, hardcoded .white/.black, shadow-based elevation that vanishes on black, tokens that pass in light and fail in dark, and colorScheme branching that should have been a token. Related skill: rtl-support. Do NOT use for the app-wide visual direction decision (CLAUDE.md §1.1).
---

# Dark / Light Mode

Design rules live in [DesignSystem.md](../../../docs/modules/DesignSystem.md). This is the
implement-and-verify procedure.

**The principle:** a view should never ask which appearance it is in. Tokens resolve; views
render. Every `@Environment(\.colorScheme)` read is a token that wasn't defined.

## 1. Tokens — light and dark declared together

Both values in the same declaration. One cannot be added without the other, and a colorset with
only an **Any** appearance is a defect, not a default.

```swift
// ✅ the colorset carries both; the view never chooses
Color.surfaceElevated

// ❌ every one of these is a bug
Color.white                              // does not invert
Color(red: 0.95, green: 0.95, blue: 0.97) // literal in a feature — CLAUDE.md §2
colorScheme == .dark ? .black : .white   // branching instead of a token
```

Naming is **semantic, not descriptive**. `grayLight` that resolves to `#1C1C1E` in dark is a lie
the compiler can't catch.

## 2. What actually breaks in dark mode

Work through these — they're the failures that survive review:

| Failure | Why it happens | Fix |
|---|---|---|
| **Elevation disappears** | Shadows are invisible on black. A card defined only by `.shadow()` becomes a floating nothing | Convey elevation with `surfaceElevated`, a lighter surface — shadow is a light-mode-only affordance |
| **Contrast passes light, fails dark** | Ratios were checked once, in one appearance | Assert ≥4.5:1 for text in **both**, in a token test |
| **Illustrations glow** | An `original` asset with a baked white background sits on a black surface | Add a dark variant to the imageset, or make it `template` and tint it |
| **Hardcoded white text** | `.foregroundStyle(.white)` on a colored button that darkens in dark | `textOnAccent` token, paired |
| **Borders vanish** | `separator` at light values on a dark surface | Paired `separator` token; never `Color.gray.opacity(0.2)` |
| **Materials read differently** | `.ultraThinMaterial` over dark content is much lower contrast | Verify with Reduce Transparency **on** as well as off |
| **Blanket dark overlay** | `.black.opacity(0.4)` scrim invisible in dark | Paired `scrim` token |

## 3. Assets

- **Template** rendering mode tints automatically — nothing to do. Prefer it for all icons.
- **Original** assets that carry their own background need a **Dark appearance** in the imageset.
- App icon, launch screen, and any marketing/onboarding imagery need dark variants too — these get
  missed because they're outside the normal screen flow.

Record the variant in [ASSETS-IMAGES.md](../../notes/ASSETS-IMAGES.md); record both hexes
in [ASSETS-COLORS.md](../../notes/ASSETS-COLORS.md).

## 4. When `colorScheme` is legitimately needed

Rare, but real: picking between two *non-color* assets that can't be expressed as one colorset, or
choosing a map/chart style from a third-party renderer.

```swift
@Environment(\.colorScheme) private var colorScheme   // justify it in a comment, like §2.8
```

If it's setting a color, it's wrong. Define the token instead.

## 5. Verify

Every component's `#Preview` covers both appearances — that preview set *is* the snapshot suite
(CLAUDE.md §9):

```swift
#Preview("Light") { ComponentUnderTest().preferredColorScheme(.light) }
#Preview("Dark")  { ComponentUnderTest().preferredColorScheme(.dark) }
```

Assert contrast rather than eyeballing it:

```swift
#expect(Color.textSecondary.contrastRatio(on: .surface, .light) >= 4.5)
#expect(Color.textSecondary.contrastRatio(on: .surface, .dark)  >= 4.5)
```

Then run it: toggle appearance live in the Simulator (**Settings → Developer → Dark Appearance**,
or ⌘⇧A) and on Mac (**System Settings → Appearance**). Toggle *while the app is running* — some
bugs only appear on the transition, not on a cold launch into dark.

Check with **Increase Contrast** and **Reduce Transparency** enabled too; both change how tokens
and materials resolve.

## 6. Platform note

macOS is on **26.6**, iOS on **17** (CLAUDE.md §1.1). Appearance APIs are old enough to be safe on
both, but any newer macOS material or appearance API belongs inside a DesignSystem component behind
`#if os(macOS)` — never in a feature.

On Mac also verify against a non-default **accent color**, since users change it and it composes
with your tokens.

## 7. Before finishing

- [ ] No colorset with only an Any appearance
- [ ] No `.white` / `.black` / literal color outside DesignSystem
- [ ] Elevation survives dark (surface, not shadow)
- [ ] Every `original` asset with a background has a dark variant
- [ ] Text contrast ≥4.5:1 asserted in **both** appearances
- [ ] Previews cover light and dark for every component
- [ ] Verified with Increase Contrast and Reduce Transparency on
- [ ] [ASSETS-COLORS.md](../../notes/ASSETS-COLORS.md) and
      [ASSETS-IMAGES.md](../../notes/ASSETS-IMAGES.md) updated in this change
