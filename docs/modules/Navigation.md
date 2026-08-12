# Navigation

`Route`, path state, deep links, and the compact/regular container split.

- **Package:** `Packages/Navigation` (local)
- **Used by:** the app shell (owns the containers) and every feature (contributes route cases and
  destinations). Depends on [Core](Core.md) only — **never** on a feature.
- **When to read this:** adding a screen, adding a deep link, wiring iPad/Mac split view, or
  implementing state restoration.

---

## Navigation state is data, never view references

One `Route` enum plus a path array. Deep links, state restoration, and split-view selection then
share **one** mechanism instead of three that disagree.

```swift
public enum Route: Hashable, Codable, Sendable {
    case authLogin
    case homeFeed
    case itemDetail(id: Item.ID)
    case settings(SettingsSection)
}

@MainActor @Observable
public final class Router {
    public private(set) var path: [Route] = []
    public var selectedRoot: Route?          // sidebar / split-view selection

    public func push(_ route: Route) { path.append(route) }
    public func pop() { _ = path.popLast() }
    public func replaceAll(with routes: [Route]) { path = routes }
}
```

`Codable` is not optional — it's what makes state restoration and deep links the same code path.

## Features contribute cases, not imports

CLAUDE.md §2.1: no package imports a sibling feature. So a feature **cannot** construct another
feature's screen. It pushes a `Route`; the app shell resolves it.

```swift
// In a feature — legal
router.push(.itemDetail(id: item.id))

// In a feature — illegal, and won't even link
ItemDetailView(id: item.id)      // ❌ FeatureHome importing FeatureDetail
```

Route → view resolution happens **once**, in the app shell, next to the composition root:

```swift
.navigationDestination(for: Route.self) { route in
    switch route {
    case .itemDetail(let id): DetailAssembly.view(container, id: id)
    …
    }
}
```

Adding a screen is therefore: one case here, one line in the shell's switch, zero edits to other
features (CLAUDE.md §3, *Scalable*).

## Container choice is by size class, never by device

```swift
@Environment(\.horizontalSizeClass) private var sizeClass

var body: some View {
    if sizeClass == .regular {
        NavigationSplitView { Sidebar() } detail: { DetailStack() }   // iPad, Mac
    } else {
        NavigationStack(path: $router.path) { RootView() }            // iPhone
    }
}
```

Never branch on device model, `UIDevice.current`, or a width constant. An iPad in Slide Over is
compact; an iPhone Pro Max in landscape is regular. Both break device checks and neither breaks
size-class checks.

## Deep links

A URL parses to `[Route]` and nothing else — no side effects during parsing, so it's unit-testable
with no app running.

```swift
public protocol DeepLinkParsing: Sendable {
    func routes(for url: URL) -> [Route]?      // nil = not ours, don't consume it
}
```

- Parsing is total and pure. Validation of *whether the user may go there* (auth, entitlement)
  happens after, in the shell.
- An unparseable or unauthorized link lands on a sensible root, never a blank screen, and never
  a system alert — use [Messaging](Messaging.md) if the user needs telling.
- Universal links, custom schemes, notification payloads, Handoff, and Spotlight items all funnel
  through this one parser.

## Multi-scene and Mac windows

- Each scene owns its own `Router`. A shared router across windows makes two windows fight over
  one path.
- Mac: window restoration uses the same `Codable` path. Menu bar `Commands` push routes; they
  never poke at views.
- iPad: keyboard shortcuts and Slide Over each just push routes — no special casing.

## Testing

Because routes are values, navigation is unit-testable without any UI:

```swift
#expect(parser.routes(for: url) == [.homeFeed, .itemDetail(id: "42")])
router.push(.settings(.privacy))
#expect(router.path.last == .settings(.privacy))
```
