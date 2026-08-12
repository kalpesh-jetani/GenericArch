# LoggingKit

Logging with redaction on by default.

- **Package:** `Packages/LoggingKit` (local)
- **Used by:** [StorageKit](StorageKit.md), [DIKit](DIKit.md) (launch graph dump),
  [NotificationKit](NotificationKit.md), and any service reporting a failure. Depends on
  [Core](Core.md) only.
- **Not used directly by the extracted repos.** [NetworkKit](NetworkKit.md) and
  [ImageCache](ImageCache.md) declare their own logging protocols; the app supplies a small adapter
  conforming this package to them (CLAUDE.md §4.2).
- **When to read this:** adding a log call, logging anything derived from a server response or
  user input, or wiring crash/analytics reporting.

---

## Redaction is the default, not an option

CLAUDE.md §8: **no PII, tokens, or request bodies in logs.** The API is shaped so the unsafe
thing is the harder thing to type.

```swift
public protocol Logging: Sendable {
    func log(_ level: LogLevel, _ message: StaticString, _ metadata: [String: Redactable])
}
```

`message` is `StaticString` — an interpolated string can't be passed, so a token can't be
concatenated into a log line by accident. Dynamic values arrive through `metadata`, where every
value is `Redactable` and redacted unless explicitly marked public.

```swift
public enum Redactable: Sendable {
    case redacted(String)        // logs as "<redacted:8>" — length only
    case `public`(String)        // logs verbatim — requires a deliberate choice
    case hashed(String)          // stable hash, for correlating without identifying
}
```

```swift
logger.log(.error, "login failed", [
    "user":   .hashed(email),          // correlate across sessions, identifies no one
    "status": .public("401"),
    "token":  .redacted(token),        // never leaves the device readable
])
```

`.public` at a call site is the review trigger. If a diff adds one, that line gets read carefully.

## What must never be logged, at any level

- Tokens, passwords, refresh secrets, Keychain contents.
- Request or response **bodies** — not even in DEBUG. Debug builds get shared, screenshotted, and
  pasted into tickets.
- Email, phone, name, address, precise location, device identifiers.
- Anything from an `AppError.underlying` that hasn't already been redacted at creation
  ([Core](Core.md)).

## Levels

| Level | Use for | Ships in release |
|---|---|---|
| `trace` | per-request detail while debugging | no |
| `debug` | state transitions, cache hits | no |
| `info` | lifecycle, launch, sign-in success | yes |
| `warning` | recovered failure, retry, degraded mode | yes |
| `error` | an `AppError` was created | yes |
| `critical` | data loss risk, failed migration | yes |

**Log where the error is created; present once at the top** ([Core](Core.md)). A log call at every
layer of a rethrow turns one failure into six lines and makes the real one unfindable.

Never log a cancellation as an error. `Task` cancellation is normal control flow.

## Backends sit behind the protocol

`OSLogBackend` (default, `os.Logger`, subsystem per package) plus `ConsoleBackend` for tests.

Any crash-reporting or analytics SDK is a **third-party dependency and therefore a wrapper**
(CLAUDE.md §7) — it is never imported here or in a feature. `LoggingKit` may forward to it through
our own protocol, but it does not know the vendor.

```swift
public protocol CrashReporting: Sendable {          // lives in Core
    func record(_ error: AppError)
    func setUserIdentifier(_ hashed: String)        // hashed, never raw
}
```

## Testing

`SpyLogger` records level, message, and metadata **with redaction already applied** — so a test can
assert that a secret never appeared:

```swift
#expect(!spy.renderedLines.contains(where: { $0.contains(token) }))
```

That assertion belongs in the test suite of any package that handles credentials. It's the only
check that catches a redaction regression before shipping.
