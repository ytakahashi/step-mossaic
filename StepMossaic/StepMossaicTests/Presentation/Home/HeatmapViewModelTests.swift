import Foundation
import StepMossaicDomain
import Testing

@testable import StepMossaic

/// Wires a heatmap view model to an in-memory cache and a fake source, with a
/// fixed clock so the display range and coverage are deterministic.
@MainActor
private func makeModel(
  source: FakeStepSource,
  today: Date
) throws -> HeatmapViewModel {
  let store = SwiftDataStepLogStore(
    context: try InMemoryStore.makeContext(), calendar: testCalendar, now: { today })
  let coordinator = StepSyncCoordinator(
    source: source, stepLogStore: store, calendar: testCalendar, now: { today })
  return HeatmapViewModel(
    coordinator: coordinator, stepLogStore: store, calendar: testCalendar, today: { today })
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
  let model = try makeModel(source: source, today: makeDate(2026, 6, 28))

  // Act
  await model.start()

  // Assert: the measured day is an available, positive cell and drives the total.
  let heatmap = try #require(model.heatmap)
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
  let model = try makeModel(source: FakeStepSource(earliest: nil), today: makeDate(2026, 6, 28))

  // Act
  await model.start()

  // Assert
  #expect(model.phase == .empty)
  #expect(model.heatmap == nil)
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
  let model = try makeModel(source: source, today: today)
  await model.start()

  // Act
  await model.selectRange(.year)

  // Assert: the displayed interval matches the year range; the data still renders.
  #expect(model.range == .year)
  #expect(
    model.heatmap?.interval
      == HeatmapRange.year.interval(endingAt: makeDay(2026, 6, 28), calendar: testCalendar))
  #expect(model.heatmap?.totalSteps == 8_432)
}
