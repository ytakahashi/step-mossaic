import Foundation

public struct DailyStepTotal: Equatable, Sendable {
  public var date: Date
  public var steps: Int

  public init(date: Date, steps: Int) {
    self.date = date
    self.steps = max(0, steps)
  }
}
