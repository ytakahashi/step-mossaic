import Foundation
import StepMossaicDomain
import Testing

@testable import StepMossaic

@MainActor
@Test("Maps each authorization status to a phase")
func homeViewModelMapsAuthorizationToPhase() {
  // Act & Assert
  for (status, expected) in [
    (HealthAuthorizationStatus.notDetermined, HomeViewModel.Phase.needsAuthorization),
    (.requested, .ready),
    (.unavailable, .unavailable),
  ] {
    let model = HomeViewModel(source: FakeStepSource(status: status), calendar: testCalendar)
    model.refreshPhase()
    #expect(model.phase == expected)
  }
}

@MainActor
@Test("Requesting access prompts HealthKit and moves to the ready phase")
func homeViewModelRequestAccessBecomesReady() async {
  // Arrange
  let source = FakeStepSource(status: .notDetermined)
  let model = HomeViewModel(source: source, calendar: testCalendar)
  model.refreshPhase()
  #expect(model.phase == .needsAuthorization)

  // Act
  await model.requestAccess()

  // Assert: the prompt was shown once and the resolved status is now "requested".
  #expect(source.requestAuthorizationCount == 1)
  #expect(model.phase == .ready)
}

@MainActor
@Test("Loads today's total from the source")
func homeViewModelLoadsTodaySteps() async {
  // Arrange
  let source = FakeStepSource(
    status: .requested,
    stepsToReturn: [DailySteps(day: makeDay(2026, 6, 27), steps: 8_432)]
  )
  let model = HomeViewModel(source: source, calendar: testCalendar)

  // Act
  await model.loadToday()

  // Assert
  #expect(model.todaySteps == 8_432)
}

@MainActor
@Test("Shows zero when the source returns no data")
func homeViewModelLoadsZeroWhenEmpty() async {
  // Arrange: an empty result stands in for "no data" or unconfirmable read access.
  let model = HomeViewModel(source: FakeStepSource(status: .requested), calendar: testCalendar)

  // Act
  await model.loadToday()

  // Assert
  #expect(model.todaySteps == 0)
}
