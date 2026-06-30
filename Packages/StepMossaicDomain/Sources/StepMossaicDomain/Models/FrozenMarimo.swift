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

extension FrozenMarimo {
  /// Builds a frozen snapshot from freshly generated parameters.
  ///
  /// The bridge from generation to persistence: `MarimoGenerator` produces the
  /// `MarimoParameters`, and the freeze policy supplies `frozenAt`/`isLocked`. The
  /// generated values are already clamped, so the base initializer's clamping is a
  /// harmless re-assertion.
  public init(
    yearMonth: YearMonth,
    parameters: MarimoParameters,
    frozenAt: Date,
    isLocked: Bool
  ) {
    self.init(
      yearMonth: yearMonth,
      sizeUnit: parameters.sizeUnit,
      colorLevel: parameters.colorLevel,
      bumpiness: parameters.bumpiness,
      seed: parameters.seed,
      totalSteps: parameters.totalSteps,
      frozenAt: frozenAt,
      isLocked: isLocked
    )
  }

  /// The rendering parameters baked into this snapshot, for drawing the marimo on
  /// the shelf and in the month detail. Drops the persistence-only `frozenAt`,
  /// `isLocked`, and month key the renderer does not need.
  public var parameters: MarimoParameters {
    MarimoParameters(
      sizeUnit: sizeUnit,
      colorLevel: colorLevel,
      bumpiness: bumpiness,
      seed: seed,
      totalSteps: totalSteps
    )
  }
}

extension Double {
  package func clamped(to range: ClosedRange<Double>) -> Double {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
