/// A localization key. Wrapping it makes a raw string literal in UI a type error, not a review note.
public struct LocalizedKey: Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}
