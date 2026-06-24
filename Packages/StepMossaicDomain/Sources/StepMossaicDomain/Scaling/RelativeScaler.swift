/// Converts a target step count into a `StepLevel` relative to a population.
public enum RelativeScaler {
  /// Ranks `steps` against `population` into a `StepLevel`.
  ///
  /// - `steps == 0` is `.empty`.
  /// - Zero-step days are excluded from the population; callers are expected to
  ///   exclude unavailable days before calling.
  /// - Equal step counts always map to the same level.
  /// - The largest population value is able to reach the maximum positive level.
  public static func level(
    for steps: Int,
    in population: [Int],
    scale: StepLevelScale
  ) -> StepLevel {
    guard steps > 0 else {
      return .empty
    }

    // Rank against the distinct positive values, not the raw day population.
    // This relativizes by tier rather than by frequency: how often a given step
    // count occurs does not affect its level, and the largest value always
    // reaches the top level (frequency-weighting would let duplicates of the
    // maximum fall short of it).
    let positiveValues = Set(population.filter { $0 > 0 })
    guard !positiveValues.isEmpty else {
      // No positive reference data: a positive target is the only signal, so it
      // maps to the lowest positive level.
      return StepLevel(rawValue: 1)
    }

    // Strict less-than means equal step counts share a rank, and so a level.
    let rank = positiveValues.filter { $0 < steps }.count
    // A single distinct positive value yields denominator 1 and rank 0: level 1.
    let denominator = max(positiveValues.count - 1, 1)
    let percentile = Double(rank) / Double(denominator)

    let levelOffset = Int((percentile * Double(scale.positiveLevelCount - 1)).rounded(.down))
    // Clamp guards the case where `steps` exceeds every population value (a
    // target outside its own population); realistic callers include the target.
    let rawValue = min(levelOffset + 1, scale.positiveLevelCount)
    return StepLevel(rawValue: rawValue)
  }
}
