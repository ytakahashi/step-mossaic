import Foundation

/// A calendar day keyed by the start instant of its local day.
///
/// Daily data is keyed by `Day` rather than a raw `Date` so that two timestamps
/// falling on the same local day compare and hash as the same value. The
/// normalization depends on the injected `Calendar`, keeping the domain free of
/// any implicit `Calendar.current` access.
public struct Day: Hashable, Comparable, Sendable {
  /// Start instant of the local day, normalized by the injected `Calendar`.
  public let start: Date

  /// Creates the `Day` that contains `date` in the given `calendar`.
  public init(containing date: Date, calendar: Calendar) {
    self.start = calendar.startOfDay(for: date)
  }

  /// Returns the `Day` offset by `days` from the receiver.
  ///
  /// Re-normalizing with `startOfDay` keeps the result on a day boundary even
  /// across DST transitions, where adding 24h would otherwise drift.
  public func adding(days: Int, calendar: Calendar) -> Day {
    let date = calendar.date(byAdding: .day, value: days, to: start)!
    return Day(containing: date, calendar: calendar)
  }

  public static func < (lhs: Day, rhs: Day) -> Bool {
    lhs.start < rhs.start
  }
}
