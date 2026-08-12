/// A localization key. Wrapping it makes a raw string literal in UI a type error, not a review note.
public struct LocalizedKey: Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    /// Wraps a catalog key.
    public init(_ rawValue: String) { self.rawValue = rawValue }

    /// Allows a literal where a key is expected, so call sites stay readable.
    ///
    /// This is the one place a raw string becomes a key — the type is what stops literals
    /// spreading into views.
    public init(stringLiteral value: String) { self.rawValue = value }
}
