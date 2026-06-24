import Testing

@testable import StepMossaicDomain

@Test func zeroStepsAreLevelZero() {
  #expect(RelativeScaler.level(for: 0, in: [100, 200, 300]) == 0)
}

@Test func positiveStepsAreRankedIntoFourLevels() {
  let population = [100, 200, 300, 400]

  #expect(RelativeScaler.level(for: 100, in: population) == 1)
  #expect(RelativeScaler.level(for: 200, in: population) == 2)
  #expect(RelativeScaler.level(for: 300, in: population) == 3)
  #expect(RelativeScaler.level(for: 400, in: population) == 4)
}
