/// Persists frozen monthly marimo snapshots.
///
/// Not `Sendable`, for the same reason as `StepLogStore`: it wraps an actor-bound
/// persistence context driven from a single actor.
public protocol MarimoStore {
  func frozenMarimo(for yearMonth: YearMonth) throws -> FrozenMarimo?
  func save(_ marimo: FrozenMarimo) throws
  func allFrozen() throws -> [FrozenMarimo]
  /// Deletes every frozen marimo, including locked months.
  ///
  /// The store only owns the deletion; deciding to wipe and which months to
  /// regenerate afterwards is the cache-rebuild orchestration's concern. Pairs
  /// with `StepLogStore.reset()` so a rebuild clears each store independently.
  func reset() throws
}
