# DIKit

Our own typed dependency registry. No third party, so nothing to wrap and nothing to swap.

- **Package:** `Packages/DIKit` (local)
- **Used by:** the composition root in the app targets, and one `Assembly` file per feature.
  **Not** used inside feature types — see [Resolve is a root privilege](#resolve-is-a-root-privilege).
- **When to read this:** adding a dependency key, wiring a new feature into the root, writing an
  `Assembly`, or setting up previews and test doubles.

Decision and rejected alternatives: [../DECISIONS.md](../DECISIONS.md).

---

A registry has two classic failure modes — a runtime "unregistered type" failure, and drift back
into ambient singletons. Both are forbidden by CLAUDE.md §2.6 and §2.7, so the registry is shaped
to make them **unrepresentable** rather than merely discouraged.

## Keys carry their own defaults — resolution cannot fail

There is no "unregistered" state. Each dependency is a typed key supplying its own values, so
`resolve` is total and never traps.

```swift
public protocol DependencyKey {
    associatedtype Value: Sendable
    static var liveValue: Value { get }
    static var testValue: Value { get }       // NoOp or Mock — never a live service
}

public enum HTTPClientKey: DependencyKey {
    public static var liveValue: any HTTPClient { URLSessionHTTPClient(config: .default) }
    public static var testValue: any HTTPClient { MockHTTPClient() }
}
```

**Two values, not three.** A separate `previewValue` was removed — it defaulted to `testValue`
anyway, and earned nothing but a line in every key, forever. Previews use `testValue`; a preview
that needs different data overrides the key explicitly, which it should be doing regardless.

- A key lives **beside the protocol it resolves**, in the package that owns that protocol — not
  here. `DIKit` owns the machinery; packages own their keys.
- `testValue` is mandatory. It is what makes CLAUDE.md §9's "no network in unit tests"
  enforceable.
- Overriding a key at the root is registration. *Not* overriding it is still valid.

## Register, then freeze — `Sendable` without locks

`DIContainerBuilder` is mutable and used only during launch. `.build()` returns an **immutable,
`Sendable` `DIContainer`**. Nothing can register after build, so there is no shared mutable state,
no lock, and no `@unchecked Sendable`.

```swift
var builder = DIContainerBuilder()
builder.register(HTTPClientKey.self, URLSessionHTTPClient(config: .default))
builder.register(AuthenticatingKey.self, AuthService(http: …, store: …))
let container = builder.build()          // immutable from here on
```

Lazy or scoped instances are the **only** place a lock is permitted, and it must carry the
CLAUDE.md §2.8 justification comment. Prefer eager construction; if a dependency is too expensive
to build at launch, register a cheap facade that builds it on first `await`.

## Resolve is a root privilege

**A feature type must never call `resolve` inside itself.** That is the singleton pattern with
extra steps, and CLAUDE.md §2.6 forbids it.

| May resolve | Must never resolve |
|---|---|
| The composition root, in the App target | View models |
| A feature's own `Assembly` — one file per feature, the seam where the root hands it dependencies | Views |
| `#Preview` blocks and test setup | Services, repositories, mappers |

Feature types still take protocols through `init`. The registry removes the **root's** wiring
boilerplate; it does not reach into features.

```swift
// FeatureAuth/DI/AuthAssembly.swift — the only file in the feature that sees the container
public struct AuthAssembly {
    public static func loginViewModel(_ c: DIContainer) -> LoginViewModel {
        LoginViewModel(auth: c[AuthenticatingKey.self],
                       presenter: c[MessagePresentingKey.self])
    }
}
```

If you find yourself wanting `resolve` deeper in a feature, the dependency is missing from that
type's `init`. Add the parameter.

## Keeping the graph visible

A registry hides the object graph that initializer injection makes obvious. Compensate with two
checks — both **automatic**, because a hand-maintained graph document goes stale and a stale graph
is worse than none:

- `DIContainer.debugDescription` lists every key and whether it resolved live or test. Dump it once
  at launch in DEBUG ([AppShell.md](AppShell.md)).
- A test per package asserts every key it owns resolves, and that `testValue` is not a live type.

> A hand-written `DEPENDENCY-GRAPH.md` was previously required here and has been dropped. Across a
> dozen packages it would drift within weeks, and the two checks above cover the same need without
> anyone maintaining them.

## Always

- The composition root is the only place concrete **live** types are constructed.
- Every protocol ships a mock beside it, for tests **and** previews.
- Previews and tests override keys explicitly; they never fall through to `liveValue`.

## Revisit this design if…

`resolve` starts appearing inside feature types. That means the registry is costing more visibility
than it saves in boilerplate.
