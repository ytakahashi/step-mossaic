import Testing

@testable import StepMossaicDomain

@Test("The empty level has raw value 0")
func stepLevelEmptyIsZero() {
  // Act & Assert
  #expect(StepLevel.empty.rawValue == 0)
}

@Test("Levels order by their raw value")
func stepLevelsOrderByRawValue() {
  // Act & Assert: empty sorts below any positive level.
  #expect(StepLevel.empty < StepLevel(rawValue: 1))
  #expect(StepLevel(rawValue: 1) < StepLevel(rawValue: 4))
}

@Test("A default scale exposes four positive levels")
func stepLevelScaleDefaultsToFour() {
  // Act & Assert
  #expect(StepLevelScale().positiveLevelCount == 4)
}
