import Foundation
import StepMossaicDomain
import Testing

@testable import StepMossaic

/// Wires a heatmap view model to an in-memory cache and a fake source, with a
/// fixed clock so the display range and coverage are deterministic.
///
/// The heatmap no longer owns the sync, so the harness also returns the shared
/// `StepSyncModel`: tests drive the sync through it, exactly as `HomeView` does.
@MainActor
private func makeModel(
  source: FakeStepSource,
  today: Date
) throws -> (sync: StepSyncModel, heatmap: HeatmapViewModel) {
  let context = try InMemoryStore.makeContext()
  let store = SwiftDataStepLogStore(context: context, calendar: testCalendar, now: { today })
  let coordinator = StepSyncCoordinator(
    source: source, stepLogStore: store, marimoStore: SwiftDataMarimoStore(context: context),
    calendar: testCalendar, now: { today })
  let sync = StepSyncModel(coordinator: coordinator)
  let heatmap = HeatmapViewModel(
    coordinator: coordinator, stepLogStore: store, calendar: testCalendar, today: { today })
  return (sync, heatmap)
}

/// Runs one full sync and reflects it only when the `HomeView` observation key
/// changes, so same-phase differential completions must still publish refreshes.
@MainActor
private func sync(_ models: (sync: StepSyncModel, heatmap: HeatmapViewModel)) async {
  let key = models.sync.observationKey
  await models.sync.start()
  guard models.sync.observationKey != key else { return }
  await models.heatmap.observe(models.sync.phase)
}

private func state(_ heatmap: StepHeatmap, _ day: Day) -> StepHeatmapCellState? {
  heatmap.cells.first { $0.day == day }?.state
}

@MainActor
@Test("Backfills then renders the stored days as an aggregated heatmap")
func heatmapReadyAfterSync() async throws {
  // Arrange: a single measured day (June 27), synced through today (June 28).
  let source = FakeStepSource(
    status: .requested,
    stepsToReturn: [DailySteps(day: makeDay(2026, 6, 27), steps: 8_432)],
    earliest: makeDate(2026, 6, 1)
  )
  let models = try makeModel(source: source, today: makeDate(2026, 6, 28))

  // Act
  await sync(models)

  // Assert: the measured day is an available, positive cell and drives the total.
  let heatmap = try #require(models.heatmap.heatmap)
  #expect(
    state(heatmap, makeDay(2026, 6, 27)) == .available(steps: 8_432, level: StepLevel(rawValue: 1)))
  #expect(heatmap.totalSteps == 8_432)
  // Today has no entry but is within coverage, so it is an available 0-step day.
  #expect(state(heatmap, makeDay(2026, 6, 28)) == .available(steps: 0, level: .empty))
  // A day before the earliest cached day is unavailable (no data), not 0 steps.
  #expect(state(heatmap, makeDay(2026, 6, 20)) == .unavailable)
}

@MainActor
@Test("Shows the empty state when there is no step data at all")
func heatmapEmptyWithoutData() async throws {
  // Arrange: no samples means no coverage was ever established.
  let models = try makeModel(source: FakeStepSource(earliest: nil), today: makeDate(2026, 6, 28))

  // Act
  await sync(models)

  // Assert: both the shared owner and the section settle on empty.
  #expect(models.sync.phase == .empty)
  #expect(models.heatmap.phase == .empty)
  #expect(models.heatmap.heatmap == nil)
}

@MainActor
@Test("Switching the range re-renders over the new interval without re-syncing")
func heatmapRangeSwitchReloads() async throws {
  // Arrange
  let source = FakeStepSource(
    status: .requested,
    stepsToReturn: [DailySteps(day: makeDay(2026, 6, 27), steps: 8_432)],
    earliest: makeDate(2026, 6, 1)
  )
  let today = makeDate(2026, 6, 28)
  let models = try makeModel(source: source, today: today)
  await sync(models)

  // Act
  await models.heatmap.selectRange(.year)

  // Assert: the displayed interval matches the year range; the data still renders.
  #expect(models.heatmap.range == .year)
  #expect(
    models.heatmap.heatmap?.interval
      == HeatmapRange.year.interval(endingAt: makeDay(2026, 6, 28), calendar: testCalendar))
  #expect(models.heatmap.heatmap?.totalSteps == 8_432)
}

@MainActor
@Test("Differential sync refreshes the heatmap even when the shared phase stays ready")
func heatmapRefreshesAfterSamePhaseDifferentialSync() async throws {
  // Arrange: the first sync establishes ready; the second updates the same cached day.
  let source = FakeStepSource(
    status: .requested,
    stepsToReturn: [DailySteps(day: makeDay(2026, 6, 27), steps: 8_432)],
    earliest: makeDate(2026, 6, 1)
  )
  let models = try makeModel(source: source, today: makeDate(2026, 6, 28))
  await sync(models)

  // Act
  source.stepsToReturn = [DailySteps(day: makeDay(2026, 6, 27), steps: 9_001)]
  await sync(models)

  // Assert: phase remains ready, but the section still re-read the cache.
  #expect(models.sync.phase == .ready)
  #expect(models.heatmap.heatmap?.totalSteps == 9_001)
}
