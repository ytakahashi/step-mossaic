import Foundation

public protocol StepLogStore: Sendable {
  func upsert(_ logs: [DailyStepLog]) throws
  func logs(in interval: DateInterval) throws -> [DailyStepLog]
  func anchorState() throws -> SyncAnchor?
  func saveAnchor(_ anchor: SyncAnchor) throws
  func reset() throws
}
