---
name: style-guide
description: Keep the design token registry authoritative when styling UI — spacing, padding, radius, elevation, shadow, motion durations, the type scale, and component variants. Fires whenever a visual value is about to be written or changed: "round the corners", "tighten the spacing", "make this bigger", "add a variant", "restyle this", or any request that would introduce a literal size, radius, shadow or duration. Looks up the tokens that already exist and proposes one that fits rather than admitting a near-duplicate; asks the user when nothing fits; registers the agreed token in the same change. Related skills: dark-light-mode, new-feature.
---

# Style guide

The registry is [STYLE-GUIDE.md](../../notes/STYLE-GUIDE.md) — spacing, radius, elevation, motion,
type scale, components. Colours are [ASSETS-COLORS.md](../../notes/ASSETS-COLORS.md); font families
and registration are [FONTS.md](../../notes/FONTS.md). The rules behind all of it are
[DesignSystem.md](../../../docs/modules/DesignSystem.md).

**The order is: look up → propose existing → ask → register.** Never invent a value, and never add a
token without checking whether one already fits.

---

## 1. Look up before writing anything

```bash
grep -in "radius\|spacing\|elevation\|motion" .claude/notes/STYLE-GUIDE.md
grep -in "<token-name>" .claude/notes/ASSETS-COLORS.md .claude/notes/FONTS.md
```

Do this **before** the first value is typed, not after. Once a literal is in a view it tends to stay,
and the next screen copies it.

## 2. If something already fits — propose it, don't add

This is the step that keeps a design system from rotting. **A near-duplicate token is worse than a
slightly wrong reuse:** two radii four points apart will never be reconciled, and every screen after
them inherits the ambiguity.

When the request is close to an existing token, say so and recommend reuse:

> You asked for a 10pt corner radius. `Radius.card` is 12 and is what cards, sheets and tiles already
> use. Three options: **use `Radius.card`** (recommended — the difference is invisible at this size
> and it keeps one card shape), **change `Radius.card` to 10** (affects 6 existing views — I can list
> them), or **add a new token** if this is genuinely a different kind of surface, in which case it
> needs a name that says what it's for.

Rules for this proposal:

- **Name the consequence of each option.** Changing an existing token is a global restyle — say how
  many call sites, from a grep. Adding one is permanent vocabulary.
- **Recommend reuse when the difference is imperceptible**; recommend a new token when the thing is
  genuinely a different concept. "It's 2pt off" is not a concept.
- If the user's instruction *matches* an existing token, just use it and say which — no question
  needed.

## 3. If nothing fits — ask, with the neighbours shown

Never pick a value silently. Ask, and make the choice easy by showing what already exists around it:

> No elevation token covers a floating action button. The scale today is level 1 (cards) and level 2
> (sheets). Should this be level 2, or a new level 3 above both?

Give options derived from **the existing scale**, not from arbitrary numbers. A scale with 4/8/16/24
should not gain a 14.

**Do not close an [Open style questions](../../notes/STYLE-GUIDE.md) row to unblock yourself.** An
unanswered question is honest; a silently chosen value becomes precedent that the next screen copies.

## 4. Register it in the same change

A token agreed and not written down is a token that gets re-invented next week.

- Add the row to the right table in STYLE-GUIDE.md — with the **declaring file and a note saying
  what's there**, never a bare path.
- Colour → also [ASSETS-COLORS.md](../../notes/ASSETS-COLORS.md) with **both** hexes. Type token →
  also [FONTS.md](../../notes/FONTS.md).
- New component or variant → the Components table, with its variants and the states it covers.
- Record the decision with `/decide` if it changes the vocabulary rather than extending it.

Targeted edits only. This is not a `/sync-app-notes` run.

## 5. What a new token must satisfy before it ships

- **Semantic name, not descriptive.** `surfaceElevated`, not `grayLight`; `Spacing.sectionGap`, not
  `Spacing.twentyFour`. A descriptive name becomes a lie the first time it changes.
- **Both appearances defined together** if it's a colour — run `dark-light-mode`.
- **Motion honours Reduce Motion**, in the token, not at the call site.
- **Type tokens carry `relativeTo:`** or Dynamic Type silently stops working.
- **Components get the full preview matrix** — states × light/dark × RTL × XXXL × disabled. That
  matrix is the snapshot suite (CLAUDE.md §9), so it is written once and used twice.

## Before finishing

- [ ] Looked up the registry **before** writing a value
- [ ] Proposed an existing token where one fit, with the consequence of each option
- [ ] Asked rather than invented where nothing fit
- [ ] Registered every agreed token/variant, with its declaring file **and a note**
- [ ] No literal spacing, radius, duration or colour left in a feature
- [ ] `./Scripts/check.sh` clean
