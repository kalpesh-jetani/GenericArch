# NotificationKit

Push registration, payload handling, local notifications, and the payload → `Route` bridge.

- **Package:** `Packages/NotificationKit` (local)
- **Used by:** the app shell (registration, OS callbacks) and any feature that schedules a local
  notification. Depends on [Core](Core.md) and [Navigation](Navigation.md).
- **When to read this:** adding push support, handling a payload, deep-linking from a notification,
  or debugging "notifications don't arrive".

---

## Protocols

```swift
public protocol PushRegistering: Sendable {
    func requestAuthorization() async -> PushAuthorization      // OUR type, not UNAuthorizationStatus
    func registerForRemoteNotifications() async
    var deviceTokenUpdates: AsyncStream<DeviceToken> { get }
}

public protocol NotificationHandling: Sendable {
    /// Parses a payload into routes. Pure and total — no side effects, unit-testable with no app.
    func routes(for payload: NotificationPayload) -> [Route]?
    func handle(_ payload: NotificationPayload, appState: NotificationAppState) async
}
```

Same shape as the deep-link parser ([Navigation.md](Navigation.md)) on purpose: **a notification is
a deep link with a different delivery mechanism.** One parser shape, one route model, one place
authorization is checked.

---

## Permission — the pre-prompt is mandatory

CLAUDE.md §2.4 and [Messaging.md](Messaging.md): **our** rationale first, the OS prompt second.

```swift
let outcome = await presenter.present(.notificationsRationale)
guard outcome == .confirmed else { return }        // declined ours; OS prompt never fires
let auth = await push.requestAuthorization()
if auth == .denied { await presenter.present(.notificationsDeniedOpenSettings) }
```

The OS prompt can be shown **once per install**. Burning it on a user who doesn't yet understand the
value is unrecoverable — they must then be walked to Settings, and most won't go.

Ask at a moment where the value is obvious, not at launch. "Enable notifications" on first run is
the single most reliably denied prompt in iOS.

Provisional authorization (`.provisional`) delivers quietly to Notification Center without a prompt
— worth considering, and worth deciding deliberately rather than by omission.

---

## Device token

- The token **changes** — on restore, reinstall, and unpredictably. Treat every
  `deviceTokenUpdates` value as authoritative and re-upload it.
- Upload it keyed to the user, not the device, and **clear it on sign-out** — otherwise the next
  user on that device receives the previous user's notifications. That's a privacy incident, not a
  bug.
- Registration failures are normal (no network, simulator, revoked permission). Log at `debug`,
  never surface to the user.
- The token is not a secret, but it is an identifier — it does not go in logs unredacted
  ([LoggingKit.md](LoggingKit.md)).

---

## Environment split — the classic failure

APNs sandbox and production are **different services with different tokens**. A token minted against
sandbox is rejected by production, silently, with no user-visible symptom.

| Scheme | APNs environment | `aps-environment` entitlement |
|---|---|---|
| DEV | sandbox | `development` |
| TEST | sandbox | `development` |
| BETA | **production** | `production` |
| PROD | production | `production` |

TestFlight builds always use **production** APNs, including internal testing. A BETA build that
receives nothing while DEV works is nearly always this ([SCHEMES.md](../../.claude/notes/SCHEMES.md)).

---

## Handling a payload — three app states, three behaviors

```swift
public enum NotificationAppState: Sendable {
    case foreground      // app visible
    case background      // running, not visible
    case coldLaunch      // launched BY the notification
}
```

| State | Behavior |
|---|---|
| `foreground` | **Do not** navigate. Present a banner via `MessagePresenting`; navigate only if the user taps it. Yanking someone away from what they're doing is the most-complained-about push behavior |
| `background` | Update state silently, badge, cache the payload. No navigation — the user hasn't asked for it |
| `coldLaunch` | Navigate — this launch *is* the user's tap. Apply the route after first frame, after the launch gates ([AppShell.md](AppShell.md)) |

Cold-launch routing must survive the gate order: force-update supersedes it, and it applies after
auth resolves. A route applied before auth lands on a screen that then gets replaced.

---

## Silent push

`content-available: 1` wakes the app for background work. Constraints that are usually learned the
hard way:

- **Not guaranteed and heavily throttled** by the system based on user behavior and battery. Never
  build a feature that requires delivery — treat it as an optimization over polling.
- Budget is seconds. Do one bounded thing, call the completion, exit.
- Requires the `remote-notification` background mode, which must be declared *and used*, or review
  rejects it ([PROJECT.md](../../.claude/notes/PROJECT.md)).

---

## Rich notifications

A **Notification Service Extension** is a separate target with its own bundle ID. It links packages
directly and never imports the app ([PROJECT.md](../../.claude/notes/PROJECT.md)) — typically
`Core` plus `ImageCache` for attachment download.

It has ~30 seconds and a small memory budget. Ship a `serviceExtensionTimeWillExpire` fallback that
delivers the unmodified content — a timeout with no fallback drops the notification entirely.

---

## Local notifications

Same protocol surface, no server. Used for reminders and scheduled prompts.

- Content is localized through the catalog ([LocalizationKit.md](LocalizationKit.md)) — a
  notification body in English on an Arabic device is a visible defect, and it is the most commonly
  missed localization surface because it renders outside the app.
- Cancel on sign-out and on the state change that made it irrelevant. A reminder for a deleted item
  is worse than no reminder.

---

## Testing

`MockPushRegistering` and `SpyNotificationHandler` ship in the package.

Because `routes(for:)` is pure, the whole routing layer is testable with no app, no permission, and
no APNs:

```swift
#expect(handler.routes(for: .fixture("new_message")) == [.homeFeed, .thread(id: "42")])
#expect(handler.routes(for: .fixture("malformed")) == nil)   // never crashes, never guesses
```

Assert the three app states separately — foreground *not* navigating is the behavior most likely to
regress, and it never shows up in a manual test because testers tap from the background.
