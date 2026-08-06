public enum SearchSubmissionIntent: Sendable, Equatable {
    case startSearch
    case nextResult
    case previousResult

    public static func resolve(
        query: String,
        completedQuery: String?,
        resultCount: Int,
        isShiftPressed: Bool
    ) -> SearchSubmissionIntent {
        guard resultCount > 0, query == completedQuery else {
            return .startSearch
        }
        return isShiftPressed ? .previousResult : .nextResult
    }
}
