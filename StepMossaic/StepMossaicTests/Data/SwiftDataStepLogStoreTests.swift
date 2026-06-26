import Foundation
import StepMossaicDomain
import Testing

@testable import StepMossaic

@MainActor
private func makeStore() throws -> SwiftDataStepLogStore {
  SwiftDataStepLogStore(context: try InMemoryStore.makeContext(), calendar: testCalendar)
}

@MainActor
@Test("Inserts new days and updates an existing day in place")
func stepLogStoreUpsertsByDate() throws {
  // Arrange
  let store = try makeStore()
  let day = makeDay(2026, 6, 1)
  try store.upsert([DailySteps(day: day, steps: 1000)])

  // Act: a second upsert for the same day must overwrite, not duplicate.
  try store.upsert([DailySteps(day: day, steps: 2500)])

  // Assert
  let logs = try store.logs(in: DayInterval(start: day, end: day))
  #expect(logs.count == 1)
  #expect(logs.first?.steps == 2500)
}

@MainActor
@Test("Returns logs within the interval, inclusive of both bounds, sorted ascending")
func stepLogStoreFetchesInclusiveRangeSorted() throws {
  // Arrange: insert out of order to prove the store sorts.
  let store = try makeStore()
  try store.upsert([
    DailySteps(day: makeDay(2026, 6, 3), steps: 300),
    DailySteps(day: makeDay(2026, 6, 1), steps: 100),
    DailySteps(day: makeDay(2026, 6, 5), steps: 500),
  ])

  // Act: bounds land exactly on stored days, proving both ends are inclusive.
  let logs = try store.logs(
    in: DayInterval(start: makeDay(2026, 6, 1), end: makeDay(2026, 6, 3))
  )

  // Assert
  #expect(logs.map(\.steps) == [100, 300])
}

@MainActor
@Test("Anchor round-trips and is absent before any save")
func stepLogStoreAnchorRoundTrips() throws {
  // Arrange
  let store = try makeStore()

  // Act & Assert: no anchor yet.
  #expect(try store.anchorState() == nil)

  // Act: saving twice must keep a single row updated in place.
  let payload = Data([0x01, 0x02])
  try store.saveAnchor(SyncAnchor(anchorData: payload, lastSyncedDate: makeDate(2026, 6, 1)))
  try store.saveAnchor(SyncAnchor(anchorData: payload, lastSyncedDate: makeDate(2026, 6, 2)))

  // Assert
  let anchor = try store.anchorState()
  #expect(anchor?.anchorData == payload)
  #expect(anchor?.lastSyncedDate == makeDate(2026, 6, 2))
}

@MainActor
@Test("Reset clears cached logs and the anchor")
func stepLogStoreResetClearsEverything() throws {
  // Arrange
  let store = try makeStore()
  try store.upsert([DailySteps(day: makeDay(2026, 6, 1), steps: 100)])
  try store.saveAnchor(SyncAnchor(anchorData: Data([0x01]), lastSyncedDate: makeDate(2026, 6, 1)))

  // Act
  try store.reset()

  // Assert
  let logs = try store.logs(
    in: DayInterval(start: makeDay(2026, 1, 1), end: makeDay(2026, 12, 31))
  )
  #expect(logs.isEmpty)
  #expect(try store.anchorState() == nil)
}
