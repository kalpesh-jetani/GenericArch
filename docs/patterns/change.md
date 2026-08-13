# Pattern — change

**Not a skill yet.** It becomes one when this repo has the code it describes — `/learn change`
promotes it. Until then it is reference: read it when the situation arises.

- **Promote when:** the code it governs exists
- **Trigger phrases it would claim:** Extend something that already exists — the ordinary edit. Fires on "add a field", "add an endpoint", "add an error case", "handle another state", "support one more parameter", "extend this to also…". …

---

# An ordinary change

Most edits are small, and small edits are where the rules quietly get skipped. Nobody forgets the
empty state on a new screen; everybody forgets it on the field they added on Friday.

**Index before grep** ([PATTERN-SEARCH.md](../PATTERN-SEARCH.md)) — `FEATURES.md` and
`NAVIGATION.md` map a screen to its files without a search.

## 1. Which layer does this actually touch?

Name it before editing. A change that touches more layers than expected is usually two changes.

| Adding | Starts at | Also needs |
|---|---|---|
| A field on a response | The DTO, then the domain model | The mapper, and a test for it |
| A request parameter | The endpoint type — one type per endpoint | Nothing else if the endpoint is declarative |
| An error case | The layer's own error, then its `AppError` mapping | A localized message key, and `isRetryable` set |
| A state to a screen | `ContentState` — never a new boolean | The `ContentStateView` branch and its copy |
| A field to a form | The view model | A localized label, a token for spacing, focus order |
| A value to persist | The relevant `Storing` protocol | Nothing in the feature — it must not name an engine |

## 2. The five things a small change forgets

Walk these every time. They cost seconds now and a review round later.

1. **Localized key** — any new user-visible text, including an error message and an
   `accessibilityLabel` (§2.3).
2. **The state you did not add** — a new failure path usually means a new `ContentState` case, not
   an `if` in the view (§2.5).
3. **The error mapping** — a new thrown error needs its `AppError` case and `isRetryable` set
   deliberately ([Core.md](../modules/Core.md)).
4. **The mock** — if you added a protocol requirement, the mock beside it must satisfy it, or every
   test using it stops compiling.
5. **The note row** — a new screen, route, asset, colour, font or token changes an inventory. Edit
   that row in the same change; the full rescan is not yours to run (CLAUDE.md §5).

## 3. Extend, do not duplicate

- A near-copy of an existing view is a parameter on that view.
- A second token four points from an existing one is the existing one — `style-guide`.
- A second endpoint differing by one field is one endpoint with an optional.

If duplication is genuinely right, say why in one clause; otherwise you are adding vocabulary that
nobody will reconcile later.

## 4. Scope discipline

**Change what was asked and say what you noticed.** A field addition that arrives with a refactor of
the surrounding view model is two changes in one diff, and the second one was not reviewed.

If the change is blocked by something broken, that is `debug` — not something to fix in passing.

## Before finishing

- [ ] Named the layer, and it was the layer that owns the behaviour
- [ ] No raw string, no literal spacing/colour, no new boolean beside `ContentState`
- [ ] Error mapped with `isRetryable` set on purpose
- [ ] Mock updated if a protocol changed
- [ ] The affected `.claude/notes/` row edited in this change
- [ ] Handed over the test command rather than running it (§2.12)
