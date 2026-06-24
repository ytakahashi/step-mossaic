import Testing

@testable import StepMossaicDomain

@Test("Zero target steps map to the empty level")
func zeroStepsAreEmptyLevel() {
  // Arrange
  let scale = StepLevelScale()

  // Act
  let level = RelativeScaler.level(for: 0, in: [100, 200, 300], scale: scale)

  // Assert
  #expect(level == .empty)
}

@Test("Positive days are ranked into the configured positive levels")
func positiveStepsAreRankedIntoFourLevels() {
  // Arrange
  let scale = StepLevelScale()
  let population = [100, 200, 300, 400]

  // Act
  let levels = population.map {
    RelativeScaler.level(for: $0, in: population, scale: scale).rawValue
  }

  // Assert: evenly spread values span 1...4, with the max reaching the top.
  #expect(levels == [1, 2, 3, 4])
}

@Test("Zero-step days are excluded from the population")
func zeroStepDaysAreExcludedFromPopulation() {
  // Arrange: the same positive distribution, padded with zero-step days.
  let scale = StepLevelScale()
  let positiveOnly = [100, 200, 300, 400]
  let padded = [0, 0, 100, 200, 300, 400]

  // Act
  let withoutZeros = RelativeScaler.level(for: 200, in: positiveOnly, scale: scale)
  let withZeros = RelativeScaler.level(for: 200, in: padded, scale: scale)

  // Assert: padding with zeros does not change the rank.
  #expect(withZeros == withoutZeros)
}

@Test("Equal step counts map to the same level")
func equalStepsMapToSameLevel() {
  // Arrange: duplicated values, so ties must resolve identically.
  let scale = StepLevelScale()
  let population = [100, 100, 200, 200]

  // Act
  let firstHundred = RelativeScaler.level(for: 100, in: population, scale: scale)
  let secondHundred = RelativeScaler.level(for: 100, in: population, scale: scale)
  let firstTwoHundred = RelativeScaler.level(for: 200, in: population, scale: scale)
  let secondTwoHundred = RelativeScaler.level(for: 200, in: population, scale: scale)

  // Assert
  #expect(firstHundred == secondHundred)
  #expect(firstTwoHundred == secondTwoHundred)
}

@Test("A single positive day ranks at level 1")
func singlePositiveDayIsLevelOne() {
  // Arrange: the target day is the only positive day in its population.
  let scale = StepLevelScale()

  // Act
  let level = RelativeScaler.level(for: 500, in: [500], scale: scale)

  // Assert
  #expect(level == StepLevel(rawValue: 1))
}

@Test("The population maximum reaches the top positive level")
func populationMaximumReachesTopLevel() {
  // Arrange
  let scale = StepLevelScale()
  let population = [100, 200, 300, 400]

  // Act
  let level = RelativeScaler.level(for: 400, in: population, scale: scale)

  // Assert
  #expect(level == StepLevel(rawValue: scale.positiveLevelCount))
}

@Test("The population maximum reaches the top level even when duplicated")
func duplicatedPopulationMaximumReachesTopLevel() {
  // Arrange: duplicate maximum values still represent the top distinct rank.
  let scale = StepLevelScale()
  let population = [100, 100, 200, 200]

  // Act
  let level = RelativeScaler.level(for: 200, in: population, scale: scale)

  // Assert
  #expect(level == StepLevel(rawValue: scale.positiveLevelCount))
}

@Test("The positive level count is configurable")
func positiveLevelCountIsConfigurable() {
  // Arrange: a two-level scale instead of the default four.
  let scale = StepLevelScale(positiveLevelCount: 2)
  let population = [100, 200, 300, 400]

  // Act
  let minLevel = RelativeScaler.level(for: 100, in: population, scale: scale)
  let maxLevel = RelativeScaler.level(for: 400, in: population, scale: scale)

  // Assert: ranks span 1...2, honoring the smaller scale.
  #expect(minLevel == StepLevel(rawValue: 1))
  #expect(maxLevel == StepLevel(rawValue: 2))
}
