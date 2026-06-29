import Foundation

/// The angle→radius mapping that gives a marimo its wobbled outline.
///
/// Pure and deterministic so the shape is testable and renders identically for a
/// given month: the drawing layer only samples this mapping and strokes a path.
/// Size and color are *not* part of the shape — the renderer scales the unit
/// radius by size and fills by color; this type owns only the wobble.
public enum MarimoShape {
  /// Number of seeded harmonics summed into the outline. A handful reads as
  /// organic lumps rather than either a smooth ellipse (too few) or noise (many).
  private static let harmonicCount = 4
  /// Maximum radial deviation at full bumpiness, as a fraction of the unit radius.
  ///
  /// Kept below 1 so the radius is always strictly positive. Exposed so a renderer
  /// can reserve a fixed margin for the wobble's peak (`1 + maximumAmplitude`) and
  /// keep the drawn size driven by size alone, not by how bumpy the marimo is.
  public static let maximumAmplitude = 0.28

  /// The unit radius (centered on `1.0`) at `angle`, wobbled by `bumpiness`.
  ///
  /// - Periodic over `2 * .pi`: `radius(atAngle: 0)` equals `radius(atAngle: 2π)`,
  ///   so a sampled outline closes smoothly with no seam.
  /// - Mean over a full turn is `1.0`: the wobble only redistributes radius, it
  ///   does not inflate or shrink the marimo (size does that).
  /// - `bumpiness <= 0` returns exactly `1.0` (a true circle); `bumpiness` is
  ///   clamped to `0...1`, and the deviation scales linearly with it.
  /// - Deterministic in `seed`: same seed, same outline; different seeds vary the
  ///   harmonic weights and phases.
  public static func radius(atAngle angle: Double, bumpiness: Double, seed: UInt64) -> Double {
    let clampedBumpiness = min(max(bumpiness, 0), 1)
    guard clampedBumpiness > 0 else { return 1 }

    var rng = SplitMix64(seed: seed)
    var weightedWobble = 0.0
    var totalWeight = 0.0
    // Integer frequencies keep every term 2π-periodic, which is what makes the
    // sampled outline close without a seam.
    for harmonic in 1...harmonicCount {
      let frequency = Double(2 * harmonic + 1)
      let weight = 0.5 + 0.5 * rng.nextUnitDouble()
      let phase = 2 * .pi * rng.nextUnitDouble()
      weightedWobble += weight * sin(frequency * angle + phase)
      totalWeight += weight
    }

    // Normalize by the weight sum so the deviation never exceeds the configured
    // amplitude regardless of how the random weights fall.
    let wobble = weightedWobble / totalWeight
    return 1 + maximumAmplitude * clampedBumpiness * wobble
  }

  /// Samples `radius(atAngle:bumpiness:seed:)` at `sampleCount` evenly spaced
  /// angles around the full turn, for a renderer to connect into a closed path.
  public static func radii(bumpiness: Double, seed: UInt64, sampleCount: Int) -> [Double] {
    precondition(sampleCount >= 1, "sampleCount must be >= 1")
    return (0..<sampleCount).map { index in
      let angle = 2 * .pi * Double(index) / Double(sampleCount)
      return radius(atAngle: angle, bumpiness: bumpiness, seed: seed)
    }
  }
}

/// Small, fast, deterministic PRNG used to derive a marimo's harmonic weights and
/// phases from its seed. Self-contained so the shape stays a pure value mapping
/// with no dependency on `SystemRandomNumberGenerator`.
private struct SplitMix64 {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state = state &+ 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  /// A value in `[0, 1)`, using the top 53 bits so the mantissa fills evenly.
  mutating func nextUnitDouble() -> Double {
    Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
  }
}
