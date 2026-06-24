import Foundation

/// An inclusive range of days, used instead of `DateInterval` for day-granular
/// domain logic.
public struct DayInterval: Equatable, Sendable {
  /// First day in the range, inclusive.
  public var start: Day
  /// Last day in the range, inclusive.
  public var end: Day

  public init(start: Day, end: Day) {
    precondition(start <= end, "DayInterval start must be <= end")
    self.start = start
    self.end = end
  }

  /// Returns whether `day` falls within `start...end` (both inclusive).
  public func contains(_ day: Day) -> Bool {
    start <= day && day <= end
  }

  /// Returns every day in the range from `start` to `end`, inclusive.
  public func days(calendar: Calendar) -> [Day] {
    var result: [Day] = []
    var current = start
    while current <= end {
      result.append(current)
      current = current.adding(days: 1, calendar: calendar)
    }
    return result
  }
}
