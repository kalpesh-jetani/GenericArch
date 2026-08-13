# Core

Protocols, domain models, `AppError`, and shared primitives.

- **Package:** `Packages/Core` (local)
- **Used by:** every package in the repo. Nothing below it; everything above depends on it.
- **When to read this:** adding a protocol two packages must share, defining a domain model,
  adding or mapping an error case, or deciding whether a type belongs here at all.

> A `Core` change recompiles everything above it, so confirm a type genuinely crosses a package
> boundary before adding it — the cheapest `Core` change is the one you don't make. A package that
> ships from its own repo cannot import `Core` at all; its types are mapped in at the boundary
> (CLAUDE.md §4.2).

---

## What belongs here

- Capability protocols shared by two or more packages (`Authenticating`, `ImageCaching`,
  `MessagePresenting`, `Reachability`).
- Domain models — value types, `Sendable`, no UI concerns, no persistence annotations.
- `AppError` and the error-mapping contract.
- `ContentState<Value>` (the enum only — its view lives in [DesignSystem](DesignSystem.md)).
- Small pure primitives: `LocalizedKey`, `Redactable`, `Progress`, ID wrappers.

## What must never go here

- Anything importing SwiftUI, UIKit, AppKit, or a third-party module.
- Anything a single package uses — that belongs in that package.
- Concrete service implementations. `Core` declares capability; it does not provide it.
- Persistence engine types. Those stay behind `EntityStoring` in [StorageKit](StorageKit.md).

---

## AppError

One error domain. Every layer maps its own errors up into it; nothing else reaches a user.

```swift
public struct AppError: Error, Sendable, Equatable {
    public let code: Code                    // stable, loggable, never localized
    public let messageKey: LocalizedKey      // what the user reads
    public let debugDescription: String      // developer-facing, never shown
    public let isRetryable: Bool
    public let underlying: String?           // already-redacted summary, not the raw error
}

public extension AppError {
    enum Code: String, Sendable {
        case offline, timeout, unauthorized, forbidden, notFound
        case decoding, encoding, storage, cancelled, unknown
    }
}
```

### The mapping contract

Every package that throws its own error type provides exactly one mapping into `AppError`, and
that mapping is unit-tested for every case.

```swift
// NetworkKit — the only place NetworkError becomes AppError
extension NetworkError {
    public func asAppError() -> AppError { … }
}
```

Rules:
- **Log where the error is created, present once at the top.** Never both.
- Never surface a raw `NSError`, `DecodingError`, or server-supplied string — CLAUDE.md §2.3
  applies to error text too.
- `cancelled` is not a user-facing error. Swallow it at the presentation boundary; never show a
  message for a task the user cancelled.
- One user action produces at most one message, regardless of how many errors it generated.
- `isRetryable` drives whether `ContentStateView` offers Retry. Set it deliberately — a
  non-retryable error with a Retry button is a worse bug than a missing button.

### Typed throws — inside a package only

Use `throws(AppError)` **within** a package, where the domain is closed and you control every
caller.

At the **public boundary of any package that ships on its own version**, use untyped `throws`.
Widening a typed throw is a breaking change, so
adding one routine error case would force a major bump and a coordinated update across every
consumer ([REPO.md](../REPO.md)).

---

## ContentState

```swift
public enum ContentState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case empty(EmptyReason)      // noResults · noDataYet · filteredOut
    case offline
    case failed(AppError)
}
```

Lives here, not in DesignSystem, so a view model can expose it without importing a UI package.
Rendering is [DesignSystem](DesignSystem.md)'s job.

`Equatable` only where `Value: Equatable`; never conform by comparing `AppError.debugDescription`.

### Paged content

A paged list has state *within* `loaded` — it is still showing content while fetching more, and a
failed page must not discard the pages already displayed. Modelling that with a second
`isLoadingMore` boolean is exactly the drift CLAUDE.md §2.5 forbids, so it belongs here:

```swift
public struct Paged<Item: Sendable>: Sendable {
    public var items: [Item]
    public var page: PageState

    public enum PageState: Sendable {
        case idle                 // more available, nothing in flight
        case loadingMore          // append a footer spinner — content stays visible
        case failed(AppError)     // inline retry in the footer, NOT a full-screen error
        case exhausted            // no more pages; hide the footer entirely
        case stale                // showing cache while a refresh runs — optional banner
    }
}
```

Used as `ContentState<Paged<Item>>`. The outer enum covers "do we have anything at all"; the inner
covers "what is happening to the tail". Two rules that follow, and are the whole reason this is a
type rather than a convention:

- **A failed page never becomes `ContentState.failed`.** Losing fifty loaded rows because page
  three timed out is the bug this prevents.
- **An empty first page is `ContentState.empty`, not `loaded` with zero items.** Otherwise the
  empty-state copy never renders.
