import Foundation

/// Builds a `StepHeatmap` for a display interval.
public enum StepHeatmapGenerator {
  /// Generates the heatmap over `interval`.
  ///
  /// - A cell is produced for every day in `interval`.
  /// - Days outside `coverage` are `.unavailable`; days after the synced range
  ///   (e.g. future days) fall here too.
  /// - A covered day with no entry is an available 0-step day.
  /// - Total and average count available days only; the average's denominator is
  ///   the available-day count, including available 0-step days.
  /// - Relativization ranks each available day against the available, positive
  ///   days within this interval — unavailable and 0-step days are not in the
  ///   population.
  public static func heatmap(
    for interval: DayInterval,
    stepsByDay: [Day: Int],
    coverage: StepDataCoverage,
    calendar: Calendar,
    levelScale: StepLevelScale
  ) -> StepHeatmap {
    // `stepsByDay` is assumed non-negative: step counts cannot be negative and
    // the upstream daily-step value clamps them. We deliberately skip validating
    // it — scanning every entry per call is not worth guarding an input that
    // cannot realistically occur.
    let days = interval.days(calendar: calendar)

    // Available days within the interval and their steps (missing entry = 0).
    let availableDays = days.filter { coverage.isAvailable($0) }
    let availableSteps = availableDays.map { stepsByDay[$0] ?? 0 }

    // Population for relativization: available positive days only. 0-step days
    // are excluded here but still counted in the average below.
    let positivePopulation = availableSteps.filter { $0 > 0 }

    let cells = days.map { day -> StepHeatmapCell in
      guard coverage.isAvailable(day) else {
        return StepHeatmapCell(day: day, state: .unavailable)
      }
      let steps = stepsByDay[day] ?? 0
      let level = RelativeScaler.level(for: steps, in: positivePopulation, scale: levelScale)
      return StepHeatmapCell(day: day, state: .available(steps: steps, level: level))
    }

    let totalSteps = availableSteps.reduce(0, +)
    // Guard against an empty denominator when no day is available.
    let averageStepsPerAvailableDay =
      availableDays.isEmpty ? 0 : Double(totalSteps) / Double(availableDays.count)

    return StepHeatmap(
      interval: interval,
      cells: cells,
      totalSteps: totalSteps,
      averageStepsPerAvailableDay: averageStepsPerAvailableDay
    )
  }
}
