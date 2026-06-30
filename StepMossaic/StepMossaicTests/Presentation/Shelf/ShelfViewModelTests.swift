import Foundation
import StepMossaicDomain
import Testing

@testable import StepMossaic

@MainActor
private func makeMarimo(_ year: Int, _ month: Int, locked: Bool = true) -> FrozenMarimo {
  FrozenMarimo(
    yearMonth: YearMonth(year: year, month: month),
    sizeUnit: 0.5,
    colorLevel: 2,
    bumpiness: 0.3,
    seed: UInt64(year * 100 + month),
    totalSteps: 120_000,
    frozenAt: makeDate(year, month, 1),
    isLocked: locked
  )
}

/// Wires a shelf view model over one in-memory context shared by the frozen-marimo
/// store, the daily-log cache, and the coordinator, and returns the marimo store so
/// a test can freeze another month mid-run.
@MainActor
private func makeHarness(
  frozen: [FrozenMarimo] = [],
  logs: [DailySteps] = [],
  anchor: SyncAnchor? = nil,
  today: Date = makeDate(2026, 6, 15)
) throws -> (model: ShelfViewModel, marimoStore: SwiftDataMarimoStore) {
  let context = try InMemoryStore.makeContext()
  let stepLogStore = SwiftDataStepLogStore(context: context, calendar: testCalendar, now: { today })
  if !logs.isEmpty { try stepLogStore.upsert(logs) }
  if let anchor { try stepLogStore.saveAnchor(anchor) }

  let marimoStore = SwiftDataMarimoStore(context: context)
  for marimo in frozen { try marimoStore.save(marimo) }

  let coordinator = StepSyncCoordinator(
    source: FakeStepSource(), stepLogStore: stepLogStore, marimoStore: marimoStore,
    calendar: testCalendar, now: { today })
  let model = ShelfViewModel(
    marimoStore: marimoStore, stepLogStore: stepLogStore, coordinator: coordinator,
    calendar: testCalendar)
  return (model, marimoStore)
}

@MainActor
@Test("Presents frozen months newest first once sync settles ready")
func shelfPresentsNewestFirst() async throws {
  // Arrange: three frozen months saved out of order, across a year boundary.
  let model = try makeHarness(frozen: [
    makeMarimo(2026, 1),
    makeMarimo(2025, 12),
    makeMarimo(2026, 3),
  ]).model

  // Act
  await model.observe(.ready)

  // Assert: the shelf leads with the most recent month.
  #expect(
    model.marimos.map(\.yearMonth) == [
      YearMonth(year: 2026, month: 3),
      YearMonth(year: 2026, month: 1),
      YearMonth(year: 2025, month: 12),
    ])
}

@MainActor
@Test("Shows empty when no month has been frozen yet")
func shelfEmptyWithoutFrozenMonths() async throws {
  // Arrange: data exists (sync is ready) but only the current month has logs, so
  // nothing is frozen.
  let model = try makeHarness().model

  // Act
  await model.observe(.ready)

  // Assert: a ready-but-monument-less cache reads as empty, not a ready shelf.
  #expect(model.phase == .empty)
  #expect(model.marimos.isEmpty)
}

@MainActor
@Test("An in-flight backfill keeps the shelf on its loading state")
func shelfLoadingDuringBackfill() async throws {
  // Arrange
  let model = try makeHarness(frozen: [makeMarimo(2026, 3)]).model

  // Act: the shelf has no per-section progress, so backfilling reads as loading.
  await model.observe(.backfilling(completedDays: 2, totalDays: 10))

  // Assert
  #expect(model.phase == .loading)
}

@MainActor
@Test("A later sync completion re-reads newly frozen months")
func shelfRefreshesOnResync() async throws {
  // Arrange: settle once with a single month.
  let harness = try makeHarness(frozen: [makeMarimo(2026, 3)])
  await harness.model.observe(.ready)
  #expect(harness.model.marimos.count == 1)

  // A month rolls over and the sync's reconciliation freezes another month.
  try harness.marimoStore.save(makeMarimo(2026, 4))

  // Act: the next settled sync re-reads the store.
  await harness.model.observe(.ready)

  // Assert: the newly frozen month is now on the shelf, still newest first.
  #expect(
    harness.model.marimos.map(\.yearMonth) == [
      YearMonth(year: 2026, month: 4),
      YearMonth(year: 2026, month: 3),
    ])
}

@MainActor
@Test("Month detail aggregates the tapped month from the cache")
func monthDetailAggregatesMonth() throws {
  // Arrange: April measured (two days), synced through June, with April frozen.
  let model = try makeHarness(
    frozen: [makeMarimo(2026, 4)],
    logs: [
      DailySteps(day: makeDay(2026, 4, 5), steps: 5_000),
      DailySteps(day: makeDay(2026, 4, 12), steps: 6_000),
    ],
    anchor: SyncAnchor(lastSyncedDate: makeDate(2026, 6, 15))
  ).model

  // Act
  let detail = try #require(model.monthDetail(for: YearMonth(year: 2026, month: 4)))

  // Assert: the total sums April's covered days, and the layout is ready to draw.
  #expect(detail.totalSteps == 11_000)
  #expect(!detail.weeks.isEmpty)
  #expect(detail.referenceColumnCount > 0)
  #expect(detail.orderedWeekdaySymbols.count == 7)
}
