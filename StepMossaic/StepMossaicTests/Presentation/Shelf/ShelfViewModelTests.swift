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

@MainActor
private func makeModel(seed: [FrozenMarimo]) throws -> ShelfViewModel {
  let store = SwiftDataMarimoStore(context: try InMemoryStore.makeContext())
  for marimo in seed { try store.save(marimo) }
  return ShelfViewModel(marimoStore: store)
}

@MainActor
@Test("Presents frozen months newest first once sync settles ready")
func shelfPresentsNewestFirst() async throws {
  // Arrange: three frozen months saved out of order, across a year boundary.
  let model = try makeModel(seed: [
    makeMarimo(2026, 1),
    makeMarimo(2025, 12),
    makeMarimo(2026, 3),
  ])

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
  let model = try makeModel(seed: [])

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
  let model = try makeModel(seed: [makeMarimo(2026, 3)])

  // Act: the shelf has no per-section progress, so backfilling reads as loading.
  await model.observe(.backfilling(completedDays: 2, totalDays: 10))

  // Assert
  #expect(model.phase == .loading)
}

@MainActor
@Test("A later sync completion re-reads newly frozen months")
func shelfRefreshesOnResync() async throws {
  // Arrange: settle once with a single month.
  let store = SwiftDataMarimoStore(context: try InMemoryStore.makeContext())
  try store.save(makeMarimo(2026, 3))
  let model = ShelfViewModel(marimoStore: store)
  await model.observe(.ready)
  #expect(model.marimos.count == 1)

  // A month rolls over and the sync's reconciliation freezes another month.
  try store.save(makeMarimo(2026, 4))

  // Act: the next settled sync re-reads the store.
  await model.observe(.ready)

  // Assert: the newly frozen month is now on the shelf, still newest first.
  #expect(
    model.marimos.map(\.yearMonth) == [
      YearMonth(year: 2026, month: 4),
      YearMonth(year: 2026, month: 3),
    ])
}
