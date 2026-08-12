# Messaging — system prompt & message redirection

Every user-facing interruption routes through **one presenter** and renders in **our own UI**.

- **Protocol (`MessagePresenting`, `AppMessage`):** [Core](Core.md), so any layer can request a
  message without importing UI.
- **Host overlay and rendering:** `Packages/DesignSystem`.
- **Used by:** every feature — as a *requester* only. Also used by the app shell, which mounts
  the single host overlay.
- **When to read this:** showing any message, error, confirmation, or permission rationale; or
  when tempted to write `.alert`.

---

## The rule

**Nothing calls `.alert`, `.confirmationDialog`, or any system-styled message surface.**
CLAUDE.md §2.4. Features **request**; they never present.

```swift
public protocol MessagePresenting: Sendable {
    func present(_ message: AppMessage) async -> AppMessage.Outcome
}

public struct AppMessage: Sendable {
    public enum Style: Sendable { case toast, banner, sheet, blockingDialog, inline }
    public enum Severity: Sendable { case info, success, warning, error }
    public let titleKey: LocalizedKey
    public let messageKey: LocalizedKey?
    public let style: Style
    public let severity: Severity
    public let actions: [Action]     // localized title + role + handler
}
```

`present` is `async` and returns the `Outcome`, so a confirmation reads top-to-bottom instead of
scattering into callbacks:

```swift
let outcome = await presenter.present(.confirmDelete(itemName: name))
guard outcome == .confirmed else { return }
try await repository.delete(id)
```

## One host, at the app root

The overlay is mounted **once**, above the navigation container, in the app shell. Not per screen
— a per-screen host means a message dies with the screen that requested it, and sheet-over-sheet
conflicts become unfixable.

## Queued and de-duplicated

A burst of failures shows **one** message, not five. The host coalesces by
`(titleKey, messageKey, severity)` within a short window and shows a single instance.

This is what makes CLAUDE.md §2.4's companion rule — never present two errors for one user
action — structurally true rather than a thing each feature has to remember.

Ordering: `blockingDialog` preempts; `toast` and `banner` queue; `inline` never queues, because it
belongs to a specific view and is rendered in place.

## Choosing a style

| Style | Use for | Never use for |
|---|---|---|
| `inline` | validation next to the field that failed | anything the user must acknowledge |
| `toast` | transient success confirmation | errors that need action |
| `banner` | persistent condition (offline, degraded sync) | one-off events |
| `sheet` | a choice with more than two options, or explanatory copy | a simple yes/no |
| `blockingDialog` | destructive confirmation, forced update | anything recoverable |

**Not every error deserves a message.** A failed load belongs in
`ContentStateView`'s `failed` state ([DesignSystem](DesignSystem.md)) — not a dialog on top of an
empty screen. Route to the presenter only when the user must acknowledge or decide something.

## Permission pre-prompts

Notifications, camera, location, photos, contacts: always show **our** pre-prompt explaining why,
*before* the OS prompt fires. The OS prompt can be shown exactly once per install — burning it on
a user who doesn't understand the ask is unrecoverable.

Denial routes to our own settings-redirect UI, never a dead end.

```swift
let outcome = await presenter.present(.cameraRationale)
guard outcome == .confirmed else { return }         // user declined OURS; OS prompt never fires
let granted = await permissions.request(.camera)
if !granted { await presenter.present(.cameraDeniedOpenSettings) }
```

## OS-owned surfaces

Share sheet, OS permission dialog, StoreKit, document picker — we cannot restyle these. Wrap each
in a `SystemSurface` type so call sites stay uniform and mockable, and so the inventory of
un-restylable surfaces is greppable.

```swift
public protocol SystemSurfacePresenting: Sendable {
    func present(_ surface: SystemSurface) async -> SystemSurface.Outcome
}
```

## Testing

`SpyMessagePresenter` records every request and returns a scripted outcome. Assert on **what was
requested**, not on rendered UI — that's the point of the split.

```swift
#expect(presenter.requests.count == 1)              // catches double-presentation regressions
#expect(presenter.requests.first?.severity == .error)
```
