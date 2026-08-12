# NetworkKit

HTTP, download/upload, and background transfer. Async/await only, protocol-first,
transport-agnostic.

- **Package:** `GenericArch-NetworkKit` — **extracted repo**, semver-tagged (CLAUDE.md §4.2)
- **Used by:** any feature that talks to a remote service, through a protocol in `Core` that the
  app conforms this package to.
- **Depends on: nothing.** Zero dependencies, by necessity and by design — see below.
- **When to read this:** adding an endpoint, adding middleware, wiring auth or token refresh,
  implementing a download/upload, or making a transfer survive app suspension.

---

## Standalone, and mapped at our boundary

This package **does not import `Core`, `LoggingKit`, or `StorageKit`.** SPM resolves a git
dependency from that repo's root manifest, so an extracted package cannot reach a package living
inside the app repo.

So it behaves like a well-mannered vendor library that we happen to own (CLAUDE.md §7):

| Need | How it's met here | Bridged in the app by |
|---|---|---|
| Errors | its own `NetworkError` | `NetworkError.asAppError()` in an infrastructure mapping file |
| Logging | an injected `NetworkLogging` protocol it defines | an adapter conforming `LoggingKit` to it |
| Disk (resume data, ETag cache) | its own scoped directory under `Caches/` | nothing — self-contained |

**One mapping file, one adapter, in the app.** If that bridging ever grows past a file, the
extraction was wrong and this belongs back inside the repo (CLAUDE.md §4.2).

## The two protocols everything hangs off

```swift
public protocol HTTPClient: Sendable {
    // Untyped `throws` at a public boundary of an extracted package — CLAUDE.md §6.
    // Widening a typed throw here would be a major bump for a routine new error case.
    func send<R: Request>(_ request: R) async throws -> R.Response
}

public protocol Request: Sendable {
    associatedtype Response: Decodable & Sendable
    var path: String { get }
    var method: HTTPMethod { get }
    var body: RequestBody? { get }
    var headers: [String: String] { get }
}
```

## Endpoints are declarative values

One type per endpoint. **No string URLs at call sites, ever** — a call site that builds a path is
a call site that can't be tested or reused.

```swift
public struct LoginRequest: Request {
    public typealias Response = AuthTokenDTO
    public let path = "/v1/auth/login"
    public let method = HTTPMethod.post
    public var body: RequestBody? { .json(credentials) }
    public var headers: [String: String] { [:] }

    let credentials: Credentials
}
```

Endpoint types live in the **feature** that owns them, not here. NetworkKit owns the protocol;
features own their endpoints.

## Middleware chain

Ordered, composable, each stage `Sendable`. Auth → retry → ETag/caching → logging → transport.

```swift
public protocol RequestMiddleware: Sendable {
    func intercept(_ request: URLRequest,
                   next: @Sendable (URLRequest) async throws -> HTTPResponse)
        async throws -> HTTPResponse
}
```

- Logging middleware redacts by default and emits through the injected `NetworkLogging` protocol,
  which the app adapts to [LoggingKit](LoggingKit.md). Never log bodies or `Authorization` headers.
- Retry middleware applies only to `isRetryable` failures and uses exponential backoff with
  jitter. Never retry a non-idempotent request automatically.

## Token refresh is single-flight

Concurrent 401s must trigger **exactly one** refresh; all waiters await the same result. Get this
wrong and a token rotation storm logs the user out.

```swift
actor TokenRefresher {
    private var inFlight: Task<AuthToken, Error>?

    func refresh() async throws -> AuthToken {
        if let inFlight { return try await inFlight.value }   // join, don't start another
        let task = Task { try await performRefresh() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}
```

An actor, not a lock — refresh is `async`, so there is no reason to reach for one.

## Download and upload

Progress via `AsyncStream<Progress>`. Every transfer is cancellable and honors
`Task.checkCancellation()`.

```swift
public protocol FileDownloading: Sendable {
    func download(_ request: some Request) -> AsyncThrowingStream<DownloadEvent, Error>
}

public enum DownloadEvent: Sendable {
    case progress(Progress)
    case finished(URL)
}
```

**Resumable:** persist `resumeData` to disk on failure or cancellation so a killed transfer
restarts where it stopped rather than from zero. Store it keyed by request, not by URL — query
strings change.

## Background transfer

For transfers that must survive suspension and termination:

- `URLSessionConfiguration.background(withIdentifier:)`, one identifier per purpose, stable
  across launches.
- Handle `handleEventsForBackgroundURLSession` in the app shell and forward the completion
  handler here. Dropping it means the system stops waking the app.
- A background session's delegate must be re-attachable after a cold launch — state lives on
  disk, not in memory.

### Periodic refresh is platform-divergent

```swift
#if os(iOS)
// BGAppRefreshTask / BGProcessingTask — register at launch, before the first scene connects.
#endif
```

`BGTaskScheduler` **does not exist on macOS.** The Mac equivalent is a plain background `Task`
while running, or a login item for wake-from-terminated — that's a per-product decision, not a
default. See CLAUDE.md §1.1 for the gating rule.

## Decoding failures

Never a bare `nil`. A decode failure carries the failing key path so the bug is findable from a
log line alone.

```swift
case decoding(keyPath: String, expected: String, underlying: String)
```

## Testing

`MockHTTPClient` and a JSON fixture loader ship **inside this package**, so every consuming
feature tests offline with no extra dependency. This is what makes CLAUDE.md §9's "no network in
unit tests" enforceable rather than aspirational.

```swift
let client = MockHTTPClient()
client.stub(LoginRequest.self, with: .fixture("login_success"))
```

Fixtures are checked in beside the tests. A stub with no fixture file fails the test rather than
returning empty data.
