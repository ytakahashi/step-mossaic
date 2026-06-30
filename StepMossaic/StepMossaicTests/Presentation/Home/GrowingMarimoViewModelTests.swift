import Foundation
import StepMossaicDomain
import Testing

@testable import StepMossaic

/// Wires a growing-marimo view model to an in-memory cache and a fake source with
/// a fixed clock, and returns the shared `StepSyncModel` so tests drive the sync
/// through it exactly as `HomeView` does.
@MainActor
private func makeModel(
  source: FakeStepSource,
  today: Date
) throws -> (sync: StepSyncModel, marimo: GrowingMarimoViewModel) {
  let context = try InMemoryStore.makeContext()
  let store = SwiftDataStepLogStore(context: context, calendar: testCalendar, now: { today })
  let coordinator = StepSyncCoordinator(
    source: source, stepLogStore: store, marimoStore: SwiftDataMarimoStore(context: context),
    calendar: testCalendar, now: { today })
  let sync = StepSyncModel(coordinator: coordinator)
  let marimo = GrowingMarimoViewModel(coordinator: coordinator)
  return (sync, marimo)
}

/// Runs one full sync and reflects it into the marimo only when the shared
/// observation key changes, mirroring the `HomeView` wiring.
@MainActor
private func sync(_ models: (sync: StepSyncModel, marimo: GrowingMarimoViewModel)) async {
  let key = models.sync.observationKey
  await models.sync.start()
  guard models.sync.observationKey != key else { return }
  await models.marimo.observe(models.sync.phase)
}

@MainActor
@Test("Renders this month's marimo once a backfill has cached the current month")
func marimoReadyAfterSync() async throws {
  // Arrange: a measured day this month, synced through today.
  let source = FakeStepSource(
    status: .requested,
    stepsToReturn: [DailySteps(day: makeDay(2026, 6, 27), steps: 8_432)],
    earliest: makeDate(2026, 6, 1)
  )
  let models = try makeModel(source: source, today: makeDate(2026, 6, 28))

  // Act
  await sync(models)

  // Assert: the month's total drives the rendered marimo.
  let parameters = try #require(models.marimo.parameters)
  #expect(parameters.totalSteps == 8_432)
}

@MainActor
@Test("Shows the empty state when there is no step data at all")
func marimoEmptyWithoutData() async throws {
  // Arrange: no samples means no coverage was ever established.
  let models = try makeModel(source: FakeStepSource(earliest: nil), today: makeDate(2026, 6, 28))

  // Act
  await sync(models)

  // Assert
  #expect(models.marimo.phase == .empty)
  #expect(models.marimo.parameters == nil)
}

@MainActor
@Test("Reflects backfill progress straight from the shared sync phase")
func marimoReflectsBackfillingPhase() async {
  // Arrange: a coordinator isn't needed — observe maps the shared phase directly.
  let context = try! InMemoryStore.makeContext()
  let store = SwiftDataStepLogStore(
    context: context, calendar: testCalendar, now: { makeDate(2026, 6, 28) })
  let coordinator = StepSyncCoordinator(
    source: FakeStepSource(), stepLogStore: store,
    marimoStore: SwiftDataMarimoStore(context: context),
    calendar: testCalendar, now: { makeDate(2026, 6, 28) })
  let marimo = GrowingMarimoViewModel(coordinator: coordinator)

  // Act
  await marimo.observe(.backfilling(completedDays: 3, totalDays: 10))

  // Assert: the section mirrors the import progress in its own phase.
  #expect(marimo.phase == .backfilling(completedDays: 3, totalDays: 10))
}
