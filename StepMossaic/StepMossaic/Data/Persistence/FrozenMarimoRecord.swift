import Foundation
import SwiftData

@Model
final class FrozenMarimoRecord {
  @Attribute(.unique) var yearMonth: String
  var sizeUnit: Double
  var colorLevel: Double
  var bumpiness: Double
  var seed: UInt64
  var totalSteps: Int
  var frozenAt: Date
  var isLocked: Bool

  init(
    yearMonth: String,
    sizeUnit: Double,
    colorLevel: Double,
    bumpiness: Double,
    seed: UInt64,
    totalSteps: Int,
    frozenAt: Date,
    isLocked: Bool
  ) {
    self.yearMonth = yearMonth
    self.sizeUnit = sizeUnit
    self.colorLevel = colorLevel
    self.bumpiness = bumpiness
    self.seed = seed
    self.totalSteps = max(0, totalSteps)
    self.frozenAt = frozenAt
    self.isLocked = isLocked
  }
}
