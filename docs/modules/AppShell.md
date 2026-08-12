# AppShell

The app targets: composition root, scene phase, state restoration, and launch gates.

- **Package:** none — this is the `App/GenericArch-iOS` and `App/GenericArch-macOS` targets
  themselves (CLAUDE.md §4.1).
- **Used by:** nothing. Nothing imports the shell; the shell imports everything.
- **When to read this:** wiring the composition root, handling background/foreground, implementing
  state restoration, or adding a launch-time gate such as force-update.

---

## The shell is thin — and this is the enforceable part

`@main`, scene declaration, the composition root, OS-callback adaptors, and the message host
overlay. **No business logic, no networking, no view beyond containers.** Anything you're tempted
to put here belongs in a package.

The test: if a line of shell code would be worth unit-testing, it's in the wrong place. The shell is
verified by the app launching, not by tests.

---

## Composition root

The only place live concrete types are constructed (CLAUDE.md §2.6, [DIKit.md](DIKit.md)).

```swift
@main
struct GenericArchApp: App {
    private let container: DIContainer

    init() {
        FontRegistrar.registerAll()                    // before first render — FONTS.md
        var builder = DIContainerBuilder()
        builder.register(AppEnvironmentKey.self, AppEnvironment.resolved())
        builder.register(HTTPClientKey.self, URLSessionHTTPClient(config: .default))
        …
        container = builder.build()
        #if DEBUG
        print(container.debugDescription)              // which keys resolved live/test/preview
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                .messageHost(container[MessagePresentingKey.self])   // one overlay, app-wide
        }
    }
}
```

Registration order doesn't matter — keys carry their own defaults. Only `init` cost matters, and
[PERFORMANCE.md](../PERFORMANCE.md) sets the rule: nothing on the launch path may do I/O.

---

## Scene phase

```swift
@Environment(\.scenePhase) private var scenePhase

.onChange(of: scenePhase) { _, phase in
    switch phase {
    case .active:     Task { await coordinator.didBecomeActive() }
    case .inactive:   break                       // transient — do NOT persist here
    case .background: Task { await coordinator.didEnterBackground() }
    @unknown default: break
    }
}
```

| Phase | Do | Don't |
|---|---|---|
| `.active` | resume polling, refresh stale data, re-check connectivity | assume it's a cold launch — this fires on every foreground |
| `.inactive` | nothing | persist state — `.inactive` fires for a notification pull-down or app switcher, constantly |
| `.background` | flush pending writes, save path, stop timers, release memory | start long work — you have seconds, and `BGTaskScheduler` exists for the rest |

**`.inactive` is not "about to close".** Treating it as a save point means writing to disk every
time the user swipes the Control Center open.

---

## State restoration

`Route` is `Codable` ([Navigation.md](Navigation.md)) precisely so restoration and deep links share
one path. Restoration is therefore: decode `[Route]`, hand it to the `Router`.

```swift
@SceneStorage("nav.path") private var encodedPath: Data?
```

Rules:

- **Restore navigation, never transient UI.** Scroll offset, keyboard focus, half-typed text, and
  sheet presentation are not restored — restoring them lands the user somewhere confusing.
- **Validate before restoring.** A restored route may point at something deleted, or at a screen
  the user is no longer entitled to see. Restore into a state you'd accept from a deep link, with
  the same authorization check.
- **Restoration must not block first frame.** Draw the root, then apply the path.
- Each scene restores independently — a shared router makes two windows fight over one path.
- Restoration silently doing nothing is the normal failure. Log it at `debug` so it's diagnosable.

---

## Launch gates

Gates run **after** first frame, over already-drawn UI. Nothing that blocks the first frame is a
gate — it's a launch regression.

Order matters, because each can supersede the next:

```
first frame drawn
  → force-update check      (blocking, unskippable)
  → maintenance window      (blocking, informational)
  → auth state              (route to login or home)
  → deep link / restoration (applied last, so it survives the above)
```

### Force update

```swift
public struct VersionGate: Sendable {
    public let minimumSupported: String     // below this: blocking, no dismiss
    public let recommended: String          // below this: dismissible prompt
}
```

- The threshold comes from a **remote** endpoint, per environment
  ([SCHEMES.md](../../.claude/notes/SCHEMES.md)) — a build-time constant can't force an update for
  builds already installed, which is the entire purpose.
- The blocking prompt is a `blockingDialog` through `MessagePresenting`
  ([Messaging.md](Messaging.md)), **never** a system alert — CLAUDE.md §2.4 has no exception here.
- Copy and the store link are localized.
- **Fail open.** If the check errors or times out, let the user in. A failed version check must
  never lock out a working app — that turns a backend blip into a total outage.
- Set the threshold for the *new* version at release time
  ([DELIVERY.md](../DELIVERY.md) checklist), not retroactively during an incident.

---

## OS callback adaptors

The only reason a delegate exists here. Each one forwards into a package and holds no logic:

| Callback | Forwards to | Platform |
|---|---|---|
| `handleEventsForBackgroundURLSession` | NetworkKit | iOS |
| `didRegisterForRemoteNotificationsWithDeviceToken` | [NotificationKit](NotificationKit.md) | both |
| `didReceiveRemoteNotification` | NotificationKit | both |
| `BGTaskScheduler` registration | NetworkKit | **iOS only** — no macOS equivalent |
| `application(_:open:)` / `onOpenURL` | Navigation deep-link parser | both |

Dropping the background-session completion handler stops the system waking the app — a bug that
only appears in the field, days later.

---

## macOS specifics

- Menu bar `Commands` push `Route` values. They never construct views.
- Window restoration uses the same `Codable` path as iOS.
- No `BGTaskScheduler`. The equivalent is a plain background `Task` while running, or a login item
  — a per-product decision, not a default.
- `applicationShouldTerminateAfterLastWindowClosed` is a product decision. Decide it; don't inherit
  the default by accident.
