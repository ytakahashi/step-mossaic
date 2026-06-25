import Foundation
import Testing

@testable import StepMossaicDomain

@Test("Enumerates every day in the range, both bounds inclusive")
func dayIntervalEnumeratesEveryDayInclusive() {
  // Arrange
  let interval = DayInterval(start: makeDay(2026, 6, 1), end: makeDay(2026, 6, 3))

  // Act
  let days = interval.days(calendar: TestCalendar.utc)

  // Assert: start and end both appear, with no gaps.
  #expect(days == [makeDay(2026, 6, 1), makeDay(2026, 6, 2), makeDay(2026, 6, 3)])
}

@Test("A single-day interval yields exactly that day")
func dayIntervalWithEqualBoundsHasSingleDay() {
  // Arrange: start == end, the minimum valid interval.
  let interval = DayInterval(start: makeDay(2026, 6, 1), end: makeDay(2026, 6, 1))

  // Act
  let days = interval.days(calendar: TestCalendar.utc)

  // Assert
  #expect(days == [makeDay(2026, 6, 1)])
}

@Test("Contains is inclusive on both bounds and excludes neighbors")
func dayIntervalContainsChecksBothBoundsInclusive() {
  // Arrange
  let interval = DayInterval(start: makeDay(2026, 6, 1), end: makeDay(2026, 6, 3))

  // Act & Assert: the days just outside each bound are excluded.
  #expect(interval.contains(makeDay(2026, 6, 1)))
  #expect(interval.contains(makeDay(2026, 6, 3)))
  #expect(!interval.contains(makeDay(2026, 5, 31)))
  #expect(!interval.contains(makeDay(2026, 6, 4)))
}
