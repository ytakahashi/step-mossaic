import Foundation
import StepMossaicDomain

/// One week of the heatmap, drawn as a row: seven slots left-to-right by weekday.
/// Weeks stack top-to-bottom, oldest first.
struct HeatmapWeek: Identifiable {
  /// Week index from the start of the range; stable for `ForEach`.
  let id: Int
  /// Exactly seven slots, ordered by weekday from the calendar's `firstWeekday`.
  let slots: [HeatmapSlot]
  /// Short month name shown on the left axis when this week begins a new month;
  /// `nil` for weeks that continue the previous month.
  let monthLabel: String?
}

/// A single position in the weekday-aligned grid: a real day or padding that
/// fills the partial first and last weeks.
enum HeatmapSlot: Identifiable {
  case day(StepHeatmapCell)
  case padding(Int)

  var id: String {
    switch self {
    case .day(let cell): "day-\(cell.day.start.timeIntervalSinceReferenceDate)"
    case .padding(let index): "padding-\(index)"
    }
  }
}

/// Arranges chronological heatmap cells into weekday-aligned week rows: each row
/// is a calendar week, each column a weekday, oldest week on top.
///
/// Kept separate from the view so the alignment rule (leading/trailing padding,
/// weekday offset, month labelling) is a pure function that can be unit tested.
enum HeatmapLayout {
  static func weeks(for cells: [StepHeatmapCell], calendar: Calendar) -> [HeatmapWeek] {
    guard let first = cells.first else { return [] }

    // Pad the first week so the first day sits under its weekday column, and the
    // last week so every row has a full seven slots.
    let leading = weekdayOffset(first.day, calendar: calendar)
    var slots: [HeatmapSlot] = (0..<leading).map { .padding($0) }
    slots += cells.map { .day($0) }
    let remainder = slots.count % 7
    if remainder != 0 {
      let trailingBase = slots.count
      slots += (0..<(7 - remainder)).map { .padding(trailingBase + $0) }
    }

    let shortMonths = calendar.shortMonthSymbols
    var lastLabeledMonth: Int?

    return stride(from: 0, to: slots.count, by: 7).enumerated().map { index, start in
      let weekSlots = Array(slots[start..<start + 7])

      // Label the week with its month only when the month changes, keyed off the
      // week's first real day; this marks where each month begins down the axis.
      var monthLabel: String?
      if let firstDay = weekSlots.firstDay {
        let month = calendar.component(.month, from: firstDay.start)
        if month != lastLabeledMonth {
          monthLabel = shortMonths[month - 1]
          lastLabeledMonth = month
        }
      }

      return HeatmapWeek(id: index, slots: weekSlots, monthLabel: monthLabel)
    }
  }

  /// Column index (0-based from `firstWeekday`) a day occupies within its week.
  static func weekdayOffset(_ day: Day, calendar: Calendar) -> Int {
    (calendar.component(.weekday, from: day.start) - calendar.firstWeekday + 7) % 7
  }

  /// Number of week columns a range occupies — its day span plus the weekday
  /// padding before the first day, rounded up to whole weeks. Lets the view size
  /// cells to a target span without building the cells.
  static func weekCount(for interval: DayInterval, calendar: Calendar) -> Int {
    let leading = weekdayOffset(interval.start, calendar: calendar)
    let days = interval.days(calendar: calendar).count
    return Int((Double(leading + days) / 7.0).rounded(.up))
  }
}

extension [HeatmapSlot] {
  /// The first real day in the row, ignoring padding.
  fileprivate var firstDay: Day? {
    for slot in self {
      if case .day(let cell) = slot { return cell.day }
    }
    return nil
  }
}
