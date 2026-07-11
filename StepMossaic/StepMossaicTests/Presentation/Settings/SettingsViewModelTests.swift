import Foundation
import StepMossaicDomain
import Testing
import UIKit

@testable import StepMossaic

/// Wires a settings model to a fake source and a sync model backed by an
/// in-memory cache, mirroring the other view-model tests' `makeModel` helpers.
@MainActor
private func makeSettingsModel(
  source: any StepSource,
  today: Date = makeDate(2026, 6, 28),
  openURL: @escaping (URL) -> Void = { _ in }
) throws -> (SettingsViewModel, StepSyncModel) {
  let context = try InMemoryStore.makeContext()
  let store = SwiftDataStepLogStore(context: context, calendar: testCalendar, now: { today })
  let marimoStore = SwiftDataMarimoStore(context: context)
  let coordinator = StepSyncCoordinator(
    source: source, stepLogStore: store, marimoStore: marimoStore, calendar: testCalendar,
    now: { today })
  let syncModel = StepSyncModel(coordinator: coordinator)
  let model = SettingsViewModel(source: source, syncModel: syncModel, openURL: openURL)
  return (model, syncModel)
}

@MainActor
@Test("Refreshing status maps each authorization status directly from the source")
func settingsRefreshesAuthorizationStatus() throws {
  // Act & Assert
  for status: HealthAuthorizationStatus in [.unavailable, .notDetermined, .requested] {
    let (model, _) = try makeSettingsModel(source: FakeStepSource(status: status))
    model.refreshStatus()
    #expect(model.authorizationStatus == status)
  }
}

@MainActor
@Test("Requesting access prompts HealthKit and resolves to requested")
func settingsRequestAccessBecomesRequested() async throws {
  // Arrange
  let source = FakeStepSource(status: .notDetermined)
  let (model, _) = try makeSettingsModel(source: source)
  model.refreshStatus()
  #expect(model.authorizationStatus == .notDetermined)

  // Act
  await model.requestAccess()

  // Assert: the prompt was shown once and the resolved status is now requested.
  #expect(source.requestAuthorizationCount == 1)
  #expect(model.authorizationStatus == .requested)
}

@MainActor
@Test("Opening Health settings invokes the injected URL opener exactly once with the settings URL")
func settingsOpenHealthSettingsOpensSettingsURL() throws {
  // Arrange
  var openedURLs: [URL] = []
  let (model, _) = try makeSettingsModel(
    source: FakeStepSource(status: .requested),
    openURL: { openedURLs.append($0) }
  )

  // Act
  model.openHealthSettings()

  // Assert
  #expect(openedURLs == [URL(string: UIApplication.openSettingsURLString)!])
}

@MainActor
@Test("Opening the Privacy Policy invokes the injected URL opener with the published page")
func settingsOpenPrivacyPolicyOpensPublishedURL() throws {
  // Arrange
  var openedURLs: [URL] = []
  let (model, _) = try makeSettingsModel(
    source: FakeStepSource(status: .requested),
    openURL: { openedURLs.append($0) }
  )

  // Act
  model.openPrivacyPolicy()

  // Assert: the exact published Privacy Policy URL, not the Health/App
  // Settings URL used elsewhere on this screen.
  #expect(openedURLs == [URL(string: "https://ytakahashi.github.io/step-mossaic/privacy/")!])
}

@MainActor
@Test("Rebuilding the cache delegates to the shared sync model")
func settingsRebuildCacheDelegatesToSyncModel() async throws {
  // Arrange: a cache already settled on ready, so a rebuild has something to redo.
  let source = FakeStepSource(
    status: .requested,
    stepsToReturn: [DailySteps(day: makeDay(2026, 6, 27), steps: 8_432)],
    earliest: makeDate(2026, 6, 1)
  )
  let (model, syncModel) = try makeSettingsModel(source: source, today: makeDate(2026, 6, 28))
  await syncModel.start()
  #expect(syncModel.phase == .ready)
  #expect(syncModel.completedSyncCount == 1)

  // Act
  await model.rebuildCache()

  // Assert: the shared sync model (not some parallel path) ran another full
  // rebuild turn and settled it.
  #expect(syncModel.phase == .ready)
  #expect(syncModel.completedSyncCount == 2)
}
