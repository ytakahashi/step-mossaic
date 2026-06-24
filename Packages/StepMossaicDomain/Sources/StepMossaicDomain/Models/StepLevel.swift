/// A relativized step rank, wrapping the raw level so the domain never passes
/// bare `Int` levels around.
public struct StepLevel: Hashable, Comparable, Sendable {
  /// The neutral, no-activity level. Always rank 0.
  public static let empty = StepLevel(rawValue: 0)

  /// Rank value. `0` is empty; positive days are ranked `1...positiveLevelCount`.
  public let rawValue: Int

  public init(rawValue: Int) {
    precondition(rawValue >= 0, "StepLevel rawValue must be non-negative")
    self.rawValue = rawValue
  }

  public static func < (lhs: StepLevel, rhs: StepLevel) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}
