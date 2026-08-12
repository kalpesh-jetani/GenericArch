public enum DIMode: Sendable, Equatable {
    /// Falls back to `liveValue` for anything not registered.
    case live
    /// Falls back to `testValue`. Used by tests and previews.
    case test
}

/// Immutable and `Sendable` — built once at launch, never mutated after.
/// No shared mutable state means no lock and no `@unchecked Sendable`.
public struct DIContainer: Sendable {
    private let storage: [ObjectIdentifier: any Sendable]
    private let registeredNames: [String]
    public let mode: DIMode

    /// Internal by design: a container is only ever produced by `DIContainerBuilder.build()`,
    /// which is what guarantees it is frozen before anything can resolve from it.
    init(storage: [ObjectIdentifier: any Sendable], registeredNames: [String], mode: DIMode) {
        self.storage = storage
        self.registeredNames = registeredNames
        self.mode = mode
    }

    /// Total: an unregistered key resolves to the key's own default for the current mode.
    public subscript<K: DependencyKey>(_ key: K.Type) -> K.Value {
        if let registered = storage[ObjectIdentifier(key)] as? K.Value { return registered }
        return mode == .live ? K.liveValue : K.testValue
    }

    /// Which keys resolved from a registration, and which fell through to a default.
    /// Dump once at launch in DEBUG — a registry hides the graph that init injection makes obvious.
    public var debugDescription: String {
        let lines = registeredNames.sorted().map { "  \($0)  → registered" }
        return (["DIContainer(mode: \(mode), registered: \(registeredNames.count))"] + lines)
            .joined(separator: "\n")
    }
}

/// Mutable during launch only. `build()` freezes it.
public struct DIContainerBuilder {
    private var storage: [ObjectIdentifier: any Sendable] = [:]
    private var registeredNames: [String] = []
    private let mode: DIMode

    /// Creates an empty builder.
    ///
    /// - Parameter mode: Which default an unregistered key falls back to. Tests and previews pass
    ///   `.test` so nothing can silently reach a live service.
    public init(mode: DIMode = .live) { self.mode = mode }

    /// Overrides a key's default with a concrete value.
    ///
    /// Registration order is irrelevant — keys carry their own defaults, so an unregistered key is
    /// still resolvable. Only construction cost matters here (see PERFORMANCE.md's facade rule).
    public mutating func register<K: DependencyKey>(_ key: K.Type, _ value: K.Value) {
        storage[ObjectIdentifier(key)] = value
        registeredNames.append(String(describing: key))
    }

    /// Freezes the registrations into an immutable, `Sendable` container.
    ///
    /// After this the graph cannot change, which is what removes the need for a lock and for
    /// `@unchecked Sendable`.
    public func build() -> DIContainer {
        DIContainer(storage: storage, registeredNames: registeredNames, mode: mode)
    }
}
