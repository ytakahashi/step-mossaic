import Foundation

public protocol StepSource: Sendable {
  func earliestSampleDate() async throws -> Date?
  func dailyStepTotals(from startDate: Date, to endDate: Date) async throws -> [DailyStepTotal]
  func observeTodayUpdates() -> AsyncStream<Void>
  func authorizationStatus() -> HealthAuthorizationStatus
  func requestAuthorization() async throws
}
