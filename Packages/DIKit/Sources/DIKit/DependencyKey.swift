/// A dependency is a typed key that supplies its own values, so `resolve` is total and never traps.
/// There is no "unregistered" state to fail on.
public protocol DependencyKey {
    associatedtype Value: Sendable
    static var liveValue: Value { get }
    /// Mandatory. A NoOp or Mock — never a live service. This is what makes
    /// "no network in unit tests" enforceable rather than aspirational.
    static var testValue: Value { get }
}
