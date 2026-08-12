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

    public init(items: [Item], page: PageState = .idle) {
        self.items = items
        self.page = page
    }
}

extension Paged: Equatable where Item: Equatable {}
