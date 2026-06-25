import Foundation
import Testing

@testable import StepMossaicDomain

private let calendar = TestCalendar.utc
private let config = MarimoGenerationConfig()

/// Coverage spanning the first half of 2026, wide enough that whole months are
/// available unless a test narrows it.
private let wideCoverage = StepDataCoverage(
  firstAvailableDay: makeDay(2026, 1, 1),
  lastSyncedDay: makeDay(2026, 6, 30)
)

private func parameters(
  yearMonth: YearMonth,
  daily: [DailySteps],
  coverage: StepDataCoverage,
  today: Day
) -> MarimoParameters? {
  MarimoGenerator.parameters(
    for: yearMonth,
    daily: daily,
    coverage: coverage,
    today: today,
    calendar: calendar,
    config: config
  )
}

private func isClose(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
  abs(lhs - rhs) < tolerance
}

@Test("Returns nil when the month has no available target day")
func returnsNilWhenNoAvailableTargetDays() {
  // Arrange: today precedes June, so no June day is a target day yet.
  let beforeJune = makeDay(2026, 5, 31)

  // Act
  let result = parameters(
    yearMonth: YearMonth(year: 2026, month: 6),
    daily: [],
    coverage: wideCoverage,
    today: beforeJune
  )

  // Assert
  #expect(result == nil)
}

@Test("Size compresses the monthly total with a square root")
func sizeUsesMonthlyTotalWithSqrtCompression() {
  // Arrange: a past month, fully available. The reference total maps to 1.0.
  let endOfJune = makeDay(2026, 6, 30)
  let atReference = [DailySteps(day: makeDay(2026, 5, 15), steps: 300_000)]
  let quarterReference = [DailySteps(day: makeDay(2026, 5, 15), steps: 75_000)]

  // Act
  let may = YearMonth(year: 2026, month: 5)
  let full = parameters(
    yearMonth: may, daily: atReference, coverage: wideCoverage, today: endOfJune)
  let quarter = parameters(
    yearMonth: may, daily: quarterReference, coverage: wideCoverage, today: endOfJune)

  // Assert: total == reference is 1.0; a quarter of the reference is sqrt(0.25).
  #expect(full?.sizeUnit == 1.0)
  #expect(isClose(quarter?.sizeUnit ?? -1, 0.5))
}

@Test("Size clamps to the configured bounds")
func sizeClampsToConfiguredBounds() {
  // Arrange: an all-zero but available month, and an over-reference month.
  let endOfJune = makeDay(2026, 6, 30)
  let huge = [DailySteps(day: makeDay(2026, 5, 15), steps: 1_200_000)]

  // Act
  let may = YearMonth(year: 2026, month: 5)
  let zero = parameters(yearMonth: may, daily: [], coverage: wideCoverage, today: endOfJune)
  let overReference = parameters(
    yearMonth: may, daily: huge, coverage: wideCoverage, today: endOfJune)

  // Assert: a zero-step month still produces a marimo, clamped to the minimum.
  #expect(zero != nil)
  #expect(zero?.sizeUnit == config.minimumSizeUnit)
  #expect(overReference?.sizeUnit == config.maximumSizeUnit)
}

@Test("Color averages scores over all target days, including zero and cold-start days")
func colorAveragesScoresIncludingZeroAndColdStartDays() {
  // Arrange: only 5/1 and 5/2 are available. 5/1 is positive but its window has
  // too little history (cold start -> neutral, midpoint 2.0); 5/2 is a rest day
  // (ranked empty, score 0). The mean is (2.0 + 0) / 2.
  let coverage = StepDataCoverage(
    firstAvailableDay: makeDay(2026, 5, 1),
    lastSyncedDay: makeDay(2026, 5, 2)
  )
  let daily = [DailySteps(day: makeDay(2026, 5, 1), steps: 5000)]

  // Act
  let result = parameters(
    yearMonth: YearMonth(year: 2026, month: 5),
    daily: daily,
    coverage: coverage,
    today: makeDay(2026, 6, 30)
  )

  // Assert
  #expect(isClose(result?.colorLevel ?? -1, 1.0))
}

@Test("Bumpiness is the coefficient of variation, including zero-step days")
func bumpinessUsesCoefficientOfVariationIncludingZeroDays() {
  // Arrange: target days 5/1 = 10000 and 5/2 = 0. Mean 5000, sd 5000, so the
  // coefficient of variation is 1.0; bumpiness is 1.0 / reference (1.5).
  let coverage = StepDataCoverage(
    firstAvailableDay: makeDay(2026, 5, 1),
    lastSyncedDay: makeDay(2026, 5, 2)
  )
  let daily = [DailySteps(day: makeDay(2026, 5, 1), steps: 10_000)]

  // Act
  let result = parameters(
    yearMonth: YearMonth(year: 2026, month: 5),
    daily: daily,
    coverage: coverage,
    today: makeDay(2026, 6, 30)
  )

  // Assert
  #expect(isClose(result?.bumpiness ?? -1, 1.0 / 1.5))
}

@Test("Bumpiness is low when there are fewer than two target days")
func bumpinessIsLowWithFewerThanTwoTargetDays() {
  // Arrange: a single available target day.
  let coverage = StepDataCoverage(
    firstAvailableDay: makeDay(2026, 5, 1),
    lastSyncedDay: makeDay(2026, 5, 1)
  )
  let daily = [DailySteps(day: makeDay(2026, 5, 1), steps: 5000)]

  // Act
  let result = parameters(
    yearMonth: YearMonth(year: 2026, month: 5),
    daily: daily,
    coverage: coverage,
    today: makeDay(2026, 6, 30)
  )

  // Assert
  #expect(result?.bumpiness == 0)
}

@Test("The current month uses days up to today and excludes future days")
func currentMonthExcludesFutureDays() {
  // Arrange: today is 6/10. A real step on 6/5 counts; a value on the future,
  // out-of-coverage 6/20 must not.
  let today = makeDay(2026, 6, 10)
  let coverage = StepDataCoverage(
    firstAvailableDay: makeDay(2026, 6, 1),
    lastSyncedDay: makeDay(2026, 6, 10)
  )
  let daily = [
    DailySteps(day: makeDay(2026, 6, 5), steps: 8000),
    DailySteps(day: makeDay(2026, 6, 20), steps: 99_999),
  ]

  // Act
  let result = parameters(
    yearMonth: YearMonth(year: 2026, month: 6),
    daily: daily,
    coverage: coverage,
    today: today
  )

  // Assert: the total excludes the future day.
  #expect(result?.totalSteps == 8000)
}

@Test("The seed is derived deterministically from the year and month")
func seedIsDeterministicFromYearMonth() {
  // Act
  let result = parameters(
    yearMonth: YearMonth(year: 2026, month: 5),
    daily: [DailySteps(day: makeDay(2026, 5, 1), steps: 5000)],
    coverage: wideCoverage,
    today: makeDay(2026, 6, 30)
  )

  // Assert
  #expect(result?.seed == UInt64(2026 * 100 + 5))
}
