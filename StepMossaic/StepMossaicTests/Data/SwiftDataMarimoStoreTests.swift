import Foundation
import StepMossaicDomain
import Testing

@testable import StepMossaic

@MainActor
private func makeMarimo(_ year: Int, _ month: Int, colorLevel: Double, locked: Bool) -> FrozenMarimo
{
  FrozenMarimo(
    yearMonth: YearMonth(year: year, month: month),
    sizeUnit: 0.5,
    colorLevel: colorLevel,
    bumpiness: 0.3,
    seed: 42,
    totalSteps: 100_000,
    frozenAt: makeDate(year, month, 1),
    isLocked: locked
  )
}

@MainActor
@Test("Fetches a saved month and returns nil for an unknown month")
func marimoStoreFetchesByMonth() throws {
  // Arrange
  let store = SwiftDataMarimoStore(context: try InMemoryStore.makeContext())
  try store.save(makeMarimo(2026, 5, colorLevel: 2.0, locked: true))

  // Act & Assert
  #expect(try store.frozenMarimo(for: YearMonth(year: 2026, month: 5))?.colorLevel == 2.0)
  #expect(try store.frozenMarimo(for: YearMonth(year: 2026, month: 4)) == nil)
}

@MainActor
@Test("Saving the same month again overwrites its parameters in place")
func marimoStoreUpsertsByMonth() throws {
  // Arrange
  let store = SwiftDataMarimoStore(context: try InMemoryStore.makeContext())
  try store.save(makeMarimo(2026, 5, colorLevel: 1.0, locked: false))

  // Act: a regenerated month during its grace period replaces the snapshot.
  try store.save(makeMarimo(2026, 5, colorLevel: 3.0, locked: true))

  // Assert
  let all = try store.allFrozen()
  #expect(all.count == 1)
  #expect(all.first?.colorLevel == 3.0)
  #expect(all.first?.isLocked == true)
}

@MainActor
@Test("allFrozen returns months in chronological order")
func marimoStoreSortsChronologically() throws {
  // Arrange: insert across a year boundary out of order.
  let store = SwiftDataMarimoStore(context: try InMemoryStore.makeContext())
  try store.save(makeMarimo(2026, 1, colorLevel: 1.0, locked: true))
  try store.save(makeMarimo(2025, 12, colorLevel: 2.0, locked: true))
  try store.save(makeMarimo(2026, 3, colorLevel: 3.0, locked: true))

  // Act
  let months = try store.allFrozen().map(\.yearMonth)

  // Assert: zero-padded keys make lexical order match chronological order.
  #expect(
    months == [
      YearMonth(year: 2025, month: 12),
      YearMonth(year: 2026, month: 1),
      YearMonth(year: 2026, month: 3),
    ])
}

@MainActor
@Test("Reset deletes every frozen marimo, including locked months")
func marimoStoreResetClearsEverything() throws {
  // Arrange: a locked month must be removed too, proving reset ignores the lock.
  let store = SwiftDataMarimoStore(context: try InMemoryStore.makeContext())
  try store.save(makeMarimo(2026, 1, colorLevel: 1.0, locked: true))
  try store.save(makeMarimo(2026, 2, colorLevel: 2.0, locked: false))

  // Act
  try store.reset()

  // Assert
  #expect(try store.allFrozen().isEmpty)
}
