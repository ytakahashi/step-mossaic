import Foundation
import StepMossaicDomain

/// In-memory `MarimoStore` for `StepSyncModel` failure-path tests, mirroring
/// the fake of the same name in `StepMossaicDomainTests`. See
/// `FakeStepLogStore` for why a fake rather than the real SwiftData store is
/// used to simulate persistence failures.
final class FakeMarimoStore: MarimoStore {
  private(set) var storage: [YearMonth: FrozenMarimo] = [:]
  /// When set, every call throws this instead of returning, so tests can force
  /// a persistence failure out of `refreshFrozenMarimos()` or `rebuildCache()`.
  var errorToThrow: Error?

  init(seed: [FrozenMarimo] = []) {
    for marimo in seed { storage[marimo.yearMonth] = marimo }
  }

  func frozenMarimo(for yearMonth: YearMonth) throws -> FrozenMarimo? {
    if let errorToThrow { throw errorToThrow }
    return storage[yearMonth]
  }

  func save(_ marimo: FrozenMarimo) throws {
    if let errorToThrow { throw errorToThrow }
    storage[marimo.yearMonth] = marimo
  }

  func allFrozen() throws -> [FrozenMarimo] {
    if let errorToThrow { throw errorToThrow }
    return storage.values.sorted { $0.yearMonth < $1.yearMonth }
  }

  func reset() throws {
    if let errorToThrow { throw errorToThrow }
    storage.removeAll()
  }
}
