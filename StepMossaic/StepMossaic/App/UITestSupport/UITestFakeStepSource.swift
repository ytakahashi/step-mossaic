#if DEBUG
  import Foundation
  import StepMossaicDomain

  /// Minimal in-memory `StepSource` for `#if DEBUG` UI-test scenarios. Kept
  /// separate from the unit test target's `FakeStepSource` so the app target
  /// never depends on the test target.
  final class UITestFakeStepSource: StepSource, @unchecked Sendable {
    private var status: HealthAuthorizationStatus

    init(status: HealthAuthorizationStatus) {
      self.status = status
    }

    func authorizationStatus() -> HealthAuthorizationStatus { status }

    func requestAuthorization() async throws {
      // Mirror HealthKit: once asked, the status is no longer "not determined".
      status = .requested
    }

    func earliestSampleDate() async throws -> Date? { nil }

    func dailySteps(in interval: DayInterval) async throws -> [DailySteps] { [] }

    func observeTodayUpdates() -> AsyncStream<Void> {
      AsyncStream { $0.finish() }
    }
  }
#endif
