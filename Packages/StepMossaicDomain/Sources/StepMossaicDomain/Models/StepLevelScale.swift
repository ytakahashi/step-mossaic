/// Configures how many positive levels exist above the empty level.
///
/// Keeping the count configurable preserves the current "empty + 4 levels"
/// behavior while leaving room to change the granularity later.
public struct StepLevelScale: Equatable, Sendable {
  /// Number of positive levels. Positive days rank in `1...positiveLevelCount`.
  public let positiveLevelCount: Int

  public init(positiveLevelCount: Int = 4) {
    precondition(positiveLevelCount >= 1, "positiveLevelCount must be >= 1")
    self.positiveLevelCount = positiveLevelCount
  }
}
