import Foundation
import Testing

@testable import StepMossaicDomain

private let defaultCalendar = TestCalendar.utc

private func lockState(
  _ yearMonth: YearMonth,
  now: Day,
  gracePeriodDays: Int,
  calendar: Calendar = defaultCalendar
) -> MarimoLockState {
  MarimoFreezePolicy(gracePeriodDays: gracePeriodDays)
    .lockState(for: yearMonth, now: now, calendar: calendar)
}

@Test("The current month is growing")
func currentMonthIsGrowing() {
  // Act: mid-month of the same month.
  let state = lockState(
    YearMonth(year: 2026, month: 6), now: makeDay(2026, 6, 15), gracePeriodDays: 5)

  // Assert
  #expect(state == .growing)
}

@Test("A future month is growing, since it cannot freeze before it starts")
func futureMonthIsGrowing() {
  // Act: now is in June, the month is July.
  let state = lockState(
    YearMonth(year: 2026, month: 7), now: makeDay(2026, 6, 15), gracePeriodDays: 5)

  // Assert
  #expect(state == .growing)
}

@Test("A past month is in grace from the next month start through the grace period")
func pastMonthIsGraceWithinGracePeriod() {
  // Arrange: May's marimo, 5-day grace. Grace covers 6/1...6/5.
  let may = YearMonth(year: 2026, month: 5)

  // Act & Assert
  #expect(lockState(may, now: makeDay(2026, 6, 1), gracePeriodDays: 5) == .grace)
  #expect(lockState(may, now: makeDay(2026, 6, 5), gracePeriodDays: 5) == .grace)
}

@Test("A past month locks once the grace period ends")
func pastMonthLocksAfterGracePeriod() {
  // Arrange: May's marimo, 5-day grace. 6/6 is the first locked day.
  let may = YearMonth(year: 2026, month: 5)

  // Act & Assert
  #expect(lockState(may, now: makeDay(2026, 6, 6), gracePeriodDays: 5) == .locked)
  #expect(lockState(may, now: makeDay(2026, 6, 30), gracePeriodDays: 5) == .locked)
}

@Test("Injected calendar timezone is honored while year and month remain Gregorian")
func lockStateUsesGregorianYearMonthWithInjectedTimeZone() {
  // Arrange: the Japanese calendar would read 2026 as an era year if the policy
  // did not force Gregorian year/month components.
  let may = YearMonth(year: 2026, month: 5)
  let now = makeDay(2026, 6, 6, calendar: TestCalendar.tokyo)

  // Act
  let state = lockState(may, now: now, gracePeriodDays: 5, calendar: TestCalendar.japaneseTokyo)

  // Assert
  #expect(state == .locked)
}

@Test("A zero-day grace locks on the first day of the next month")
func zeroGracePeriodLocksImmediately() {
  // Act: no grace window, so the next month's first day is already locked.
  let state = lockState(
    YearMonth(year: 2026, month: 5), now: makeDay(2026, 6, 1), gracePeriodDays: 0)

  // Assert
  #expect(state == .locked)
}
