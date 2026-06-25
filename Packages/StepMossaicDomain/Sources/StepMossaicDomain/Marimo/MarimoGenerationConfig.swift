/// Tunable values for marimo generation, grouped so they are not hard-coded
/// constants scattered through the generator.
public struct MarimoGenerationConfig: Equatable, Sendable {
  /// Length of the as-of population window, in days.
  public var asOfWindowDays: Int
  /// Minimum positive days in the window before a day is ranked, not neutral.
  public var coldStartMinimumPositiveDays: Int
  /// Monthly step total that maps to the maximum size before clamping.
  public var sizeReferenceMonthlySteps: Int
  /// Lower bound for the size unit.
  public var minimumSizeUnit: Double
  /// Upper bound for the size unit.
  public var maximumSizeUnit: Double
  /// Coefficient of variation that normalizes to full bumpiness.
  public var bumpinessReferenceCoefficientOfVariation: Double
  /// Level scale shared by relativization and color scoring.
  public var levelScale: StepLevelScale

  public init(
    asOfWindowDays: Int = 90,
    coldStartMinimumPositiveDays: Int = 14,
    sizeReferenceMonthlySteps: Int = 300_000,
    minimumSizeUnit: Double = 0.12,
    maximumSizeUnit: Double = 1.0,
    bumpinessReferenceCoefficientOfVariation: Double = 1.5,
    levelScale: StepLevelScale = StepLevelScale()
  ) {
    precondition(asOfWindowDays >= 1, "asOfWindowDays must be >= 1")
    precondition(coldStartMinimumPositiveDays >= 0, "coldStartMinimumPositiveDays must be >= 0")
    // Used as a sqrt denominator, so it must be strictly positive.
    precondition(sizeReferenceMonthlySteps > 0, "sizeReferenceMonthlySteps must be > 0")
    precondition(minimumSizeUnit >= 0, "minimumSizeUnit must be >= 0")
    precondition(minimumSizeUnit <= maximumSizeUnit, "minimumSizeUnit must be <= maximumSizeUnit")
    // Used as a normalization denominator for bumpiness.
    precondition(
      bumpinessReferenceCoefficientOfVariation > 0,
      "bumpinessReferenceCoefficientOfVariation must be > 0"
    )

    self.asOfWindowDays = asOfWindowDays
    self.coldStartMinimumPositiveDays = coldStartMinimumPositiveDays
    self.sizeReferenceMonthlySteps = sizeReferenceMonthlySteps
    self.minimumSizeUnit = minimumSizeUnit
    self.maximumSizeUnit = maximumSizeUnit
    self.bumpinessReferenceCoefficientOfVariation = bumpinessReferenceCoefficientOfVariation
    self.levelScale = levelScale
  }
}
