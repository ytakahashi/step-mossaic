import Foundation
import StepMossaicDomain

/// In-memory `StepLogStore` for `StepSyncModel` failure-path tests.
///
/// The real `SwiftDataStepLogStore` backed by an in-memory `ModelContainer`
/// cannot be made to fail deterministically, so persistence-failure tests use
/// this fake instead — mirroring the fake of the same name in
/// `StepMossaicDomainTests`.
final class FakeStepLogStore: StepLogStore {
  private(set) var storage: [Day: DailySteps] = [:]
  private var anchor: SyncAnchor?
  /// When set, every call throws this instead of returning, so tests can force
  /// a persistence failure out of `coverage()`, `refreshFrozenMarimos()`, or
  /// `rebuildCache()`.
  var errorToThrow: Error?
  /// When set, only `earliestLoggedDay()` throws this, independent of
  /// `errorToThrow`. `earliestLoggedDay()` is only ever called from
  /// `coverage()`, so this isolates "sync succeeded, the coverage re-read
  /// failed" from a sync-time persistence failure.
  var earliestLoggedDayErrorToThrow: Error?
  /// When set, only `reset()` throws this, independent of `errorToThrow`, so a
  /// test can fail a rebuild's reset while leaving every other call — including
  /// a would-be follow-up sync, if one incorrectly ran — free to succeed.
  var resetErrorToThrow: Error?

  init(seedLogs: [DailySteps] = [], anchor: SyncAnchor? = nil) {
    for log in seedLogs { storage[log.day] = log }
    self.anchor = anchor
  }

  func upsert(_ days: [DailySteps]) throws {
    if let errorToThrow { throw errorToThrow }
    for daily in days { storage[daily.day] = daily }
  }

  func logs(in interval: DayInterval) throws -> [DailySteps] {
    if let errorToThrow { throw errorToThrow }
    return storage.values
      .filter { interval.contains($0.day) }
      .sorted { $0.day < $1.day }
  }

  func earliestLoggedDay() throws -> Day? {
    if let earliestLoggedDayErrorToThrow { throw earliestLoggedDayErrorToThrow }
    if let errorToThrow { throw errorToThrow }
    return storage.keys.min()
  }

  func anchorState() throws -> SyncAnchor? {
    if let errorToThrow { throw errorToThrow }
    return anchor
  }

  func saveAnchor(_ anchor: SyncAnchor) throws {
    if let errorToThrow { throw errorToThrow }
    self.anchor = anchor
  }

  func reset() throws {
    if let resetErrorToThrow { throw resetErrorToThrow }
    if let errorToThrow { throw errorToThrow }
    storage.removeAll()
    anchor = nil
  }
}
