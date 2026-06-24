import Foundation

/// Describes which days have step data available, so the domain can tell
/// "no data" apart from "0 steps".
public struct StepDataCoverage: Equatable, Sendable {
  /// Earliest day with available data. `nil` means no coverage exists at all.
  public var firstAvailableDay: Day?
  /// Latest day that has been synced.
  public var lastSyncedDay: Day

  public init(firstAvailableDay: Day?, lastSyncedDay: Day) {
    if let firstAvailableDay {
      precondition(
        firstAvailableDay <= lastSyncedDay,
        "StepDataCoverage firstAvailableDay must be <= lastSyncedDay"
      )
    }
    self.firstAvailableDay = firstAvailableDay
    self.lastSyncedDay = lastSyncedDay
  }

  /// Returns whether `day` is covered.
  ///
  /// Days before `firstAvailableDay` or after `lastSyncedDay` are unavailable
  /// rather than 0 steps. A covered day with no stored entry is treated as an
  /// available 0-step day by downstream aggregation.
  public func isAvailable(_ day: Day) -> Bool {
    guard let firstAvailableDay else { return false }
    return firstAvailableDay <= day && day <= lastSyncedDay
  }
}
