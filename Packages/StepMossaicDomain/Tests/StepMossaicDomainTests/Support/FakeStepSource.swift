import Foundation

@testable import StepMossaicDomain

/// In-memory `StepSource` for driving sync-coordinator tests without HealthKit.
///
/// `@unchecked Sendable`: the mutable fields are written before a sync runs and
/// the recorded intervals are read after it completes, so accesses are serialized
/// by `await` rather than concurrent.
final class FakeStepSource: StepSource, @unchecked Sendable {
  var earliest: Date?
  /// Steps keyed by day; days absent here are returned as no entry, mirroring
  /// HealthKit omitting empty buckets.
  var stepsByDay: [Day: Int]
  var status: HealthAuthorizationStatus
  private let calendar: Calendar
  /// Every interval `dailySteps(in:)` was asked for, in call order, so tests can
  /// assert the chunking and the differential window.
  private(set) var requestedIntervals: [DayInterval] = []

  init(
    earliest: Date? = nil,
    stepsByDay: [Day: Int] = [:],
    status: HealthAuthorizationStatus = .requested,
    calendar: Calendar = TestCalendar.utc
  ) {
    self.earliest = earliest
    self.stepsByDay = stepsByDay
    self.status = status
    self.calendar = calendar
  }

  func earliestSampleDate() async throws -> Date? { earliest }

  func dailySteps(in interval: DayInterval) async throws -> [DailySteps] {
    requestedIntervals.append(interval)
    return interval.days(calendar: calendar).compactMap { day in
      guard let steps = stepsByDay[day] else { return nil }
      return DailySteps(day: day, steps: steps)
    }
  }

  func observeTodayUpdates() -> AsyncStream<Void> { AsyncStream { $0.finish() } }

  func authorizationStatus() -> HealthAuthorizationStatus { status }

  func requestAuthorization() async throws { status = .requested }
}
