---
name: rtl-support
description: Implement and verify right-to-left support — layoutDirection, mirroring, directional SF Symbols, asset flipping, text alignment, locale-correct numbers and dates. Use when asked to support RTL, add Arabic, Hebrew, Farsi or Urdu, verify mirroring, or when adding a locale. Catches .left/.right instead of leading/trailing, chevron.right that does not flip, concatenation that freezes word order, custom drawing that ignores layoutDirection, and logos or media controls that must NOT flip. Related skill: dark-light-mode.
---

# RTL support

Key format, catalogs, and typed accessors are in
[LocalizationKit.md](../../../docs/modules/LocalizationKit.md). This is the layout-mirroring
procedure.

**RTL is not a translation problem — it's a layout problem.** A perfectly translated screen with
frozen geometry is still broken. CLAUDE.md requires RTL from day one; retrofitting it after a
hundred views is the expensive path.

## 1. Never left/right — leading/trailing everywhere

```swift
// ✅ mirrors automatically
.padding(.leading, Spacing.md)
HStack(alignment: .firstTextBaseline) { … }
VStack(alignment: .leading) { … }
.multilineTextAlignment(.leading)
.transition(.move(edge: .leading))

// ❌ frozen geometry
.padding(.left, 16)
VStack(alignment: .trailing)   // ← only if you mean "the end", not "the right"
.multilineTextAlignment(.left)
```

Grep for `.left`, `.right`, `.leftToRight` and `alignment: .trailing` used to mean "right".

## 2. SF Symbols — semantic, not geometric

```swift
Image(systemName: "chevron.forward")    // ✅ mirrors in RTL
Image(systemName: "chevron.right")      // ❌ points the wrong way in Arabic
```

Same for `arrow.forward` / `arrow.backward`, `arrow.uturn.forward`. Use `.forward`/`.backward`
whenever the symbol means *next*/*previous*; use `.right`/`.left` only when it means an actual
compass direction.

## 3. Assets that convey direction

An imageset carrying an arrow, a swipe hint, or a reading-order illustration must mirror. Set
**Direction: Both, Mirrors** in the asset catalog, or:

```swift
Image.appSwipeHint.flipsForRightToLeftLayoutDirection(true)
```

## 4. What must NOT mirror

Mirroring everything is as wrong as mirroring nothing:

| Never mirror | Why |
|---|---|
| Media playback controls (play, fast-forward, scrubber) | Time flows one way in every locale |
| Logos and brand marks | It's a wordmark, not a layout |
| Phone numbers, URLs, email addresses, code | Always rendered LTR, even inside RTL text |
| Clock faces, musical notation, physical-object imagery | The object doesn't flip |

Progress views and sliders *do* mirror — but only if you use standard components. Custom ones
don't, which is the next section.

## 5. Custom drawing does not mirror for free

`layoutDirection` mirrors layout containers. It does **not** mirror `Canvas`, `Path`,
`rotationEffect`, `offset(x:)`, or a `GeometryReader`-computed x-position. Anything hand-drawn or
hand-positioned needs explicit handling:

```swift
@Environment(\.layoutDirection) private var direction

.offset(x: direction == .rightToLeft ? -dx : dx)
// or, for a whole custom shape:
.scaleEffect(x: direction == .rightToLeft ? -1 : 1, anchor: .center)
```

This is the failure that survives every review, because the surrounding layout looks correct.

## 6. Text: never concatenate

```swift
// ✅ the translator controls word order
Text(String(localized: "home_greeting_title \(name)", bundle: .module))

// ❌ freezes English order — breaks in RTL and in every SOV language
Text("Welcome back, " + name)
```

Numbers, dates, currency, and measurements go through `FormatStyle`, never manual formatting —
some RTL locales use Eastern Arabic numerals and different date orders, and `FormatStyle` handles
both.

Mixed-direction text (an Arabic sentence containing a Latin brand name or a phone number) resolves
correctly **only** if you let the system lay it out. Don't split the string to position parts.

## 7. Verify

Preview both directions for every component — alongside the light/dark and Dynamic Type matrix
required by [DesignSystem.md](../../../docs/modules/DesignSystem.md):

```swift
#Preview("RTL") {
    ComponentUnderTest()
        .environment(\.layoutDirection, .rightToLeft)
}
```

Previews aren't enough on their own. Run the app with Xcode's pseudolanguages —
**Edit Scheme → Run → Options → App Language**:

| Setting | Finds |
|---|---|
| **Right-to-Left Pseudolanguage** | mirroring bugs, without needing a translation |
| **Double-Length Pseudolanguage** | truncation and clipping that RTL will also expose |
| A real RTL locale (ar, he, fa, ur) | numeral systems, font fallback, line breaking |

**Test RTL together with Dynamic Type XXXL.** Each alone often passes; the combination is what
breaks real layouts.

## 8. Adding a language

1. Add it to every package's `.xcstrings` — all of them, not just the feature you're touching.
2. Run the localization test (CLAUDE.md §9): no key missing in any language.
3. Verify font fallback covers the script — a custom font with no Arabic glyphs silently falls
   back, and the mismatch is visible. Record coverage in
   [FONTS.md](../../notes/FONTS.md).
4. Check line-height and truncation: Arabic and Urdu ascenders/descenders need more vertical room
   than Latin at the same point size.

## 9. Before finishing

- [ ] No `.left` / `.right` in layout, padding, alignment, or transitions
- [ ] Directional SF Symbols use `.forward` / `.backward`
- [ ] Directional assets set to mirror; non-mirroring assets (logos, media controls) verified
      *not* mirrored
- [ ] Custom drawing, offsets, and rotations handle `layoutDirection` explicitly
- [ ] No string concatenation; all interpolation via `LocalizationValue`
- [ ] Numbers, dates, currency via `FormatStyle`
- [ ] Previews cover RTL for every component
- [ ] Run and checked under RTL pseudolanguage **and** at Dynamic Type XXXL
- [ ] Font covers the script; noted in [FONTS.md](../../notes/FONTS.md)
