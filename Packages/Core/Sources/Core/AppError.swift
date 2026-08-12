/// The single error domain a user is ever shown. Every layer maps its own errors up into this.
public struct AppError: Error, Sendable, Equatable {
    public enum Code: String, Sendable, Equatable {
        case offline, timeout, unauthorized, forbidden, notFound
        case decoding, encoding, storage, cancelled, unknown
    }

    public let code: Code
    /// What the user reads. Never a raw server string.
    public let messageKey: LocalizedKey
    /// Developer-facing. Never displayed.
    public let debugDescription: String
    public let isRetryable: Bool

    /// Creates an error for display.
    ///
    /// - Parameters:
    ///   - code: Stable and loggable. Never shown to a user.
    ///   - messageKey: What the user reads. Never a raw server string.
    ///   - debugDescription: Developer-facing detail; must already be redacted.
    ///   - isRetryable: Drives whether the UI offers Retry. Set it deliberately — a
    ///     non-retryable error with a Retry button is worse than no button.
    public init(code: Code, messageKey: LocalizedKey, debugDescription: String, isRetryable: Bool) {
        self.code = code
        self.messageKey = messageKey
        self.debugDescription = debugDescription
        self.isRetryable = isRetryable
    }
}

public extension AppError {
    static let offline = AppError(
        code: .offline,
        messageKey: LocalizedKey("common_error_no_internet_message"),
        debugDescription: "No network path available",
        isRetryable: true
    )

    /// Fallback for a failure that could not be mapped to a known `Code`.
    ///
    /// Reaching for this often means a layer is missing a mapping — prefer adding the specific
    /// case over widening use of this one.
    static func unknown(_ debug: String) -> AppError {
        AppError(code: .unknown,
                 messageKey: LocalizedKey("common_error_unknown_message"),
                 debugDescription: debug,
                 isRetryable: true)
    }
}
