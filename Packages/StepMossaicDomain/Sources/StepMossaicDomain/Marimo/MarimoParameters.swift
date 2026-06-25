/// Rendering parameters for a single month's marimo.
///
/// This is a plain value holder: `MarimoGenerator` is the canonical producer and
/// already clamps each field to its configured range, so no clamping is repeated
/// here (which also avoids hard-coding a color range that the level scale owns).
public struct MarimoParameters: Equatable, Sendable {
  public var sizeUnit: Double
  public var colorLevel: Double
  public var bumpiness: Double
  public var seed: UInt64
  public var totalSteps: Int

  public init(
    sizeUnit: Double,
    colorLevel: Double,
    bumpiness: Double,
    seed: UInt64,
    totalSteps: Int
  ) {
    self.sizeUnit = sizeUnit
    self.colorLevel = colorLevel
    self.bumpiness = bumpiness
    self.seed = seed
    self.totalSteps = totalSteps
  }
}
