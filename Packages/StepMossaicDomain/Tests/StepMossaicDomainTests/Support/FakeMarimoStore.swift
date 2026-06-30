import Foundation

@testable import StepMossaicDomain

/// In-memory `MarimoStore` for sync-coordinator tests.
///
/// Plain (non-`Sendable`) like the real store: it is only ever driven from the
/// main actor through the coordinator, so no synchronization is needed.
final class FakeMarimoStore: MarimoStore {
  private(set) var storage: [YearMonth: FrozenMarimo] = [:]
  /// Number of `save` calls, so tests can tell that a locked month was skipped
  /// (never re-saved) rather than regenerated.
  private(set) var saveCallCount = 0

  init(seed: [FrozenMarimo] = []) {
    for marimo in seed { storage[marimo.yearMonth] = marimo }
  }

  func frozenMarimo(for yearMonth: YearMonth) throws -> FrozenMarimo? {
    storage[yearMonth]
  }

  func save(_ marimo: FrozenMarimo) throws {
    saveCallCount += 1
    storage[marimo.yearMonth] = marimo
  }

  func allFrozen() throws -> [FrozenMarimo] {
    storage.values.sorted { $0.yearMonth < $1.yearMonth }
  }

  func reset() throws {
    storage.removeAll()
  }
}
