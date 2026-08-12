# Style Guide

Every design token and component variant that exists, so nothing gets invented twice.

- **Maintained by:** targeted edit on every token or variant added, changed, or removed.
  A full rescan is the `/sync-app-notes` **command** — it runs only when you type it.
- **Read this when:** building or restyling any view — **before** writing a value.
- **Companions:** [ASSETS-COLORS.md](ASSETS-COLORS.md) (colour tokens + hex),
  [FONTS.md](FONTS.md) (families, registration, type tokens). This file owns everything else:
  spacing, radius, elevation, motion, and the component inventory.
- **Design rules** — why tokens exist and how components must behave —
  [DesignSystem.md](../../docs/modules/DesignSystem.md). This file is the *registry*; that one is
  the *rules*.

> **Check here before adding a value.** A near-duplicate token is worse than a slightly wrong reuse:
> two radii four points apart will never be reconciled, and every screen after them inherits the
> ambiguity. If nothing here fits, that is a decision to bring to the user — not a value to invent.

> Empty until `Packages/DesignSystem` exists. `/sync-app-notes` populates it by scanning the token
> declarations and the `#Preview` blocks.

---

## Spacing

The only permitted spacing values. A view needing something else needs a **token added here**, agreed
with the user — not a literal at the call site.

| Token | Value | Use for | Declared in — *what's there* |
|---|---|---|---|
| — | — | — | — |

<!-- Example, delete when real tokens land:
| `Spacing.xs` | 4 | icon-to-label, tight inline pairs | `Packages/DesignSystem/Sources/DesignSystem/Tokens/Spacing.swift` — the scale, one enum |
| `Spacing.sm` | 8 | between related rows | same file |
| `Spacing.md` | 16 | default gutter, card padding | same file |
| `Spacing.lg` | 24 | between sections | same file |
| `Spacing.xl` | 40 | screen top/bottom margins | same file |
-->

## Radius

| Token | Value | Use for | Declared in — *what's there* |
|---|---|---|---|
| — | — | — | — |

<!--
| `Radius.control` | 8 | buttons, fields, chips | `Packages/DesignSystem/Sources/DesignSystem/Tokens/Radius.swift` — the scale |
| `Radius.card` | 12 | cards, sheets, tiles | same file |
-->

## Elevation

**Dark mode is why this is a token and not a shadow.** Shadows are invisible on black, so elevation
is carried by surface colour; the shadow is a light-appearance affordance layered on top
([dark-light-mode](../skills/dark-light-mode/SKILL.md)).

| Level | Surface token | Shadow (light only) | Use for | Declared in — *what's there* |
|---|---|---|---|---|
| — | — | — | — | — |

<!--
| 0 | `surface` | none | page background | `Packages/DesignSystem/Sources/DesignSystem/Tokens/Elevation.swift` — level → surface + shadow |
| 1 | `surfaceElevated` | y1 blur2 8% | cards, raised rows | same file |
| 2 | `surfaceElevated` | y4 blur12 12% | sheets, popovers | same file |
-->

## Motion

Every duration and curve. All of them collapse to instant under **Reduce Motion** — that is a
property of the token, not something each call site remembers.

| Token | Duration | Curve | Use for | Declared in — *what's there* |
|---|---|---|---|---|
| — | — | — | — | — |

<!--
| `Motion.standard` | 0.25s | easeInOut | most state changes | `Packages/DesignSystem/Sources/DesignSystem/Tokens/Motion.swift` — durations + Reduce Motion collapse |
| `Motion.emphasized` | 0.4s | spring(0.8) | sheet present/dismiss | same file |
-->

## Typography scale

Families and registration live in [FONTS.md](FONTS.md). This table is the **semantic scale** — which
token to reach for, and what it maps to.

| Token | Role | Relative to | Declared in — *what's there* |
|---|---|---|---|
| — | — | — | — |

<!--
| `Font.appLargeTitle` | screen titles | `.largeTitle` | `Packages/DesignSystem/Sources/DesignSystem/Tokens/Typography.swift` — tokens, all with relativeTo: |
| `Font.appBody` | body copy | `.body` | same file |
-->

## Components

The inventory. **Extend an existing component before adding a near-duplicate** — two that differ by a
corner radius are one component and a parameter.

| Component | Variants | States covered | File — *what's there* |
|---|---|---|---|
| — | — | — | — |

<!--
| `PrimaryButton` | filled, tinted, destructive | default, pressed, disabled, loading | `Packages/DesignSystem/Sources/DesignSystem/Components/PrimaryButton.swift` — the button + its full preview matrix |
| `ContentStateView` | — | idle, loading, loaded, empty, offline, failed, paging | `Packages/DesignSystem/Sources/DesignSystem/Components/ContentStateView.swift` — renders every ContentState so features supply only loaded content |
-->

## Using this as an index

```bash
# does a token for this already exist? — run BEFORE writing any value
grep -in "radius\|spacing\|elevation" .claude/notes/STYLE-GUIDE.md

# every component and the file that defines it, each with a note
grep -n "Components/" .claude/notes/STYLE-GUIDE.md

# a value looking for a home — find the nearest existing token
grep -nE '\| (4|8|12|16|24|40) \|' .claude/notes/STYLE-GUIDE.md
```

## Open style questions

Style the user has not yet decided. **Do not invent an answer to close a row here** — an unanswered
question is honest; a silently chosen value becomes precedent.

| Question | Blocked work | Asked on |
|---|---|---|
| Visual language across iOS 17 and macOS 26 — native per platform, or one owned look | Any token that would differ by platform ([DECISIONS.md](../../docs/DECISIONS.md)) | — |

## Gaps

| Finding | Where | Noted |
|---|---|---|
| — | — | — |

`/sync-app-notes` flags: a literal spacing/radius/duration in a feature; two tokens within ~20% of
each other (a near-duplicate); a component with no preview matrix; a token declared but never used;
a motion token that does not honour Reduce Motion; and any component whose variants are not listed
here.
