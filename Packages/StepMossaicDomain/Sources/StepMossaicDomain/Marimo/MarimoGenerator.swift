import Foundation

/// Produces a month's `MarimoParameters` from daily steps.
public enum MarimoGenerator {
  /// Computes parameters for `yearMonth`, or `nil` when the month has no
  /// available target day.
  ///
  /// Target days are the available days in the month, up to `today`:
  /// - Past months use every available day in the month.
  /// - The current month's growing marimo runs from the month start to the
  ///   effective last available day; future days are excluded.
  /// - Days before `coverage.firstAvailableDay` are excluded.
  public static func parameters(
    for yearMonth: YearMonth,
    daily: [DailySteps],
    coverage: StepDataCoverage,
    today: Day,
    calendar: Calendar,
    config: MarimoGenerationConfig
  ) -> MarimoParameters? {
    // Last write wins if a day appears twice; callers provide one entry per day.
    let stepsByDay = Dictionary(daily.map { ($0.day, $0.steps) }, uniquingKeysWith: { $1 })

    // `coverage.isAvailable` excludes days outside [firstAvailableDay,
    // lastSyncedDay]; `<= today` additionally drops future days.
    let monthDays = yearMonth.interval(calendar: calendar).days(calendar: calendar)
    let targetDays = monthDays.filter { coverage.isAvailable($0) && $0 <= today }
    guard !targetDays.isEmpty else { return nil }

    let targetSteps = targetDays.map { stepsByDay[$0] ?? 0 }
    let totalSteps = targetSteps.reduce(0, +)

    return MarimoParameters(
      sizeUnit: sizeUnit(totalSteps: totalSteps, config: config),
      colorLevel: colorLevel(
        targetDays: targetDays,
        stepsByDay: stepsByDay,
        coverage: coverage,
        calendar: calendar,
        config: config
      ),
      bumpiness: bumpiness(targetSteps: targetSteps, config: config),
      seed: seed(for: yearMonth),
      totalSteps: totalSteps
    )
  }

  // MARK: - Size

  private static func sizeUnit(totalSteps: Int, config: MarimoGenerationConfig) -> Double {
    // Size uses the monthly total, not the average, and is not normalized by day
    // count: the current month is naturally small early and grows within it. A
    // zero-step month compresses to 0 and clamps up to the minimum size.
    let compressed = sqrt(Double(totalSteps))
    let reference = sqrt(Double(config.sizeReferenceMonthlySteps))
    return (compressed / reference).clamped(to: config.minimumSizeUnit...config.maximumSizeUnit)
  }

  // MARK: - Color

  private static func colorLevel(
    targetDays: [Day],
    stepsByDay: [Day: Int],
    coverage: StepDataCoverage,
    calendar: Calendar,
    config: MarimoGenerationConfig
  ) -> Double {
    // Average the color score over every available target day, so 0-step days
    // (score 0) and cold-start days (neutral midpoint) both pull the mean. This
    // is deliberately not an average over walked days only.
    let scores = targetDays.map { day in
      AsOfConditionCalculator.condition(
        for: day,
        stepsByDay: stepsByDay,
        coverage: coverage,
        calendar: calendar,
        asOfWindowDays: config.asOfWindowDays,
        coldStartMinimumPositiveDays: config.coldStartMinimumPositiveDays,
        levelScale: config.levelScale
      )
      .colorScore(scale: config.levelScale)
    }
    return scores.reduce(0, +) / Double(targetDays.count)
  }

  // MARK: - Bumpiness

  private static func bumpiness(targetSteps: [Int], config: MarimoGenerationConfig) -> Double {
    // Coefficient of variation over target days, including available 0-step days.
    guard targetSteps.count >= 2 else { return 0 }

    let values = targetSteps.map(Double.init)
    let mean = values.reduce(0, +) / Double(values.count)
    guard mean > 0 else { return 0 }

    let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
    let coefficientOfVariation = sqrt(variance) / mean
    return (coefficientOfVariation / config.bumpinessReferenceCoefficientOfVariation)
      .clamped(to: 0...1)
  }

  // MARK: - Seed

  private static func seed(for yearMonth: YearMonth) -> UInt64 {
    // Deterministic and simple: per-user variation comes from size, color, and
    // bumpiness, not from the seed.
    UInt64(yearMonth.year * 100 + yearMonth.month)
  }
}
