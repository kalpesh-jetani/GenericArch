public struct AppMessage: Sendable, Equatable {
    public enum Style: Sendable, Equatable { case toast, banner, sheet, blockingDialog, inline }
    public enum Severity: Sendable, Equatable { case info, success, warning, error }
    public enum Outcome: Sendable, Equatable { case confirmed, dismissed }

    public let titleKey: LocalizedKey
    public let messageKey: LocalizedKey?
    public let style: Style
    public let severity: Severity

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
    func present(_ message: AppMessage) async -> AppMessage.Outcome
}

/// Ships beside the protocol, for tests and previews.
public actor SpyMessagePresenter: MessagePresenting {
    public private(set) var requests: [AppMessage] = []
    private let outcome: AppMessage.Outcome

    public init(outcome: AppMessage.Outcome = .dismissed) { self.outcome = outcome }

    public func present(_ message: AppMessage) async -> AppMessage.Outcome {
        requests.append(message)
        return outcome
    }
}
