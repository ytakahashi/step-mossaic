public struct MarimoParameters: Equatable, Sendable {
  public var sizeUnit: Double
  public var colorLevel: Double
  public var bumpiness: Double
  public var seed: UInt64
  public var totalSteps: Int

  public init(
    sizeUnit: Double, colorLevel: Double, bumpiness: Double, seed: UInt64, totalSteps: Int
  ) {
    self.sizeUnit = sizeUnit.clamped(to: 0...1)
    self.colorLevel = colorLevel.clamped(to: 0...4)
    self.bumpiness = bumpiness.clamped(to: 0...1)
    self.seed = seed
    self.totalSteps = max(0, totalSteps)
  }
}
