import Foundation
import StepMossaicDomain
import Testing

@testable import StepMossaic

/// UTC calendar with Sunday as the first weekday and a fixed English locale, so
/// weekday offsets and month-symbol labels are deterministic across machines.
private let sundayFirstCalendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC")!
  calendar.firstWeekday = 1
  calendar.locale = Locale(identifier: "en_US_POSIX")
  return calendar
}()

private func cell(_ year: Int, _ month: Int, _ day: Int) -> StepHeatmapCell {
  StepHeatmapCell(day: makeDay(year, month, day), state: .available(steps: 0, level: .empty))
}

@MainActor
private func dayStart(_ slot: HeatmapSlot?) -> Date? {
  guard case .day(let cell) = slot else { return nil }
  return cell.day.start
}

@MainActor
private func isPadding(_ slot: HeatmapSlot?) -> Bool {
  guard case .padding = slot else { return false }
  return true
}

@MainActor
@Test("Pads the first week so each day lands on its weekday column")
func layoutPadsFirstWeekByWeekday() {
  // Arrange: Jan 1 2026 is a Thursday — four padding slots before it (Sun..Wed).
  let cells = (1...10).map { cell(2026, 1, $0) }

  // Act
  let weeks = HeatmapLayout.weeks(for: cells, calendar: sundayFirstCalendar)

  // Assert
  #expect(weeks.count == 2)
  #expect(isPadding(weeks[0].slots[3]))
  // The first real day sits in the Thursday column (index 4), proving alignment.
  #expect(dayStart(weeks[0].slots[4]) == makeDay(2026, 1, 1).start)
  // The next week starts on Sunday (first column) with Jan 4.
  #expect(dayStart(weeks[1].slots[0]) == makeDay(2026, 1, 4).start)
}

@MainActor
@Test("Pads the final partial week to a full seven slots")
func layoutPadsTrailingWeek() {
  // Arrange: a single day produces one week padded out to seven slots.
  let weeks = HeatmapLayout.weeks(for: [cell(2026, 1, 4)], calendar: sundayFirstCalendar)

  // Assert: Jan 4 (Sunday) first, the remaining six columns padded.
  #expect(weeks.count == 1)
  #expect(weeks[0].slots.count == 7)
  #expect(dayStart(weeks[0].slots[0]) == makeDay(2026, 1, 4).start)
  #expect((1...6).allSatisfy { isPadding(weeks[0].slots[$0]) })
}

@MainActor
@Test("Labels a week only when its month changes")
func layoutLabelsMonthBoundaries() {
  // Arrange: span late January into February so the month label moves once.
  let cells = (25...31).map { cell(2026, 1, $0) } + (1...7).map { cell(2026, 2, $0) }

  // Act
  let weeks = HeatmapLayout.weeks(for: cells, calendar: sundayFirstCalendar)

  // Assert: the first week is labelled Jan; February's label appears on the first
  // week whose leading day is in February, and intervening weeks stay unlabelled.
  #expect(weeks.first?.monthLabel == "Jan")
  #expect(weeks.contains { $0.monthLabel == "Feb" })
  #expect(weeks.filter { $0.monthLabel != nil }.count == 2)
}

@MainActor
@Test("No cells produces no weeks")
func layoutEmptyForNoCells() {
  // Act & Assert
  #expect(HeatmapLayout.weeks(for: [], calendar: sundayFirstCalendar).isEmpty)
}
