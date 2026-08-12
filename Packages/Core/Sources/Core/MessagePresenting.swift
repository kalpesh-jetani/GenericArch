public struct AppMessage: Sendable, Equatable {
    public enum Style: Sendable, Equatable { case toast, banner, sheet, blockingDialog, inline }
    public enum Severity: Sendable, Equatable { case info, success, warning, error }
    public enum Outcome: Sendable, Equatable { case confirmed, dismissed }

    public let titleKey: LocalizedKey
    public let messageKey: LocalizedKey?
    public let style: Style
    public let severity: Severity

    /// Describes a message to request. Constructing one does not present it.
    ///
    /// - Parameters:
    ///   - style: How it should appear. `inline` never queues — it belongs to a specific view.
    ///   - severity: Drives tint and symbol. Never the sole carrier of meaning.
    public init(titleKey: LocalizedKey, messageKey: LocalizedKey? = nil,
                style: Style, severity: Severity) {
        self.titleKey = titleKey
        self.messageKey = messageKey
        self.style = style
        self.severity = severity
    }
}

/// Features *request*; they never present. One host overlay at the app root presents.
public protocol MessagePresenting: Sendable {
    /// Presents a message and suspends until the user resolves it.
    ///
    /// Returning the outcome rather than taking a callback is what lets a confirmation read
    /// top-to-bottom at the call site.
    ///
    /// - Returns: `.confirmed` only on an explicit affirmative; dismissal is `.dismissed`.
    func present(_ message: AppMessage) async -> AppMessage.Outcome
}

/// Ships beside the protocol, for tests and previews.
public actor SpyMessagePresenter: MessagePresenting {
    public private(set) var requests: [AppMessage] = []
    private let outcome: AppMessage.Outcome

    /// Creates a spy that records requests and answers every one identically.
    ///
    /// - Parameter outcome: Returned for every request. Defaults to `.dismissed` so a test must
    ///   opt in to the confirmed path rather than getting it by accident.
    public init(outcome: AppMessage.Outcome = .dismissed) { self.outcome = outcome }

    /// Records the request and returns the scripted outcome without rendering anything.
    public func present(_ message: AppMessage) async -> AppMessage.Outcome {
        requests.append(message)
        return outcome
    }
}
