import Foundation

public struct FrozenMarimo: Equatable, Sendable {
  public var yearMonth: YearMonth
  public var sizeUnit: Double
  public var colorLevel: Double
  public var bumpiness: Double
  public var seed: UInt64
  public var totalSteps: Int
  public var frozenAt: Date
  public var isLocked: Bool

  public init(
    yearMonth: YearMonth,
    sizeUnit: Double,
    colorLevel: Double,
    bumpiness: Double,
    seed: UInt64,
    totalSteps: Int,
    frozenAt: Date,
    isLocked: Bool
  ) {
    self.yearMonth = yearMonth
    self.sizeUnit = sizeUnit.clamped(to: 0...1)
    self.colorLevel = colorLevel.clamped(to: 0...4)
    self.bumpiness = bumpiness.clamped(to: 0...1)
    self.seed = seed
    self.totalSteps = max(0, totalSteps)
    self.frozenAt = frozenAt
    self.isLocked = isLocked
  }
}

extension Double {
  package func clamped(to range: ClosedRange<Double>) -> Double {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
