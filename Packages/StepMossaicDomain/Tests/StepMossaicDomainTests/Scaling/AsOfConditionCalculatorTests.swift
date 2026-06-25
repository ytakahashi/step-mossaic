import Foundation
import Testing

@testable import StepMossaicDomain

private let calendar = TestCalendar.utc
private let targetDay = makeDay(2026, 6, 30)
private let windowDays = 90
private let coldStartThreshold = 14

/// Coverage wide enough that availability never clips the window unless a test
/// deliberately narrows it.
private let openCoverage = StepDataCoverage(
  firstAvailableDay: targetDay.adding(days: -200, calendar: calendar),
  lastSyncedDay: targetDay
)

/// Builds a step lookup with `targetSteps` on the target day plus a positive
/// step value on each `dayOffsets` day (offsets are days before the target).
private func stepsByDay(
  targetSteps: Int,
  positiveOffsets: [Int],
  positiveStepValue: Int = 5000
) -> [Day: Int] {
  var steps: [Day: Int] = [targetDay: targetSteps]
  for offset in positiveOffsets {
    steps[targetDay.adding(days: offset, calendar: calendar)] = positiveStepValue
  }
  return steps
}

private func condition(
  stepsByDay: [Day: Int],
  coverage: StepDataCoverage = openCoverage
) -> AsOfCondition {
  AsOfConditionCalculator.condition(
    for: targetDay,
    stepsByDay: stepsByDay,
    coverage: coverage,
    calendar: calendar,
    asOfWindowDays: windowDays,
    coldStartMinimumPositiveDays: coldStartThreshold,
    levelScale: StepLevelScale()
  )
}

@Test("A zero-step target day is ranked empty, even with ample history")
func zeroStepTargetIsRankedEmpty() {
  // Arrange: plenty of positive history, but the target day itself is a rest day.
  let steps = stepsByDay(targetSteps: 0, positiveOffsets: Array(-20 ... -1))

  // Act
  let result = condition(stepsByDay: steps)

  // Assert: a rest day is a definite result, never neutral.
  #expect(result == .ranked(.empty))
}

@Test("Fewer positive days than the cold-start threshold yields neutral")
func belowColdStartThresholdIsNeutral() {
  // Arrange: target + 9 positive days = 10 positive days, below the threshold of 14.
  let steps = stepsByDay(targetSteps: 5000, positiveOffsets: Array(-9 ... -1))

  // Act
  let result = condition(stepsByDay: steps)

  // Assert
  #expect(result == .neutral)
}

@Test("Enough positive history ranks the target by RelativeScaler")
func sufficientHistoryRanksTarget() {
  // Arrange: 13 increasing days plus a target that is the new maximum, so the
  // window holds 14 positive days and the target reaches the top level.
  var steps: [Day: Int] = [targetDay: 14_000]
  for offset in -13 ... -1 {
    steps[targetDay.adding(days: offset, calendar: calendar)] = (14 + offset) * 1_000
  }

  // Act
  let result = condition(stepsByDay: steps)

  // Assert
  #expect(result == .ranked(StepLevel(rawValue: 4)))
}

@Test("The day 89 days before the target is inside the window")
func day89BeforeTargetIsInsideWindow() {
  // Arrange: target + 12 recent positive days + one at offset -89. If -89 counts,
  // there are 14 positive days (ranked); if it were excluded, 13 (neutral).
  let steps = stepsByDay(targetSteps: 5000, positiveOffsets: Array(-12 ... -1) + [-89])

  // Act
  let result = condition(stepsByDay: steps)

  // Assert: a ranked result proves day -89 is counted.
  #expect(result != .neutral)
}

@Test("The day 90 days before the target is outside the window")
func day90BeforeTargetIsOutsideWindow() {
  // Arrange: target + 12 recent positive days + one at offset -90. Correctly
  // excluding -90 leaves 13 positive days (neutral); including it would be 14.
  let steps = stepsByDay(targetSteps: 5000, positiveOffsets: Array(-12 ... -1) + [-90])

  // Act
  let result = condition(stepsByDay: steps)

  // Assert: a neutral result proves day -90 is excluded.
  #expect(result == .neutral)
}

@Test("Unavailable days are excluded from the positive population")
func unavailableDaysAreExcludedFromPopulation() {
  // Arrange: target + 13 positive days would rank, but coverage starts late so
  // the two oldest days are unavailable, dropping the count to 12 (neutral).
  let steps = stepsByDay(targetSteps: 5000, positiveOffsets: Array(-13 ... -1))
  let clippedCoverage = StepDataCoverage(
    firstAvailableDay: targetDay.adding(days: -11, calendar: calendar),
    lastSyncedDay: targetDay
  )

  // Act
  let result = condition(stepsByDay: steps, coverage: clippedCoverage)

  // Assert
  #expect(result == .neutral)
}
