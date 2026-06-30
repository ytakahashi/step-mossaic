import Foundation

extension YearMonth {
  /// Returns the inclusive day range covering this month in the given calendar.
  public func interval(calendar: Calendar) -> DayInterval {
    let gregorianCalendar = calendar.stepMossaicGregorian

    var startComponents = DateComponents()
    startComponents.year = year
    startComponents.month = month
    startComponents.day = 1
    let firstDate = gregorianCalendar.date(from: startComponents)!
    let startDay = Day(containing: firstDate, calendar: gregorianCalendar)

    // Derive the last day from the first day of the next month so calendars and
    // month lengths are handled by `Calendar` rather than hand-coded rules.
    let following = next()
    var followingComponents = DateComponents()
    followingComponents.year = following.year
    followingComponents.month = following.month
    followingComponents.day = 1
    let followingFirstDate = gregorianCalendar.date(from: followingComponents)!
    let lastDate = gregorianCalendar.date(byAdding: .day, value: -1, to: followingFirstDate)!
    let endDay = Day(containing: lastDate, calendar: gregorianCalendar)

    return DayInterval(start: startDay, end: endDay)
  }

  /// Returns the following month. Pure arithmetic; no `Calendar` needed.
  public func next() -> YearMonth {
    if month == 12 {
      return YearMonth(year: year + 1, month: 1)
    }
    return YearMonth(year: year, month: month + 1)
  }

  /// Returns the preceding month. Pure arithmetic; no `Calendar` needed.
  public func previous() -> YearMonth {
    if month == 1 {
      return YearMonth(year: year - 1, month: 12)
    }
    return YearMonth(year: year, month: month - 1)
  }
}

extension Calendar {
  /// Returns the StepMossaic calendar for interpreting stored Gregorian
  /// year/month/day values while preserving the caller's display context.
  ///
  /// `YearMonth` keys are Gregorian, even when the user's current calendar is an
  /// era-based or otherwise non-Gregorian calendar. Time zone and locale still
  /// come from the receiver so local day boundaries and localized presentation stay
  /// aligned with the user's environment.
  public var stepMossaicGregorian: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    calendar.locale = locale
    return calendar
  }
}
