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

    static func unknown(_ debug: String) -> AppError {
        AppError(code: .unknown,
                 messageKey: LocalizedKey("common_error_unknown_message"),
                 debugDescription: debug,
                 isRetryable: true)
    }
}
