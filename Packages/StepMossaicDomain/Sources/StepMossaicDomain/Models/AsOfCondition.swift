/// The day-by-day condition that drives a marimo's color.
///
/// Unlike a heatmap cell, a marimo's condition has a neutral state for days that
/// do not yet have enough history to rank fairly (cold start). `neutral` is only
/// for the marimo condition; heatmap cells never use it.
public enum AsOfCondition: Equatable, Sendable {
  case neutral
  case ranked(StepLevel)

  /// Maps the condition to a numeric color score.
  ///
  /// - `.ranked(level)` scores as the raw level, so an empty day scores `0`.
  /// - `.neutral` scores at the scale midpoint, e.g. `2.0` for a 4-level scale,
  ///   so cold-start days read as average rather than dark or bright.
  public func colorScore(scale: StepLevelScale) -> Double {
    switch self {
    case .ranked(let level):
      return Double(level.rawValue)
    case .neutral:
      return Double(scale.positiveLevelCount) / 2
    }
  }
}
