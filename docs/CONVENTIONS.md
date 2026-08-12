# Conventions

Naming, file layout, and access control. Checked **while writing code**, which is why these live
here rather than in always-on context — and why most of them should be enforced by the linter
([../.swiftlint.yml](../.swiftlint.yml)) rather than by reading.

- **When to read this:** naming a new type, deciding what to make `public`, or reviewing a diff.

---

## Naming

| Thing | Form | Example |
|---|---|---|
| Types | `UpperCamelCase` | `LoginViewModel` |
| Members | `lowerCamelCase` | `isRetryable` |
| Acronyms | fully uppercased | `HTTPClient`, `URLBuilder`, `APIToken` |
| Protocols — capability | noun ending `-ing` | `ImageCaching`, `TokenRefreshing` |
| Protocols — trait | adjective ending `-able` | `Cancellable`, `Redactable` |
| Dependency keys | `<Protocol>Key` | `HTTPClientKey` |
| Mocks / spies | `Mock<X>` / `Spy<X>` | `MockHTTPClient`, `SpyMessagePresenter` |

**No `I` prefix, no `Protocol` suffix.** `IHTTPClient` and `HTTPClientProtocol` both mean the author
couldn't name the implementation — name that instead (`URLSessionHTTPClient`).

Booleans read as assertions: `isRetryable`, `hasSeenOnboarding`, `canRetry`. Not `retryable`,
not `onboardingFlag`.

Avoid `Manager`, `Helper`, `Utils`, `Service` as a bare suffix. They describe no capability, so they
attract unrelated code — the `// MARK: - Unrelated` smell in CLAUDE.md §3.

## Files

- **One primary type per file; file name = type name.** Small related types (an enum a struct owns)
  may share the file.
- Extensions on a foreign type go in `<Type>+<Purpose>.swift` — `AppError+Network.swift`.
- Test file mirrors its subject: `LoginViewModel.swift` → `LoginViewModelTests.swift`.
- Directory layout inside a feature: `Models`, `Services`, `ViewModels`, `Views`, `Localization`,
  `DI`. Nothing else at the top level.

## Access control

Default to **`internal`**. Make something `public` only when it crosses a package boundary — and
each time you do, that is a decision to be able to defend, because `public` is what a consumer can
depend on and what a change can break.

- `final` by default on classes. Non-final needs a reason, and CLAUDE.md §3 bans base classes anyway.
- `private` over `fileprivate` unless the file genuinely needs sharing.
- `@testable import` for internals; **never** widen access to `public` to make a test compile.
- In an extracted package (CLAUDE.md §4.2), every `public` symbol is a semver commitment. Prefer
  `package`-level access where the symbol only needs to cross targets inside that package.

## Documentation comments

**Every function and initialiser you write or change gets a `///` doc comment.** Not just `public`
ones — the reader of a private helper has the same question, and "I'll document it later" is how a
file ends up with none.

Cover what the signature cannot say:

```swift
/// Sends a request and decodes its response.
///
/// - Throws: `NetworkError.offline` when no network path exists; `.decoding` with the failing
///   key path when the payload doesn't match. Cancellation propagates as `CancellationError`.
public func send<R: Request>(_ request: R) async throws -> R.Response
```

Thrown errors and cancellation behaviour are the two things callers cannot infer and always need.

### Doc comments, not meta comments

A `///` doc comment states the contract. A **meta comment** narrates the code or the act of writing
it, and has no place in the source:

```swift
// ❌ meta — restates the signature, narrates the edit, or talks about the process
// this function logs the user in
// helper for the above
// added to fix the crash in QA
// TODO: clean this up later

/// ✅ doc — the contract, and what the signature cannot express
/// Exchanges credentials for a session.
///
/// - Throws: `AppError.unauthorized` on bad credentials; `.offline` with no network path.
///   Cancellation propagates as `CancellationError` and leaves no partial session.
```

If a note is about the *change* rather than the *code*, it belongs in the commit message or
[DECISIONS.md](DECISIONS.md) — not in a comment that outlives the change.

**Two exceptions, both because the description already exists elsewhere:**

- A `@Test("…")` case whose string already describes it. A `///` above it would only duplicate.
- A conformance whose contract is fully stated on the protocol. Document the *deviation*, not the
  restatement.

**Inline `//` comments explain *why*, never *what*.** A comment restating the code goes stale and lies:

```swift
// ❌ says nothing the code doesn't
// increment the retry count
retryCount += 1

// ✅ says why this number
// Three attempts covers a token rotation mid-flight without amplifying an outage.
let maxAttempts = 3
```

Two comments are **mandatory**, both because CLAUDE.md §2 requires them:
- Beside any `@unchecked Sendable`, justifying the manual synchronisation (§2.8).
- Beside any `@Environment(\.colorScheme)` or `\.layoutDirection` read, justifying why a token or
  automatic mirroring wasn't enough.

## Formatting

Enforced by [`.swiftformat`](../.swiftformat) — don't argue it in review. 120-column limit, 4-space
indent, trailing commas in multi-line literals.

## Ordering within a type

Stored properties → initialisers → public methods → private helpers → nested types. `// MARK: -`
between groups once a type exceeds roughly one screen. A type needing many MARKs is usually two
types.
