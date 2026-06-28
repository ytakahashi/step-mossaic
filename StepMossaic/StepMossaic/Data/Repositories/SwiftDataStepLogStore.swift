import Foundation
import StepMossaicDomain
import SwiftData

/// SwiftData-backed cache of daily step totals and the HealthKit sync anchor.
///
/// Main-actor isolated: the store wraps a single `ModelContext`, which is not
/// `Sendable`. The daily cache is tiny (a decade is ~3,650 rows), so a single
/// context driven from the main actor is sufficient and avoids cross-actor
/// `ModelContext` hazards. The `StepLogStore` conformance is therefore an
/// isolated conformance; all callers run on the main actor.
@MainActor
final class SwiftDataStepLogStore {
  /// Singleton key for the one HealthKit step anchor row.
  private static let anchorID = "healthkit.steps"

  private let context: ModelContext
  /// Used to re-normalize stored instants back into `Day` values on read.
  private let calendar: Calendar
  /// Source of the persistence-only `updatedAt` stamp; injected so tests stay
  /// deterministic instead of reading the wall clock.
  private let now: @MainActor () -> Date

  init(
    context: ModelContext,
    calendar: Calendar = .current,
    now: @escaping @MainActor () -> Date = { Date() }
  ) {
    self.context = context
    self.calendar = calendar
    self.now = now
  }

  private func anchorRecord() throws -> SyncAnchorRecord? {
    let id = Self.anchorID
    let descriptor = FetchDescriptor<SyncAnchorRecord>(
      predicate: #Predicate { $0.id == id }
    )
    return try context.fetch(descriptor).first
  }
}

extension SwiftDataStepLogStore: @MainActor StepLogStore {
  /// Inserts or updates each day's total, keyed by the day's start instant.
  ///
  /// An existing row for the same day is updated in place so the unique-date
  /// identity is preserved; a new day is inserted. Every touched row is stamped
  /// with the current time so re-sync can resolve last-writer-wins.
  func upsert(_ days: [DailySteps]) throws {
    let timestamp = now()
    for daily in days {
      let date = daily.day.start
      let descriptor = FetchDescriptor<DailyStepLogRecord>(
        predicate: #Predicate { $0.date == date }
      )
      if let existing = try context.fetch(descriptor).first {
        existing.apply(daily, updatedAt: timestamp)
      } else {
        context.insert(DailyStepLogRecord(daily, updatedAt: timestamp))
      }
    }
    try context.save()
  }

  /// Returns the days within `interval`, both bounds inclusive, sorted ascending.
  func logs(in interval: DayInterval) throws -> [DailySteps] {
    let start = interval.start.start
    let end = interval.end.start
    let descriptor = FetchDescriptor<DailyStepLogRecord>(
      predicate: #Predicate { $0.date >= start && $0.date <= end },
      sortBy: [SortDescriptor(\.date, order: .forward)]
    )
    return try context.fetch(descriptor).map { $0.toDomain(calendar: calendar) }
  }

  /// Returns the earliest stored day, fetching a single row rather than scanning.
  func earliestLoggedDay() throws -> Day? {
    var descriptor = FetchDescriptor<DailyStepLogRecord>(
      sortBy: [SortDescriptor(\.date, order: .forward)]
    )
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first?.toDomain(calendar: calendar).day
  }

  func anchorState() throws -> SyncAnchor? {
    try anchorRecord()?.toDomain()
  }

  func saveAnchor(_ anchor: SyncAnchor) throws {
    if let existing = try anchorRecord() {
      existing.apply(anchor)
    } else {
      context.insert(
        SyncAnchorRecord(id: Self.anchorID, lastSyncedDate: anchor.lastSyncedDate)
      )
    }
    try context.save()
  }

  /// Clears the cached daily logs and the sync anchor.
  ///
  /// Frozen marimo are owned by `SwiftDataMarimoStore`; a full cache rebuild
  /// resets each store independently so neither reaches across aggregates.
  func reset() throws {
    try context.delete(model: DailyStepLogRecord.self)
    try context.delete(model: SyncAnchorRecord.self)
    try context.save()
  }
}
