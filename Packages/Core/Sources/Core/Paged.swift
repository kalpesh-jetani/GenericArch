/// A paged collection. State *within* `loaded`, so a failed page never discards loaded rows.
public struct Paged<Item: Sendable>: Sendable {
    public enum PageState: Sendable, Equatable {
        case idle
        case loadingMore
        case failed(AppError)
        case exhausted
        case stale
    }

    public var items: [Item]
    public var page: PageState

    /// Creates a page of loaded items.
    ///
    /// - Parameters:
    ///   - items: Everything loaded so far, not just the latest page.
    ///   - page: State of the *tail*. A failed page keeps `items` intact — that separation is
    ///     the reason this type exists.
    public init(items: [Item], page: PageState = .idle) {
        self.items = items
        self.page = page
    }
}

extension Paged: Equatable where Item: Equatable {}
