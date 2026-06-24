import Foundation
import Testing

@testable import StepMossaicDomain

@Test("Normalizes any timestamp to the start of its local day")
func dayNormalizesToStartOfLocalDay() {
  // Arrange: a late-evening timestamp, to prove the time-of-day is dropped
  // rather than merely preserved.
  let calendar = TestCalendar.utc
  let components = DateComponents(year: 2026, month: 6, day: 25, hour: 23, minute: 59)
  let date = calendar.date(from: components)!

  // Act
  let day = Day(containing: date, calendar: calendar)

  // Assert
  #expect(day.start == calendar.startOfDay(for: date))
}

@Test("Two timestamps on the same local day are equal")
func sameLocalDayProducesEqualDays() {
  // Arrange: morning and evening of the same date.
  let calendar = TestCalendar.utc
  let morningDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 1))!
  let eveningDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 22))!

  // Act
  let morning = Day(containing: morningDate, calendar: calendar)
  let evening = Day(containing: eveningDate, calendar: calendar)

  // Assert: keying by Day collapses intra-day differences.
  #expect(morning == evening)
}

@Test("Orders days by their start instant")
func daysAreOrderedByStart() {
  // Act & Assert
  #expect(makeDay(2026, 6, 24) < makeDay(2026, 6, 25))
}

@Test("Adding days crosses the month boundary")
func addingDaysCrossesMonthBoundary() {
  // Arrange
  let calendar = TestCalendar.utc

  // Act
  let dayAfter = makeDay(2026, 6, 30).adding(days: 1, calendar: calendar)
  let dayBefore = makeDay(2026, 7, 1).adding(days: -1, calendar: calendar)

  // Assert: rolls into the next/previous month, not just +/-1 to the day number.
  #expect(dayAfter == makeDay(2026, 7, 1))
  #expect(dayBefore == makeDay(2026, 6, 30))
}
