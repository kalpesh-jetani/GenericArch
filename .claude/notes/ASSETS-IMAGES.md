# Assets — Images

Every image asset, by catalog group, with the package that owns it.

- **Maintained by:** targeted edit on every asset insertion or deletion.
  A full rescan is the `/sync-app-notes` skill, which runs **only with your approval**.
- **Read this when:** looking for an existing asset before adding a near-duplicate, or checking
  which package an image lives in.
- **Rule:** images are referenced through typed accessors, never a raw string
  (`Image.appEmptyInbox`, not `Image("empty_inbox")`). A raw name is a runtime blank, not a
  compile error.

> Empty until the first asset catalog exists. `/sync-app-notes` populates it by scanning
> `**/*.xcassets/**/*.imageset`.

---

## Naming convention

`<group>_<subject>_<variant>` — lowercase, `_`-joined, matching the localization key style
(CLAUDE.md §2.3 sibling convention).

```
empty_inbox            onboarding_welcome_hero
empty_search           onboarding_permissions_camera
error_generic          avatar_placeholder
```

No spaces, no camelCase, no `@2x` in the name (that's the slot, not the name).

## Inventory

| Group | Asset name | Owner package | Rendering mode | Dark variant | Used by |
|---|---|---|---|---|---|
| — | — | — | — | — | — |

<!--
| EmptyStates | `empty_inbox`      | DesignSystem | template | n/a       | ContentStateView |
| EmptyStates | `empty_search`     | DesignSystem | template | n/a       | ContentStateView |
| Onboarding  | `onboarding_hero`  | FeatureOnboarding | original | ✅ | WelcomeView |
-->

- **Rendering mode** — `template` for anything that should take a tint (most icons); `original`
  for illustrations and photography. Wrong mode is the most common asset bug.
- **Dark variant** — required for any `original` asset that carries its own background. A single
  light-only illustration on a dark background is a visible defect, not a nice-to-have.
- **Used by** — one consumer means it may belong in that package, not in DesignSystem.

## Prefer SF Symbols

Before adding an image, check whether an SF Symbol does the job. Symbols scale with Dynamic Type,
mirror correctly in RTL, and cost nothing in bundle size.

Use directional symbols semantically: `chevron.forward`, never `chevron.right` — the latter does
not mirror in RTL ([LocalizationKit.md](../../docs/modules/LocalizationKit.md)).

| SF Symbol in use | Where | Why not an asset |
|---|---|---|
| — | — | — |

## Package resources

Assets inside an SPM package resolve against `.module`, not `.main`:

```swift
Image("empty_inbox", bundle: .module)      // inside a package
```

Getting this wrong renders a blank view with no error — which is why typed accessors exist.
Declare the catalog in `Package.swift`:

```swift
.target(name: "DesignSystem", resources: [.process("Resources/Assets.xcassets")])
```

## Gaps

| Finding | Where | Noted |
|---|---|---|
| — | — | — |

`/sync-app-notes` flags: unused assets, assets referenced by raw string, `original`-mode assets
with no dark variant, duplicate images across packages, and app-icon/launch-asset slots that are
incomplete.
