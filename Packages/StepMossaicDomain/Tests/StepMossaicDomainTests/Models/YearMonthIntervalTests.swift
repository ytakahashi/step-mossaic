import Foundation
import Testing

@testable import StepMossaicDomain

@Test("Interval spans the whole month, both bounds inclusive")
func yearMonthIntervalCoversWholeMonth() {
  // Act
  let interval = YearMonth(year: 2026, month: 6).interval(calendar: TestCalendar.utc)

  // Assert
  #expect(interval.start == makeDay(2026, 6, 1))
  #expect(interval.end == makeDay(2026, 6, 30))
}

@Test("Derives the last day from the next month, so leap February is 29 days")
func yearMonthIntervalHandlesLeapFebruary() {
  // Act
  let interval = YearMonth(year: 2024, month: 2).interval(calendar: TestCalendar.utc)

  // Assert: month length is left to Calendar rather than hand-coded.
  #expect(interval.end == makeDay(2024, 2, 29))
}

@Test("Interprets year/month as Gregorian while honoring the injected time zone")
func yearMonthIntervalUsesGregorianYearMonthWithInjectedTimeZone() {
  // Arrange: a Japanese-era calendar would otherwise read 2026 as an era year.
  // Act
  let interval = YearMonth(year: 2026, month: 6).interval(calendar: TestCalendar.japaneseTokyo)

  // Assert: bounds match the Gregorian month, with day boundaries in Tokyo time.
  #expect(interval.start == makeDay(2026, 6, 1, calendar: TestCalendar.tokyo))
  #expect(interval.end == makeDay(2026, 6, 30, calendar: TestCalendar.tokyo))
}

@Test("next() advances the month and wraps across the year")
func yearMonthNextWrapsAcrossYear() {
  // Act & Assert: December wraps to the next January.
  #expect(YearMonth(year: 2026, month: 12).next() == YearMonth(year: 2027, month: 1))
  #expect(YearMonth(year: 2026, month: 6).next() == YearMonth(year: 2026, month: 7))
}

@Test("previous() steps back the month and wraps across the year")
func yearMonthPreviousWrapsAcrossYear() {
  // Act & Assert: January wraps to the previous December.
  #expect(YearMonth(year: 2026, month: 1).previous() == YearMonth(year: 2025, month: 12))
  #expect(YearMonth(year: 2026, month: 6).previous() == YearMonth(year: 2026, month: 5))
}
