import Foundation

@testable import StepMossaicDomain

/// In-memory `StepLogStore` for sync-coordinator tests.
///
/// Plain (non-`Sendable`) like the real store: it is only ever driven from the
/// main actor through the coordinator, so no synchronization is needed.
final class FakeStepLogStore: StepLogStore {
  private(set) var storage: [Day: DailySteps] = [:]
  private var anchor: SyncAnchor?
  /// Number of `upsert` calls, so tests can tell one chunked backfill apart from
  /// a single differential fetch.
  private(set) var upsertCallCount = 0

  init(seedLogs: [DailySteps] = [], anchor: SyncAnchor? = nil) {
    for log in seedLogs { storage[log.day] = log }
    self.anchor = anchor
  }

  func upsert(_ days: [DailySteps]) throws {
    upsertCallCount += 1
    for daily in days { storage[daily.day] = daily }
  }

  func logs(in interval: DayInterval) throws -> [DailySteps] {
    storage.values
      .filter { interval.contains($0.day) }
      .sorted { $0.day < $1.day }
  }

  func anchorState() throws -> SyncAnchor? { anchor }

  func saveAnchor(_ anchor: SyncAnchor) throws { self.anchor = anchor }

  func reset() throws {
    storage.removeAll()
    anchor = nil
  }
}
