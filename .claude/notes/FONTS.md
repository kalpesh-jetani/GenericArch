# Fonts

Every font family shipped, how it is registered, and the typed accessor that exposes it.

- **Companion:** [STYLE-GUIDE.md](STYLE-GUIDE.md) — spacing, radius, elevation, motion,
  component variants. This file owns only its own slice.
**Read it when** adding a font file, adding a type token, or debugging a font that renders as
  system-default.
- **Rule:** no `Font.custom("Inter-Bold", size: 17)` at a call site. Features use type tokens
  (`Font.appTitle`); only DesignSystem names a file.

> Empty until `Packages/DesignSystem` ships a font — `/sync-app-notes` populates it.

---

## Registration — check this first when a font "doesn't work"

Registration differs by where the file lives, and this is the single most common cause of a
custom font silently falling back to system.

| File location | iOS registration | macOS registration |
|---|---|---|
| App bundle | `UIAppFonts` array in `Info.plist` | `ATSApplicationFontsPath` in `Info.plist` |
| **SPM package resource** | **`Info.plist` does not apply** — register at runtime | same — register at runtime |

**`UIAppFonts` only reads the main bundle.** A font shipped as a resource of
`Packages/DesignSystem` is *not* registered by adding it to the app's `Info.plist` — the app
bundle doesn't contain it. It must be registered programmatically at launch:

```swift
// DesignSystem — called once, before the first view renders
enum FontRegistrar {
    static func registerAll() {
        for url in Bundle.module.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? [] {
            var error: Unmanaged<CFError>?
            // Not fatal — a missing font degrades to system, it must never crash the app (§2.7)
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                logger.log(.warning, "font registration failed", ["file": .public(url.lastPathComponent)])
            }
        }
    }
}
```

Registration is idempotent and must run before the first view renders — call it from the
composition root, not lazily from a view.

## Registered families

| Family | PostScript names | Weights | File | Location | Registered via | Verified |
|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — |

<!--
| Inter | Inter-Regular, Inter-Medium, Inter-SemiBold, Inter-Bold | 400/500/600/700 | Inter.otf | DesignSystem/Resources/Fonts | CTFontManager (runtime) | ✅ |
-->

**PostScript name ≠ filename ≠ display name.** `Inter-Bold.otf` may register as `Inter-Bold`,
`InterBold`, or `Inter Bold` depending on how it was built. Record the *PostScript* name — that is
what `Font.custom` takes. Dump the truth rather than guessing:

```swift
// DEBUG only — prints what actually registered
for family in UIFont.familyNames.sorted() {
    print(family, UIFont.fontNames(forFamilyName: family))
}
```

## Type tokens

The only names a feature may use. Every token maps to a family, a weight, and a **`TextStyle`** —
never a fixed point size, or Dynamic Type stops working.

| Token | Family | Weight | Relative to | Used for |
|---|---|---|---|---|
| — | — | — | — | — |

<!--
| `appLargeTitle` | Inter | Bold      | .largeTitle | screen titles |
| `appTitle`      | Inter | SemiBold  | .title2     | section headers |
| `appBody`       | Inter | Regular   | .body       | body copy |
| `appCaption`    | Inter | Regular   | .caption    | metadata, timestamps |
-->

```swift
// ✅ scales with Dynamic Type to XXXL
static let appTitle = Font.custom("Inter-SemiBold", size: 22, relativeTo: .title2)

// ❌ frozen — Dynamic Type stops working (docs/DONE.md)
static let appTitle = Font.custom("Inter-SemiBold", size: 22)
```

`relativeTo:` is not optional. A fixed size is an accessibility defect that passes every build.

## Licensing

Track it — a font shipped without redistribution rights is a legal problem, not a technical one.

| Family | License | Redistribution allowed | Source |
|---|---|---|---|
| — | — | — | — |

## Gaps

| Finding | Where | Noted |
|---|---|---|
| — | — | — |

`/sync-app-notes` flags: font files present but never registered, `UIAppFonts` entries whose file
is missing from the bundle, package fonts relying on `Info.plist` (which silently does nothing),
`Font.custom` without `relativeTo:`, raw `Font.custom` at a feature call site, and registered
families with no type token.
