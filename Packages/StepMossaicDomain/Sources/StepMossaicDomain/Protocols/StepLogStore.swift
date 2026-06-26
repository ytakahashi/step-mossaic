import Foundation

/// Persists the daily-step cache and HealthKit sync anchor.
///
/// Not `Sendable`: the conforming store wraps a single, actor-bound persistence
/// context and is meant to be driven from one actor (the main actor in the app),
/// not shared across actors. `StepSource` remains `Sendable` because it is the
/// genuinely concurrent, async boundary.
public protocol StepLogStore {
  /// Inserts or updates each day's total, keyed by `DailySteps.day`.
  ///
  /// The persistence-only `updatedAt` bookkeeping is the store's concern, not the
  /// caller's; the domain passes day + steps and nothing more.
  func upsert(_ days: [DailySteps]) throws
  /// Returns the stored days within `interval` (both bounds inclusive), sorted
  /// ascending by day.
  func logs(in interval: DayInterval) throws -> [DailySteps]
  func anchorState() throws -> SyncAnchor?
  func saveAnchor(_ anchor: SyncAnchor) throws
  func reset() throws
}
