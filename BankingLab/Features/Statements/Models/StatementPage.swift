struct StatementPage: Equatable, Sendable {
    let items: [StatementTransaction]
    let nextCursor: String?
}
