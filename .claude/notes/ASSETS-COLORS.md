# Assets — Colors

Every color token, with its light and dark hex values.

- **Maintained by:** targeted edit on every color insertion or deletion.
  A full rescan is the `/sync-app-notes` **command** — it runs only when you type it.
- **Companion:** [STYLE-GUIDE.md](STYLE-GUIDE.md) — spacing, radius, elevation, motion,
  component variants. This file owns only its own slice.
- **Read this when:** adding a token, checking an existing one before defining a near-duplicate,
  or auditing contrast.
- **Rule:** zero literal colors in features (CLAUDE.md §2 / DesignSystem). A feature that needs a
  color it can't find here needs a **token added here**, not a `Color(hex:)` at the call site.

> Empty until `Packages/DesignSystem` exists. `/sync-app-notes` populates it by scanning
> `**/*.xcassets/**/*.colorset/Contents.json` and reading the sRGB components.

---

## Naming is semantic, not descriptive

`surfaceElevated`, not `grayLight`. A descriptive name becomes a lie the first time Dark Mode
disagrees with it — `grayLight` that resolves to `#1C1C1E` in dark is actively misleading.

## Inventory

| Token | Light | Dark | Role | Owner |
|---|---|---|---|---|
| — | — | — | — | — |

<!--
| `appPrimary`       | `#0A84FF` | `#0A84FF` | primary action, links      | DesignSystem |
| `surface`          | `#FFFFFF` | `#000000` | base background            | DesignSystem |
| `surfaceElevated`  | `#F2F2F7` | `#1C1C1E` | cards, sheets, raised rows | DesignSystem |
| `textPrimary`      | `#000000` | `#FFFFFF` | body copy                  | DesignSystem |
| `textSecondary`    | `#3C3C43` | `#EBEBF5` | captions, metadata         | DesignSystem |
| `separator`        | `#C6C6C8` | `#38383A` | hairlines                  | DesignSystem |
| `severityError`    | `#FF3B30` | `#FF453A` | error state, destructive   | DesignSystem |
| `severityWarning`  | `#FF9500` | `#FF9F0A` | warning banner             | DesignSystem |
| `severitySuccess`  | `#34C759` | `#30D158` | success toast              | DesignSystem |
-->

**Light and dark are defined together, in the same declaration.** One can't be added without the
other — a colorset with only an "Any" appearance is a bug this table makes visible.

## Contrast

Body text must be ≥ **4.5:1** against the surface it sits on (CLAUDE.md §8), in **both**
appearances — a token that passes in light and fails in dark is the common failure.

**There is deliberately no contrast column here.** The ratio is asserted by a token test, and a
hand-maintained column duplicating a test result drifts and then gets believed. The test is the
record; failures surface in `Gaps` below.

Assert it rather than checking by eye:

```swift
#expect(Color.textSecondary.contrastRatio(on: .surface, .light) >= 4.5)
#expect(Color.textSecondary.contrastRatio(on: .surface, .dark)  >= 4.5)
```

**Never encode meaning in color alone** — every semantic color pairs with a symbol or text label.
`severityError` red with no icon fails for the ~8% of users with colour vision deficiency.

## System colors

Prefer a system color where one fits — they adapt to Increase Contrast and future OS changes for
free. Record the mapping so a swap to a custom value later is a one-line change:

| Token | Backed by | Reason for custom value |
|---|---|---|
| — | — | — |

## Package resources

Colors inside an SPM package resolve against `.module`:

```swift
Color("appPrimary", bundle: .module)      // wrapped by the typed accessor, never called directly
```

## Gaps

| Finding | Where | Noted |
|---|---|---|
| — | — | — |

`/sync-app-notes` flags: colorsets missing a dark appearance, literal `Color(red:green:blue:)` or
`Color(hex:)` in a feature, tokens with no consumer, near-duplicate hex values across tokens, and
any text token below 4.5:1 in either appearance.
