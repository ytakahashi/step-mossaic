/// An aggregated heatmap over a display interval.
///
/// Aggregation lives in the domain, not the UI: it combines coverage clipping,
/// zero-fill, totals, averages, and relativization, which is more than a
/// rendering concern.
public struct StepHeatmap: Equatable, Sendable {
  /// The display interval the cells cover.
  public var interval: DayInterval
  /// One cell per day in `interval`, in chronological order.
  public var cells: [StepHeatmapCell]
  /// Sum of steps over available days only.
  public var totalSteps: Int
  /// Mean steps across available days, counting available 0-step days as 0.
  public var averageStepsPerAvailableDay: Double

  public init(
    interval: DayInterval,
    cells: [StepHeatmapCell],
    totalSteps: Int,
    averageStepsPerAvailableDay: Double
  ) {
    self.interval = interval
    self.cells = cells
    self.totalSteps = totalSteps
    self.averageStepsPerAvailableDay = averageStepsPerAvailableDay
  }
}

/// A single day in the heatmap.
public struct StepHeatmapCell: Equatable, Sendable {
  public var day: Day
  public var state: StepHeatmapCellState

  public init(day: Day, state: StepHeatmapCellState) {
    self.day = day
    self.state = state
  }
}

/// The state of a heatmap cell.
///
/// `unavailable` is "no data" — outside coverage — and is distinct from an
/// available 0-step day, which is `available(steps: 0, level: .empty)`.
public enum StepHeatmapCellState: Equatable, Sendable {
  case unavailable
  case available(steps: Int, level: StepLevel)
}
