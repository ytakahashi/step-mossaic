import Foundation

/// Computes the as-of `AsOfCondition` for a target day.
///
/// The population for target day `D` is the inclusive window
/// `[D - (asOfWindowDays - 1) ... D]`, restricted to available, positive days.
/// The window, cold-start threshold, and level scale are injected rather than
/// read from a config type, so this stays usable before marimo config exists.
public enum AsOfConditionCalculator {
  /// Computes the condition for `targetDay`.
  ///
  /// - A zero-step target day is `.ranked(.empty)`, never neutral: a rest day is
  ///   a definite result.
  /// - If the window holds fewer positive days than `coldStartMinimumPositiveDays`,
  ///   the result is `.neutral` (not enough history to rank fairly).
  /// - Otherwise the target is ranked by `RelativeScaler`.
  ///
  /// `targetDay` must be available (a precondition): callers compute as-of only
  /// for available days, and an unavailable day is "no data", not a 0-step day.
  /// `stepsByDay` holds steps for days that have an entry; a day within coverage
  /// but absent from the map is treated as an available 0-step day, which is
  /// excluded from the positive population.
  public static func condition(
    for targetDay: Day,
    stepsByDay: [Day: Int],
    coverage: StepDataCoverage,
    calendar: Calendar,
    asOfWindowDays: Int,
    coldStartMinimumPositiveDays: Int,
    levelScale: StepLevelScale
  ) -> AsOfCondition {
    precondition(asOfWindowDays >= 1, "asOfWindowDays must be >= 1")
    precondition(coldStartMinimumPositiveDays >= 0, "coldStartMinimumPositiveDays must be >= 0")
    precondition(coverage.isAvailable(targetDay), "targetDay must be available")

    let targetSteps = stepsByDay[targetDay] ?? 0
    guard targetSteps > 0 else {
      return .ranked(.empty)
    }

    // Inclusive window ending on the target day: [D - (window - 1) ... D].
    let windowStart = targetDay.adding(days: -(asOfWindowDays - 1), calendar: calendar)
    let window = DayInterval(start: windowStart, end: targetDay)

    // Population excludes unavailable days and 0-step days (see RelativeScaler).
    let positivePopulation =
      window.days(calendar: calendar)
      .filter { coverage.isAvailable($0) }
      .map { stepsByDay[$0] ?? 0 }
      .filter { $0 > 0 }

    guard positivePopulation.count >= coldStartMinimumPositiveDays else {
      return .neutral
    }

    let level = RelativeScaler.level(for: targetSteps, in: positivePopulation, scale: levelScale)
    return .ranked(level)
  }
}
