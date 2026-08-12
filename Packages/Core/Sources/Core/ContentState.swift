public enum EmptyReason: Sendable, Equatable {
    case noResults, noDataYet, filteredOut
}

/// Every data-driven screen renders from this. No ad-hoc `isLoading` booleans.
public enum ContentState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case empty(EmptyReason)
    case offline
    case failed(AppError)
}

extension ContentState: Equatable where Value: Equatable {}
