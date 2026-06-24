import Foundation

public enum MarimoGenerator {
  public static let coldStartMinimumDays = 14

  public static func parameters(
    for yearMonth: YearMonth,
    dailyTotals: [DailyStepTotal],
    asOfLevels: [Date: Int],
    calendar: Calendar = .current
  ) -> MarimoParameters {
    let monthTotals = dailyTotals.filter {
      YearMonth(date: $0.date, calendar: calendar) == yearMonth
    }
    let steps = monthTotals.map(\.steps)
    let totalSteps = steps.reduce(0, +)
    let sizeUnit = sizeUnit(forTotalSteps: totalSteps)
    let colorLevel = colorLevel(for: monthTotals, asOfLevels: asOfLevels)
    let bumpiness = bumpiness(for: steps)
    let seed = deterministicSeed(for: yearMonth)

    return MarimoParameters(
      sizeUnit: sizeUnit,
      colorLevel: colorLevel,
      bumpiness: bumpiness,
      seed: seed,
      totalSteps: totalSteps
    )
  }

  private static func sizeUnit(forTotalSteps totalSteps: Int) -> Double {
    guard totalSteps > 0 else {
      return 0
    }

    let compressed = sqrt(Double(totalSteps))
    let reference = sqrt(300_000)
    return (compressed / reference).clamped(to: 0.12...1)
  }

  private static func colorLevel(for totals: [DailyStepTotal], asOfLevels: [Date: Int]) -> Double {
    let levels = totals.compactMap { asOfLevels[$0.date] }.filter { $0 > 0 }
    guard levels.count >= coldStartMinimumDays else {
      return 2
    }

    let total = levels.reduce(0, +)
    return Double(total) / Double(levels.count)
  }

  private static func bumpiness(for steps: [Int]) -> Double {
    let positiveSteps = steps.filter { $0 > 0 }
    guard positiveSteps.count > 1 else {
      return 0
    }

    let mean = Double(positiveSteps.reduce(0, +)) / Double(positiveSteps.count)
    guard mean > 0 else {
      return 0
    }

    let variance =
      positiveSteps
      .map { pow(Double($0) - mean, 2) }
      .reduce(0, +) / Double(positiveSteps.count)
    let coefficientOfVariation = sqrt(variance) / mean
    return (coefficientOfVariation / 1.5).clamped(to: 0...1)
  }

  private static func deterministicSeed(for yearMonth: YearMonth) -> UInt64 {
    UInt64(yearMonth.year * 100 + yearMonth.month)
  }
}
