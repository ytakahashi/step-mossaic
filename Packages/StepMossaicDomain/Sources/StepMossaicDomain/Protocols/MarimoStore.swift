public protocol MarimoStore: Sendable {
  func frozenMarimo(for yearMonth: YearMonth) throws -> FrozenMarimo?
  func save(_ marimo: FrozenMarimo) throws
  func allFrozen() throws -> [FrozenMarimo]
}
