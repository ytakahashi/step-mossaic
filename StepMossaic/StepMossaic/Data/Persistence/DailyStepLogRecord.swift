import Foundation
import SwiftData

@Model
final class DailyStepLogRecord {
  @Attribute(.unique) var date: Date
  var steps: Int
  var updatedAt: Date

  init(date: Date, steps: Int, updatedAt: Date) {
    self.date = date
    self.steps = max(0, steps)
    self.updatedAt = updatedAt
  }
}
