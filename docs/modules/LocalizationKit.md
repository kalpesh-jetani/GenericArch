# LocalizationKit

Shared `common_*` strings, typed accessors, and the key convention every package follows.

- **Package:** `Packages/LocalizationKit` (local)
- **Used by:** every package that renders text — features, [DesignSystem](DesignSystem.md), and
  [Messaging](Messaging.md). Each package owns its *own* catalog; this package owns only the
  shared strings and the tooling.
- **When to read this:** adding any user-visible string, adding a language, or handling plurals,
  dates, numbers, or currency.

---

## The rule

**Every user-visible string is localized. Zero exceptions** — error text, empty-state copy,
accessibility labels, button titles, placeholder text. CLAUDE.md §2.3.

If it can appear on screen or be read aloud by VoiceOver, it has a key.

## Key format

Lowercase, `_`-joined, hierarchical: **`<feature>_<screen>_<element>_<role>`**

```
auth_login_email_placeholder
auth_login_submit_button
auth_login_error_invalid_credentials
home_feed_empty_title
home_feed_empty_body
common_error_no_internet_message
common_action_retry
common_action_cancel
```

- Shared strings use the **`common_`** prefix and live in this package. A string used by two
  features is a `common_` string — duplicating it in both catalogs guarantees they drift.
- The hierarchy is not decoration: it's what makes an unused key findable and a missing
  translation reviewable in feature order.
- Never rename a shipped key to "clean it up" — translators key off it. Add the new one, migrate,
  delete the old in a separate change.

## String Catalogs

`.xcstrings`, **one per package**, resolved against that package's bundle.

```swift
// Inside a package, the bundle is NOT .main
Text(String(localized: "auth_login_submit_button", bundle: .module))
```

Getting the bundle wrong is the single most common localization bug in a multi-package app: the
string silently falls back to the key, and the key looks close enough to real copy to survive
review. The typed accessors below exist to make it impossible.

## Typed accessors, never raw strings at call sites

```swift
Text(L10n.Auth.Login.submitButton)          // ✅
Text("auth_login_submit_button")            // ❌ — no compile-time check, wrong bundle
```

The `L10n` tree is generated from the catalog per package. A key that doesn't exist doesn't
compile; a deleted key breaks the build instead of shipping as visible gibberish.

## Interpolation, plurals, formats

```swift
// ✅ LocalizationValue — the translator controls word order
Text(String(localized: "home_greeting_title \(userName)", bundle: .module))

// ❌ concatenation — unlocalizable, breaks in RTL and in every SOV language
Text("Hello, " + userName)
```

- **Plurals** go through the catalog's plural variations. Never `count == 1 ? "item" : "items"` —
  that's wrong in most languages, several of which have more than two plural forms.
- **Dates, numbers, currency, measurements** go through `FormatStyle`, never manual formatting.
  `Text(price, format: .currency(code: locale.currency))`.
- **Never build a sentence from fragments.** One key per complete sentence.

## RTL and Dynamic Type from day one

- `leading`/`trailing`, never `left`/`right`. Same for padding, alignment, and chevrons.
- Directional symbols use their `.rtl` variants automatically only if you use SF Symbols
  semantically (`chevron.forward`, not `chevron.right`).
- Every screen verified at Dynamic Type XXXL without truncation or clipping, and mirrored in RTL.
  Enforced by the preview set in [DesignSystem](DesignSystem.md).

## Testing

A localization test per package (CLAUDE.md §9) asserts:

1. No key present in the base language is missing in any other language.
2. No key is unused — an orphan key is a translation someone paid for and no one shows.
3. No view file contains a raw user-facing literal. Grep-based, runs in CI, fails the build.

Rule 3 is the one that actually holds the line. Without it §2.3 degrades within a sprint.
