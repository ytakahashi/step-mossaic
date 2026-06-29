import Foundation
import Testing

@testable import StepMossaicDomain

@Test("Zero bumpiness yields a true circle of unit radius")
func shapeIsCircleWithoutBumpiness() {
  // Act
  let radii = MarimoShape.radii(bumpiness: 0, seed: 202_606, sampleCount: 64)

  // Assert: every sample sits exactly on the unit radius, so the outline is round.
  #expect(radii.allSatisfy { $0 == 1 })
}

@Test("The outline closes seamlessly: radius is periodic over a full turn")
func shapeRadiusIsPeriodic() {
  // Act
  let atStart = MarimoShape.radius(atAngle: 0, bumpiness: 0.8, seed: 7)
  let afterFullTurn = MarimoShape.radius(atAngle: 2 * .pi, bumpiness: 0.8, seed: 7)

  // Assert: angle 0 and 2π map to the same radius, so a sampled loop has no seam.
  #expect(abs(atStart - afterFullTurn) < 1e-9)
}

@Test("Same seed reproduces the outline; different seeds vary it")
func shapeIsDeterministicPerSeed() {
  // Act
  let first = MarimoShape.radii(bumpiness: 0.6, seed: 42, sampleCount: 48)
  let same = MarimoShape.radii(bumpiness: 0.6, seed: 42, sampleCount: 48)
  let different = MarimoShape.radii(bumpiness: 0.6, seed: 43, sampleCount: 48)

  // Assert
  #expect(first == same)
  #expect(first != different)
}

@Test("Deviation from the unit radius grows with bumpiness")
func shapeAmplitudeScalesWithBumpiness() {
  // Arrange: peak deviation from radius 1 at two bumpiness levels, same seed.
  func peakDeviation(bumpiness: Double) -> Double {
    MarimoShape.radii(bumpiness: bumpiness, seed: 99, sampleCount: 256)
      .map { abs($0 - 1) }
      .max() ?? 0
  }

  // Act
  let gentle = peakDeviation(bumpiness: 0.3)
  let strong = peakDeviation(bumpiness: 0.9)

  // Assert: a bumpier marimo deviates further from the circle. A positive gentle
  // value also proves any bumpiness already breaks the perfect circle.
  #expect(gentle > 0)
  #expect(strong > gentle)
}

@Test("Radius stays centered on 1 and strictly positive")
func shapeRadiusIsCenteredAndPositive() {
  // Arrange: a dense sweep at full bumpiness, the worst case for both bounds.
  let radii = MarimoShape.radii(bumpiness: 1, seed: 12_345, sampleCount: 720)

  // Act
  let mean = radii.reduce(0, +) / Double(radii.count)

  // Assert: the wobble redistributes radius without inflating it (mean ≈ 1) and
  // never collapses through the center (all positive), so the fill can't invert.
  #expect(abs(mean - 1) < 0.01)
  #expect(radii.allSatisfy { $0 > 0 })
}
