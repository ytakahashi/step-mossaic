/// The domain's single daily-step value, keyed by `Day`.
///
/// Persistence concerns such as `updatedAt` live only in the data layer's
/// record, never here.
public struct DailySteps: Equatable, Sendable {
  public var day: Day
  public var steps: Int

  public init(day: Day, steps: Int) {
    self.day = day
    // Steps round up to non-negative; a negative count is never meaningful.
    self.steps = max(0, steps)
  }
}
