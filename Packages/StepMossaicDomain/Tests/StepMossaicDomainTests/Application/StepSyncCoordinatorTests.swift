import Foundation
import Testing

@testable import StepMossaicDomain

private let calendar = TestCalendar.utc

/// A precise UTC instant, for exercising the local-midnight boundary.
private func instant(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
  calendar.date(
    from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// A clock that hands out each instant in `times` on successive reads (pinning to
/// the last once exhausted) and counts how many times it was read, so a test can
/// detect whether the coordinator reads `now()` more than once per sync.
@MainActor
private final class TickingClock {
  private let times: [Date]
  private(set) var reads = 0

  init(_ times: [Date]) { self.times = times }

  func now() -> Date {
    defer { reads += 1 }
    return times[min(reads, times.count - 1)]
  }
}

@MainActor
private func makeCoordinator(
  source: FakeStepSource,
  store: FakeStepLogStore,
  today: Date,
  chunkSizeInDays: Int = 365
) -> StepSyncCoordinator {
  StepSyncCoordinator(
    source: source,
    stepLogStore: store,
    calendar: calendar,
    now: { today },
    chunkSizeInDays: chunkSizeInDays
  )
}

@MainActor
@Test("First sync backfills from the earliest sample to today in chunks")
func firstSyncBackfillsWholeHistoryInChunks() async throws {
  // Arrange: 41 days of history (Jan 1 .. Feb 10), fetched 10 days at a time.
  let source = FakeStepSource(
    earliest: makeDate(2026, 1, 1),
    stepsByDay: [makeDay(2026, 1, 5): 5_000, makeDay(2026, 2, 10): 8_000]
  )
  let store = FakeStepLogStore()
  let coordinator = makeCoordinator(
    source: source, store: store, today: makeDate(2026, 2, 10), chunkSizeInDays: 10
  )

  // Act
  try await coordinator.sync()

  // Assert: measured days are cached, and the range was fetched as 5 chunks
  // (ceil(41 / 10)) rather than one large request.
  #expect(source.requestedIntervals.count == 5)
  #expect(store.upsertCallCount == 5)
  #expect(
    try store.logs(in: DayInterval(start: makeDay(2026, 1, 1), end: makeDay(2026, 2, 10))).count
      == 2)
  // The anchor advances to today so the next run takes the differential path.
  #expect(try store.anchorState()?.lastSyncedDate == makeDate(2026, 2, 10))
}

@MainActor
@Test("Backfill reports day-based progress reaching completion")
func backfillReportsProgressToCompletion() async throws {
  // Arrange
  let source = FakeStepSource(earliest: makeDate(2026, 1, 1))
  let coordinator = makeCoordinator(
    source: source, store: FakeStepLogStore(), today: makeDate(2026, 1, 10), chunkSizeInDays: 4
  )
  var events: [SyncProgress] = []

  // Act
  try await coordinator.sync { events.append($0) }

  // Assert: progress is denominated in days (10), advances, and ends finished.
  #expect(events.first == .backfilling(completedDays: 0, totalDays: 10))
  #expect(events.contains(.backfilling(completedDays: 10, totalDays: 10)))
  #expect(events.last == .finished)
}

@MainActor
@Test("Backfill is skipped and no anchor saved when there are no samples")
func backfillSkippedWhenNoSamples() async throws {
  // Arrange: HealthKit has no step samples yet.
  let source = FakeStepSource(earliest: nil)
  let store = FakeStepLogStore()
  let coordinator = makeCoordinator(source: source, store: store, today: makeDate(2026, 2, 10))

  // Act
  try await coordinator.sync()

  // Assert: leaving the anchor unset lets a later launch retry the full backfill
  // once data exists, rather than locking into differential sync from today.
  #expect(source.requestedIntervals.isEmpty)
  #expect(try store.anchorState() == nil)
}

@MainActor
@Test("Subsequent sync re-fetches only from the last synced day to today")
func differentialSyncFetchesOnlyRecentWindow() async throws {
  // Arrange: already synced through Feb 1; today is Feb 10.
  let source = FakeStepSource(
    earliest: makeDate(2026, 1, 1),
    stepsByDay: [makeDay(2026, 2, 9): 6_000]
  )
  let store = FakeStepLogStore(anchor: SyncAnchor(lastSyncedDate: makeDate(2026, 2, 1)))
  let coordinator = makeCoordinator(source: source, store: store, today: makeDate(2026, 2, 10))

  // Act
  try await coordinator.sync()

  // Assert: only the Feb 1 .. Feb 10 window is re-read, not the whole history.
  #expect(
    source.requestedIntervals == [
      DayInterval(start: makeDay(2026, 2, 1), end: makeDay(2026, 2, 10))
    ])
  #expect(try store.anchorState()?.lastSyncedDate == makeDate(2026, 2, 10))
}

@MainActor
@Test("Coverage maps the earliest cached day and anchor to the data range")
func coverageMapsCacheAndAnchor() throws {
  // Arrange: a cache holding logs back to Jan 1, synced through Feb 10.
  let store = FakeStepLogStore(
    seedLogs: [DailySteps(day: makeDay(2026, 1, 1), steps: 5_000)],
    anchor: SyncAnchor(lastSyncedDate: makeDate(2026, 2, 10))
  )
  let coordinator = makeCoordinator(
    source: FakeStepSource(), store: store, today: makeDate(2026, 2, 28))

  // Act: no live source query is made; coverage comes from the cache.
  let coverage = try coordinator.coverage()

  // Assert: first available day is the earliest cached day, last synced day comes
  // from the anchor (not today).
  #expect(coverage.firstAvailableDay == makeDay(2026, 1, 1))
  #expect(coverage.lastSyncedDay == makeDay(2026, 2, 10))
}

@MainActor
@Test("Coverage has no first available day when the cache is empty")
func coverageEmptyWhenCacheEmpty() throws {
  // Arrange: nothing synced or stored yet.
  let coordinator = makeCoordinator(
    source: FakeStepSource(), store: FakeStepLogStore(), today: makeDate(2026, 2, 10)
  )

  // Act
  let coverage = try coordinator.coverage()

  // Assert: no coverage; last synced day falls back to today before any sync.
  #expect(coverage.firstAvailableDay == nil)
  #expect(coverage.lastSyncedDay == makeDay(2026, 2, 10))
}

@MainActor
@Test("Backfill crossing midnight pins the fetched range end and anchor to one day")
func backfillPinsClockAcrossMidnight() async throws {
  // Arrange: a clock that rolls to the next day on its second read. If the
  // coordinator read it twice — once for the range end, once for the anchor — the
  // run straddling midnight would record Feb 11 for one and Feb 10 for the other.
  let clock = TickingClock([instant(2026, 2, 10, 23, 59), instant(2026, 2, 11, 0, 0)])
  let source = FakeStepSource(earliest: makeDate(2026, 1, 1))
  let store = FakeStepLogStore()
  let coordinator = StepSyncCoordinator(
    source: source, stepLogStore: store, calendar: calendar, now: clock.now)

  // Act
  try await coordinator.sync()

  // Assert: the clock is read exactly once, so the fetched range end and the saved
  // anchor agree on Feb 10 despite the midnight crossing.
  #expect(clock.reads == 1)
  #expect(source.requestedIntervals.last?.end == makeDay(2026, 2, 10))
  #expect(try store.anchorState()?.lastSyncedDate == instant(2026, 2, 10, 23, 59))
}

@MainActor
@Test("Differential sync crossing midnight pins the fetched range end and anchor to one day")
func differentialSyncPinsClockAcrossMidnight() async throws {
  // Arrange: already synced through Feb 1; the clock rolls past midnight mid-run.
  let clock = TickingClock([instant(2026, 2, 10, 23, 59), instant(2026, 2, 11, 0, 0)])
  let source = FakeStepSource(earliest: makeDate(2026, 1, 1))
  let store = FakeStepLogStore(anchor: SyncAnchor(lastSyncedDate: makeDate(2026, 2, 1)))
  let coordinator = StepSyncCoordinator(
    source: source, stepLogStore: store, calendar: calendar, now: clock.now)

  // Act
  try await coordinator.sync()

  // Assert: a single clock read keeps the window end and the anchor on Feb 10.
  #expect(clock.reads == 1)
  #expect(
    source.requestedIntervals == [
      DayInterval(start: makeDay(2026, 2, 1), end: makeDay(2026, 2, 10))
    ])
  #expect(try store.anchorState()?.lastSyncedDate == instant(2026, 2, 10, 23, 59))
}

// MARK: - Growing marimo

@MainActor
@Test("The growing marimo aggregates the current month's cached days up to today")
func growingMarimoAggregatesThisMonth() throws {
  // Arrange: June 1 and June 10 measured, synced through today (June 15).
  let store = FakeStepLogStore(
    seedLogs: [
      DailySteps(day: makeDay(2026, 6, 1), steps: 6_000),
      DailySteps(day: makeDay(2026, 6, 10), steps: 9_000),
    ],
    anchor: SyncAnchor(lastSyncedDate: makeDate(2026, 6, 15))
  )
  let coordinator = makeCoordinator(
    source: FakeStepSource(), store: store, today: makeDate(2026, 6, 15))

  // Act
  let marimo = try coordinator.growingMarimo()

  // Assert: the month's total drives the marimo and the size is past the floor.
  let parameters = try #require(marimo)
  #expect(parameters.totalSteps == 15_000)
  #expect(parameters.sizeUnit > 0)
}

@MainActor
@Test("The growing marimo is nil when no step data has ever existed")
func growingMarimoNilWithoutData() throws {
  // Arrange: an empty cache has no coverage, so the month has no available day.
  let coordinator = makeCoordinator(
    source: FakeStepSource(), store: FakeStepLogStore(), today: makeDate(2026, 6, 15))

  // Act & Assert
  #expect(try coordinator.growingMarimo() == nil)
}

@MainActor
@Test("The growing marimo excludes days after today within the month")
func growingMarimoExcludesFutureDays() throws {
  // Arrange: a stray log dated past the sync anchor (June 20) must not count while
  // today is June 15.
  let store = FakeStepLogStore(
    seedLogs: [
      DailySteps(day: makeDay(2026, 6, 1), steps: 6_000),
      DailySteps(day: makeDay(2026, 6, 20), steps: 9_999),
    ],
    anchor: SyncAnchor(lastSyncedDate: makeDate(2026, 6, 15))
  )
  let coordinator = makeCoordinator(
    source: FakeStepSource(), store: store, today: makeDate(2026, 6, 15))

  // Act
  let parameters = try #require(try coordinator.growingMarimo())

  // Assert: only the in-range day counts; the future day is outside coverage.
  #expect(parameters.totalSteps == 6_000)
}

@MainActor
@Test("The growing marimo pins the rendered month and today to one clock read")
func growingMarimoPinsClockAcrossMonthBoundary() throws {
  // Arrange: the clock moves from June to July after the render instant is read.
  // Reading month and today separately would make the generator inputs describe
  // two different render instants.
  let clock = TickingClock([instant(2026, 6, 30, 23, 59), instant(2026, 7, 1, 0, 0)])
  let store = FakeStepLogStore(
    seedLogs: [
      DailySteps(day: makeDay(2026, 6, 1), steps: 6_000),
      DailySteps(day: makeDay(2026, 6, 30), steps: 9_999),
      DailySteps(day: makeDay(2026, 7, 1), steps: 7_777),
    ],
    anchor: SyncAnchor(lastSyncedDate: makeDate(2026, 7, 1))
  )
  let coordinator = StepSyncCoordinator(
    source: FakeStepSource(), stepLogStore: store, calendar: calendar, now: clock.now)

  // Act
  let parameters = try #require(try coordinator.growingMarimo())

  // Assert: the June render uses June 30 as today, not the next clock tick.
  #expect(clock.reads == 1)
  #expect(parameters.totalSteps == 15_999)
}
