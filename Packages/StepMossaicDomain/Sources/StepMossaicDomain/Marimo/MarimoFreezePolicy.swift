import Foundation

/// Whether a month's marimo may still change.
public enum MarimoLockState: Equatable, Sendable {
  /// The current (or a not-yet-started) month: freely regenerated.
  case growing
  /// A past month still inside its grace period: may be regenerated.
  case grace
  /// A past month past its grace period: frozen.
  case locked
}

/// Decides whether a month's marimo is still growing, in grace, or locked.
///
/// This is a pure policy. Persistence — whether to regenerate, skip, or delete a
/// frozen marimo — is the data layer's concern, not this type's.
public struct MarimoFreezePolicy: Equatable, Sendable {
  /// Days after the month ends during which the marimo may still be regenerated.
  public var gracePeriodDays: Int

  public init(gracePeriodDays: Int) {
    precondition(gracePeriodDays >= 0, "gracePeriodDays must be >= 0")
    self.gracePeriodDays = gracePeriodDays
  }

  /// Returns the lock state of `yearMonth`'s marimo as of `now`.
  ///
  /// - The current month is `.growing`; a future month is too, since it cannot
  ///   be frozen before it starts.
  /// - A past month is `.grace` from the first day of the next month until
  ///   `gracePeriodDays` later, then `.locked`. With `gracePeriodDays == 0` it
  ///   locks on the first day of the next month.
  public func lockState(
    for yearMonth: YearMonth,
    now: Day,
    calendar: Calendar
  ) -> MarimoLockState {
    let nowMonth = YearMonth(date: now.start, calendar: calendar)
    guard yearMonth < nowMonth else {
      // Current or future month: nothing to freeze yet.
      return .growing
    }

    // Past month: grace runs [nextMonthStart, nextMonthStart + gracePeriodDays).
    let nextMonthStart = yearMonth.next().interval(calendar: calendar).start
    let lockBoundary = nextMonthStart.adding(days: gracePeriodDays, calendar: calendar)
    return now < lockBoundary ? .grace : .locked
  }
}
