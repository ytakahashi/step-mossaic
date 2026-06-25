import Foundation
import Testing

@testable import StepMossaicDomain

private let calendar = TestCalendar.utc
private let june = YearMonth(year: 2026, month: 6).interval(calendar: calendar)

private func heatmap(
  stepsByDay: [Day: Int],
  coverage: StepDataCoverage
) -> StepHeatmap {
  StepHeatmapGenerator.heatmap(
    for: june,
    stepsByDay: stepsByDay,
    coverage: coverage,
    calendar: calendar,
    levelScale: StepLevelScale()
  )
}

private func state(_ heatmap: StepHeatmap, _ day: Day) -> StepHeatmapCellState? {
  heatmap.cells.first { $0.day == day }?.state
}

private func available(_ steps: Int, level: Int) -> StepHeatmapCellState {
  .available(steps: steps, level: StepLevel(rawValue: level))
}

@Test("Cells cover the whole interval, clipped to coverage")
func cellsCoverWholeIntervalClippedByCoverage() {
  // Arrange: display all of June, but data only covers 6/1...6/20.
  let coverage = StepDataCoverage(
    firstAvailableDay: makeDay(2026, 6, 1),
    lastSyncedDay: makeDay(2026, 6, 20)
  )

  // Act
  let result = heatmap(stepsByDay: [makeDay(2026, 6, 1): 5000], coverage: coverage)

  // Assert: one cell per day; days past the synced range are unavailable.
  #expect(result.cells.count == 30)
  #expect(state(result, makeDay(2026, 6, 20)) == .available(steps: 0, level: .empty))
  #expect(state(result, makeDay(2026, 6, 21)) == .unavailable)
  #expect(state(result, makeDay(2026, 6, 30)) == .unavailable)
}

@Test("Average divides by available days, counting 0-step days, excluding unavailable")
func averageDividesByAvailableDayCount() {
  // Arrange: 20 available days; 10 with 1000 steps, 10 with none (0). An
  // unavailable day carries steps that must not leak into total or average.
  var steps: [Day: Int] = [:]
  for dayOfMonth in 1...10 {
    steps[makeDay(2026, 6, dayOfMonth)] = 1000
  }
  steps[makeDay(2026, 6, 25)] = 9999  // unavailable
  let coverage = StepDataCoverage(
    firstAvailableDay: makeDay(2026, 6, 1),
    lastSyncedDay: makeDay(2026, 6, 20)
  )

  // Act
  let result = heatmap(stepsByDay: steps, coverage: coverage)

  // Assert: total excludes the unavailable day; average divides by 20, not 10.
  #expect(result.totalSteps == 10_000)
  #expect(result.averageStepsPerAvailableDay == 500)
}

@Test("Relativization ranks against available positive days only")
func relativizationPopulationIsAvailablePositiveDaysOnly() {
  // Arrange: four positive available days plus zero-step available days. An
  // unavailable day holds a huge value that must not enter the population.
  var steps: [Day: Int] = [
    makeDay(2026, 6, 1): 1000,
    makeDay(2026, 6, 2): 2000,
    makeDay(2026, 6, 3): 3000,
    makeDay(2026, 6, 4): 4000,
    makeDay(2026, 6, 25): 100_000,  // unavailable
  ]
  steps[makeDay(2026, 6, 5)] = 0
  let coverage = StepDataCoverage(
    firstAvailableDay: makeDay(2026, 6, 1),
    lastSyncedDay: makeDay(2026, 6, 20)
  )

  // Act
  let result = heatmap(stepsByDay: steps, coverage: coverage)

  // Assert: the four positives span levels 1...4, so the unavailable 100k did
  // not displace 4000 as the population maximum.
  #expect(state(result, makeDay(2026, 6, 1)) == available(1000, level: 1))
  #expect(state(result, makeDay(2026, 6, 2)) == available(2000, level: 2))
  #expect(state(result, makeDay(2026, 6, 3)) == available(3000, level: 3))
  #expect(state(result, makeDay(2026, 6, 4)) == available(4000, level: 4))
  // A covered day with no steps is available and empty, not unavailable.
  #expect(state(result, makeDay(2026, 6, 5)) == .available(steps: 0, level: .empty))
  #expect(state(result, makeDay(2026, 6, 25)) == .unavailable)
}

@Test("No available days yields a zero average rather than dividing by zero")
func noAvailableDaysYieldsZeroAverage() {
  // Arrange: coverage with no available data at all.
  let coverage = StepDataCoverage(firstAvailableDay: nil, lastSyncedDay: makeDay(2026, 6, 30))

  // Act
  let result = heatmap(stepsByDay: [makeDay(2026, 6, 10): 5000], coverage: coverage)

  // Assert
  #expect(result.totalSteps == 0)
  #expect(result.averageStepsPerAvailableDay == 0)
  #expect(result.cells.allSatisfy { $0.state == .unavailable })
}
