# StorageKit

Key-value, secure, entity, and file storage — all behind protocols, so no feature ever names an
engine.

- **Package:** `Packages/StorageKit` (local)
- **Used by:** features that persist data, and auth (token storage). **Not** by the extracted repos
  — [NetworkKit](NetworkKit.md) (resume data, ETag cache) and [ImageCache](ImageCache.md) each own
  a scoped directory under `Caches/`, because a standalone package cannot import this one
  (CLAUDE.md §4.2).
- **When to read this:** persisting anything, storing a secret, adding a cache, or writing a
  migration.

---

## Four protocols

```swift
public protocol KeyValueStoring: Sendable {          // preferences, flags, small scalars
    func value<T: Codable & Sendable>(for key: StorageKey<T>) async -> T?
    func set<T: Codable & Sendable>(_ value: T?, for key: StorageKey<T>) async
}

public protocol SecureStoring: Sendable { … }        // Keychain — tokens, secrets, nothing else
public protocol EntityStoring: Sendable { … }        // domain objects, queries, migrations
public protocol FileStoring: Sendable { … }          // blobs, downloads, generated files
```

Pick by **lifetime and sensitivity**, not by convenience:

| Need | Protocol |
|---|---|
| A user preference, a feature flag, "has seen onboarding" | `KeyValueStoring` |
| A token, password, refresh secret, biometric-gated value | `SecureStoring` |
| Anything you will later query, sort, or relate | `EntityStoring` |
| A downloaded file, an export, a cached image | `FileStoring` |

## The engine behind `EntityStoring` is a §0 question

**Ask when a feature first needs it. Do not pick one silently.** CLAUDE.md §0.

Options to offer, with this summary:

| Option | Trade-off |
|---|---|
| **SwiftData** | Least boilerplate, best SwiftUI integration — but the roughest fit with Swift 6 strict concurrency; `ModelActor` isolation will shape your repository layer |
| **Core Data** | Most proven, best migration tooling — verbose, and `NSManagedObject` is not `Sendable`, so mapping to domain models is mandatory |
| **SQLite / GRDB** | Full SQL control, cleanest `Sendable` story, testable in memory — hand-written mapping, and you own the migration mechanics |
| **Other** | — |
| **Skip** | Many products need no entity store at all. Don't build one speculatively |

Record the answer in [../DECISIONS.md](../DECISIONS.md). Because the engine sits behind
`EntityStoring`, **a feature never names it** — swapping engines touches this target only.

## Secrets

Keychain **only**. Never `UserDefaults`, never a plist, never a `.xcconfig` committed to git,
never a log line ([LoggingKit](LoggingKit.md) redacts, but don't rely on that as the first
defense).

- Set the accessibility class deliberately — `whenUnlockedThisDeviceOnly` for tokens unless there
  is a stated reason to sync.
- Keychain items survive app deletion on some OS versions. Clear explicitly on sign-out; don't
  assume uninstall does it.
- Biometric gating goes through `BiometricAuthenticating`, not `LocalAuthentication` at a call
  site.

## Migrations

Versioned, ordered, and **tested against a fixture database captured from the previous release**.
A migration that only runs on a fresh install is untested.

- Never mutate a shipped schema in place.
- A failed migration must not lose data — fall back to a read-only mode and surface it through
  [Messaging](Messaging.md), never a silent wipe.
- Keep the migration path linear. Supporting `v1→v4` *and* `v3→v4` doubles the test matrix
  forever.

## Caches

Every cache declares, in code, at construction:

1. an **eviction policy** (LRU, TTL, or both),
2. a **size cap** in bytes, and
3. what happens on a cache miss.

An unbounded cache is a crash on an older device with a full disk. `FileStoring` caches go in
`Caches/`, not `Documents/` — `Documents/` is backed up and counts against iCloud quota.

## Concurrency

Implementations are actors or `Sendable` structs — never `@MainActor`. A storage call from a view
model is `await`ed like any other service call.

`StorageKey<T>` is typed so a key can't be read as the wrong type:

```swift
extension StorageKey {
    static var hasSeenOnboarding: StorageKey<Bool> { .init("has_seen_onboarding") }
}
```

## Testing

In-memory implementations of all four protocols ship **in this package**, so consuming features
test without touching the disk or the Keychain. Contract tests (CLAUDE.md §9) run the same suite
against both the real and in-memory implementation.
