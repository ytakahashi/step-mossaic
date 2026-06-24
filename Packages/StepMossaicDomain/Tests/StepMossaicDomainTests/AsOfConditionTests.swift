import Testing

@testable import StepMossaicDomain

@Test("A ranked condition scores as its raw level")
func rankedConditionScoresAsRawLevel() {
  // Act & Assert
  #expect(AsOfCondition.ranked(StepLevel(rawValue: 3)).colorScore(scale: StepLevelScale()) == 3.0)
}

@Test("An empty ranked condition scores zero")
func emptyRankedConditionScoresZero() {
  // Act & Assert
  #expect(AsOfCondition.ranked(.empty).colorScore(scale: StepLevelScale()) == 0.0)
}

@Test("A neutral condition scores at the scale midpoint")
func neutralConditionScoresAtMidpoint() {
  // Arrange: the default 4-level scale has a midpoint of 2.0.
  let score = AsOfCondition.neutral.colorScore(scale: StepLevelScale())

  // Assert
  #expect(score == 2.0)
}
