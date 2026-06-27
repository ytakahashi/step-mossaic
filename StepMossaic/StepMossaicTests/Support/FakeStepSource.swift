import Foundation
import StepMossaicDomain

/// In-memory `StepSource` for driving view-model and sync tests without HealthKit.
///
/// `@unchecked Sendable`: the mutable fields are only touched from the main actor
/// in tests, so no synchronization is needed.
final class FakeStepSource: StepSource, @unchecked Sendable {
  var status: HealthAuthorizationStatus
  var stepsToReturn: [DailySteps]
  var earliest: Date?
  private(set) var requestAuthorizationCount = 0

  init(
    status: HealthAuthorizationStatus = .notDetermined,
    stepsToReturn: [DailySteps] = [],
    earliest: Date? = nil
  ) {
    self.status = status
    self.stepsToReturn = stepsToReturn
    self.earliest = earliest
  }

  func authorizationStatus() -> HealthAuthorizationStatus { status }

  func requestAuthorization() async throws {
    requestAuthorizationCount += 1
    // Mirror HealthKit: once asked, the status is no longer "not determined".
    status = .requested
  }

  func earliestSampleDate() async throws -> Date? { earliest }

  func dailySteps(in interval: DayInterval) async throws -> [DailySteps] { stepsToReturn }

  func observeTodayUpdates() -> AsyncStream<Void> {
    AsyncStream { $0.finish() }
  }
}
