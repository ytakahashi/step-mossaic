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
  /// Number of live ticks `observeTodayUpdates()` should emit before finishing.
  /// Defaults to 0, so the stream finishes immediately like a source with no live
  /// updates. A finite count keeps `observeLiveUpdates()` deterministic in tests:
  /// the loop returns once these ticks have been drained and their syncs ran.
  var liveTickCount = 0
  private(set) var requestAuthorizationCount = 0

  init(
    status: HealthAuthorizationStatus = .notDetermined,
    stepsToReturn: [DailySteps] = [],
    earliest: Date? = nil,
    liveTickCount: Int = 0
  ) {
    self.status = status
    self.stepsToReturn = stepsToReturn
    self.earliest = earliest
    self.liveTickCount = liveTickCount
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
    let count = liveTickCount
    return AsyncStream { continuation in
      for _ in 0..<count { continuation.yield(()) }
      continuation.finish()
    }
  }
}
