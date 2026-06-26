import Foundation
import StepMossaicDomain

extension DailyStepLogRecord {
  /// Builds a record from a domain day. Used when inserting a new day.
  ///
  /// The domain carries no timestamp, so the data layer stamps `updatedAt`
  /// itself; `Day.start` is the normalized instant persisted as the row key.
  convenience init(_ daily: DailySteps, updatedAt: Date) {
    self.init(date: daily.day.start, steps: daily.steps, updatedAt: updatedAt)
  }

  /// Copies the mutable fields from a domain day onto an existing record.
  ///
  /// Used by upsert when a record for the same day already exists, so SwiftData
  /// keeps the same row (and `@Attribute(.unique)` identity) instead of churning.
  func apply(_ daily: DailySteps, updatedAt: Date) {
    steps = max(0, daily.steps)
    self.updatedAt = updatedAt
  }

  /// Reconstructs the domain day, re-normalizing the stored instant into a `Day`
  /// under `calendar`. `updatedAt` stays in the record and is not surfaced.
  func toDomain(calendar: Calendar) -> DailySteps {
    DailySteps(day: Day(containing: date, calendar: calendar), steps: steps)
  }
}
