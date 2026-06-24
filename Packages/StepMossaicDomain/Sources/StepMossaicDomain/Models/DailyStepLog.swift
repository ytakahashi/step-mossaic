import Foundation

public struct DailyStepLog: Equatable, Sendable {
  public var date: Date
  public var steps: Int
  public var updatedAt: Date

  public init(date: Date, steps: Int, updatedAt: Date) {
    self.date = date
    self.steps = max(0, steps)
    self.updatedAt = updatedAt
  }
}
