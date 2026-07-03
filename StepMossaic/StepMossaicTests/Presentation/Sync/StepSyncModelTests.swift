import Foundation
import StepMossaicDomain
import Testing

@testable import StepMossaic

/// Wires a sync model to an in-memory cache and a fake source with a fixed clock,
/// so coverage and the settled phase are deterministic.
@MainActor
private func makeModel(
  source: any StepSource,
  today: Date
) throws -> StepSyncModel {
  let context = try InMemoryStore.makeContext()
  let store = SwiftDataStepLogStore(context: context, calendar: testCalendar, now: { today })
  let marimoStore = SwiftDataMarimoStore(context: context)
  let coordinator = StepSyncCoordinator(
    source: source, stepLogStore: store, marimoStore: marimoStore, calendar: testCalendar,
    now: { today })
  return StepSyncModel(coordinator: coordinator)
}

/// Step source that pauses the earliest-sample query so tests can overlap two
/// `start()` calls at the sync boundary instead of only running them sequentially.
private final class PausingStepSource: StepSource, @unchecked Sendable {
  var status: HealthAuthorizationStatus = .requested
  var stepsToReturn: [DailySteps]
  private var earliestResults: [Date?]
  private(set) var earliestRequestCount = 0

  private var earliestContinuation: CheckedContinuation<Date?, Never>?
  private var waitContinuation: CheckedContinuation<Void, Never>?

  init(earliestResults: [Date?], stepsToReturn: [DailySteps]) {
    self.earliestResults = earliestResults
    self.stepsToReturn = stepsToReturn
  }

  func authorizationStatus() -> HealthAuthorizationStatus { status }

  func requestAuthorization() async throws {}

  func earliestSampleDate() async throws -> Date? {
    earliestRequestCount += 1
    waitContinuation?.resume()
    waitContinuation = nil

    return await withCheckedContinuation { continuation in
      earliestContinuation = continuation
    }
  }

  func dailySteps(in interval: DayInterval) async throws -> [DailySteps] { stepsToReturn }

  func observeTodayUpdates() -> AsyncStream<Void> {
    AsyncStream { $0.finish() }
  }

  func waitForEarliestRequest() async {
    guard earliestContinuation == nil else { return }
    await withCheckedContinuation { continuation in
      waitContinuation = continuation
    }
  }

  func releaseEarliestRequest() {
    let result = earliestResults.removeFirst()
    let continuation = earliestContinuation
    earliestContinuation = nil
    continuation?.resume(returning: result)
  }
}

/// Step source that pauses its first `dailySteps(in:)` call so a test can force
/// a rebuild request to land while a sync is already reading from the source.
/// Unlike `PausingStepSource` (which pauses `earliestSampleDate()`, only ever
/// called on the full-backfill path), this pauses the call every sync path makes,
/// so it can catch an in-flight *differential* sync mid-read too. Later calls
/// return immediately. `dailySteps` filters a fixed full history by the
/// requested interval, so a differential window and a post-rebuild full backfill
/// each see the historically-correct slice rather than a single canned answer.
private final class PausingDailyStepsSource: StepSource, @unchecked Sendable {
  var status: HealthAuthorizationStatus = .requested
  private let earliest: Date?
  private let allDays: [DailySteps]
  private(set) var dailyStepsRequestCount = 0

  private var didPauseOnce = false
  private var pausedContinuation: CheckedContinuation<Void, Never>?
  private var waitContinuation: CheckedContinuation<Void, Never>?

  init(earliest: Date?, allDays: [DailySteps]) {
    self.earliest = earliest
    self.allDays = allDays
  }

  func authorizationStatus() -> HealthAuthorizationStatus { status }

  func requestAuthorization() async throws {}

  func earliestSampleDate() async throws -> Date? { earliest }

  func dailySteps(in interval: DayInterval) async throws -> [DailySteps] {
    dailyStepsRequestCount += 1
    if !didPauseOnce {
      didPauseOnce = true
      waitContinuation?.resume()
      waitContinuation = nil
      await withCheckedContinuation { continuation in
        pausedContinuation = continuation
      }
    }
    return allDays.filter { interval.contains($0.day) }
  }

  func observeTodayUpdates() -> AsyncStream<Void> {
    AsyncStream { $0.finish() }
  }

  func waitForFirstDailyStepsRequest() async {
    guard pausedContinuation == nil else { return }
    await withCheckedContinuation { continuation in
      waitContinuation = continuation
    }
  }

  func releaseFirstDailyStepsRequest() {
    let continuation = pausedContinuation
    pausedContinuation = nil
    continuation?.resume()
  }
}

@MainActor
@Test("Settles on ready once a backfill has cached at least one day")
func syncSettlesReadyWithData() async throws {
  // Arrange: one measured day with an earliest sample, so a backfill has data.
  let source = FakeStepSource(
    status: .requested,
    stepsToReturn: [DailySteps(day: makeDay(2026, 6, 27), steps: 8_432)],
    earliest: makeDate(2026, 6, 1)
  )
  let model = try makeModel(source: source, today: makeDate(2026, 6, 28))

  // Act
  await model.start()

  // Assert
  #expect(model.phase == .ready)
}

@MainActor
@Test("A settled sync freezes completed past months into the marimo store")
func syncFreezesPastMonths() async throws {
  // Arrange: April..June history, so April and May are completed past months while
  // June is still the growing (current) month. Share one context so the frozen
  // store reads the same cache the sync just filled.
  let context = try InMemoryStore.makeContext()
  let today = makeDate(2026, 6, 15)
  let stepLogStore = SwiftDataStepLogStore(context: context, calendar: testCalendar, now: { today })
  let marimoStore = SwiftDataMarimoStore(context: context)
  let coordinator = StepSyncCoordinator(
    source: FakeStepSource(
      status: .requested,
      stepsToReturn: [
        DailySteps(day: makeDay(2026, 4, 5), steps: 5_000),
        DailySteps(day: makeDay(2026, 5, 10), steps: 6_000),
        DailySteps(day: makeDay(2026, 6, 3), steps: 7_000),
      ],
      earliest: makeDate(2026, 4, 1)
    ),
    stepLogStore: stepLogStore,
    marimoStore: marimoStore,
    calendar: testCalendar,
    now: { today }
  )
  let model = StepSyncModel(coordinator: coordinator)

  // Act
  await model.start()

  // Assert: the settled sync reconciled the shelf's past months, excluding June.
  #expect(model.phase == .ready)
  #expect(
    try marimoStore.allFrozen().map(\.yearMonth) == [
      YearMonth(year: 2026, month: 4),
      YearMonth(year: 2026, month: 5),
    ])
}

@MainActor
@Test("Settles on empty when no samples were ever available")
func syncSettlesEmptyWithoutData() async throws {
  // Arrange: no earliest sample means a backfill establishes no coverage.
  let model = try makeModel(source: FakeStepSource(earliest: nil), today: makeDate(2026, 6, 28))

  // Act
  await model.start()

  // Assert: a settled-but-empty cache reads as empty, not ready.
  #expect(model.phase == .empty)
}

@MainActor
@Test("A second sync re-runs the differential path without flashing back to loading")
func syncReRunStaysReady() async throws {
  // Arrange: first sync settles on ready.
  let source = FakeStepSource(
    status: .requested,
    stepsToReturn: [DailySteps(day: makeDay(2026, 6, 27), steps: 8_432)],
    earliest: makeDate(2026, 6, 1)
  )
  let model = try makeModel(source: source, today: makeDate(2026, 6, 28))
  await model.start()

  // Act: a later appearance re-syncs against the existing anchor.
  await model.start()

  // Assert: the re-sync keeps ready rather than reverting to loading. The
  // differential path never reports backfill progress, so no flash occurs.
  #expect(model.phase == .ready)
  #expect(model.completedSyncCount == 2)
}

@MainActor
@Test("A live tick runs a differential sync and bumps the observation key")
func liveTickRunsDifferentialSync() async throws {
  // Arrange: settle on ready, then arm one live tick.
  let source = FakeStepSource(
    status: .requested,
    stepsToReturn: [DailySteps(day: makeDay(2026, 6, 27), steps: 8_432)],
    earliest: makeDate(2026, 6, 1),
    liveTickCount: 1
  )
  let model = try makeModel(source: source, today: makeDate(2026, 6, 28))
  await model.start()
  #expect(model.completedSyncCount == 1)

  // Act: the finite tick stream drains one tick, so this returns once its sync ran.
  await model.observeLiveUpdates()

  // Assert: the tick drove a differential sync that bumped the observation key
  // (so the cache-backed sections re-render) without leaving ready.
  #expect(model.phase == .ready)
  #expect(model.completedSyncCount == 2)
}

@MainActor
@Test("A live tick promotes an empty cache to ready once samples appear")
func liveTickPromotesEmptyToReady() async throws {
  // Arrange: the first sync finds no samples and settles empty (no anchor saved).
  let source = FakeStepSource(status: .requested, earliest: nil)
  let model = try makeModel(source: source, today: makeDate(2026, 6, 28))
  await model.start()
  #expect(model.phase == .empty)

  // The user starts accruing steps mid-session; the next tick should pick them up.
  source.earliest = makeDate(2026, 6, 28)
  source.stepsToReturn = [DailySteps(day: makeDay(2026, 6, 28), steps: 1_200)]
  source.liveTickCount = 1

  // Act
  await model.observeLiveUpdates()

  // Assert: the tick re-ran the backfill path and promoted the section to ready.
  #expect(model.phase == .ready)
}

@MainActor
@Test("Rapid live ticks are coalesced into one pending follow-up sync")
func rapidLiveTicksCoalesce() async throws {
  // Arrange: settle on ready, then emit a burst before the observer can need each
  // individual tick. The cache is re-read, so only one pending signal matters.
  let source = FakeStepSource(
    status: .requested,
    stepsToReturn: [DailySteps(day: makeDay(2026, 6, 27), steps: 8_432)],
    earliest: makeDate(2026, 6, 1),
    liveTickCount: 3
  )
  let model = try makeModel(source: source, today: makeDate(2026, 6, 28))
  await model.start()

  // Act
  await model.observeLiveUpdates()

  // Assert: the burst can cause the current refresh plus one pending follow-up,
  // but it does not replay every stale tick as its own sync.
  #expect(model.phase == .ready)
  #expect(model.completedSyncCount == 3)
}

@MainActor
@Test("Rebuild clears the cache and redrives a full backfill back to ready")
func rebuildRedrivesFullBackfill() async throws {
  // Arrange: settle on ready with a past month frozen, so there's something for
  // the rebuild to actually wipe.
  let context = try InMemoryStore.makeContext()
  let today = makeDate(2026, 6, 28)
  let stepLogStore = SwiftDataStepLogStore(context: context, calendar: testCalendar, now: { today })
  let marimoStore = SwiftDataMarimoStore(context: context)
  let source = FakeStepSource(
    status: .requested,
    stepsToReturn: [
      DailySteps(day: makeDay(2026, 5, 10), steps: 6_000),
      DailySteps(day: makeDay(2026, 6, 27), steps: 8_432),
    ],
    earliest: makeDate(2026, 5, 1)
  )
  let coordinator = StepSyncCoordinator(
    source: source, stepLogStore: stepLogStore, marimoStore: marimoStore, calendar: testCalendar,
    now: { today })
  let model = StepSyncModel(coordinator: coordinator)
  await model.start()
  #expect(model.phase == .ready)
  #expect(try marimoStore.allFrozen().isEmpty == false)

  // Act
  await model.rebuild()

  // Assert: the wipe-then-resync round trip lands back on ready with the same
  // source data and the frozen month reconciled again, not left empty.
  #expect(model.phase == .ready)
  #expect(try marimoStore.allFrozen().map(\.yearMonth) == [YearMonth(year: 2026, month: 5)])
  #expect(
    try stepLogStore.logs(in: DayInterval(start: makeDay(2026, 5, 1), end: makeDay(2026, 6, 28)))
      .count == 2)
}

@MainActor
@Test("Rebuild on an empty cache settles back on empty rather than ready")
func rebuildOnEmptyCacheStaysEmpty() async throws {
  // Arrange: the first sync finds no samples and settles empty.
  let model = try makeModel(source: FakeStepSource(earliest: nil), today: makeDate(2026, 6, 28))
  await model.start()
  #expect(model.phase == .empty)

  // Act
  await model.rebuild()

  // Assert: rebuilding an already-empty cache is a harmless no-op.
  #expect(model.phase == .empty)
}

@MainActor
@Test("A rebuild requested during an in-flight differential sync still ends up a full backfill")
func rebuildDuringInFlightDifferentialSyncStillFullBackfills() async throws {
  // Arrange: a cache already synced through May 20 (so start() takes the
  // differential path — `phase` stays `.ready` throughout it, which is exactly
  // why a UI guard on `phase` alone cannot rule out a rebuild racing this run).
  // April is already cached history that a naive immediate reset would lose.
  let context = try InMemoryStore.makeContext()
  let today = makeDate(2026, 6, 15)
  let stepLogStore = SwiftDataStepLogStore(context: context, calendar: testCalendar, now: { today })
  let marimoStore = SwiftDataMarimoStore(context: context)
  try stepLogStore.upsert([DailySteps(day: makeDay(2026, 4, 5), steps: 5_000)])
  try stepLogStore.saveAnchor(SyncAnchor(lastSyncedDate: makeDate(2026, 5, 20)))

  let source = PausingDailyStepsSource(
    earliest: makeDate(2026, 4, 1),
    allDays: [
      DailySteps(day: makeDay(2026, 4, 5), steps: 5_000),
      DailySteps(day: makeDay(2026, 6, 14), steps: 8_000),
    ]
  )
  let coordinator = StepSyncCoordinator(
    source: source, stepLogStore: stepLogStore, marimoStore: marimoStore, calendar: testCalendar,
    now: { today })
  let model = StepSyncModel(coordinator: coordinator)

  // Act: start the differential sync and let it reach its `dailySteps` read, then
  // request a rebuild while that read is paused (`isSyncing` is still true).
  let syncTask = Task { await model.start() }
  await source.waitForFirstDailyStepsRequest()

  let rebuildTask = Task { await model.rebuild() }
  await rebuildTask.value

  // Release the paused differential read; it completes and saves a fresh anchor
  // before the queued rebuild gets its own turn.
  source.releaseFirstDailyStepsRequest()
  await syncTask.value

  // Assert: the rebuild's turn ran strictly after the differential sync's own
  // upsert/anchor save, so the reset caught a clean state and the redrive was a
  // genuine full backfill — April survives instead of being silently dropped by
  // a reset that landed between the differential sync's read and its write.
  #expect(model.phase == .ready)
  #expect(source.dailyStepsRequestCount == 2)
  #expect(
    try stepLogStore.logs(in: DayInterval(start: makeDay(2026, 4, 1), end: makeDay(2026, 6, 15)))
      .map(\.day) == [makeDay(2026, 4, 5), makeDay(2026, 6, 14)]
  )
}

@MainActor
@Test("An overlapping start queues one follow-up sync instead of dropping it")
func syncQueuesFollowUpWhenStartOverlaps() async throws {
  // Arrange: the in-flight sync sees no samples, then the queued follow-up sees data.
  let source = PausingStepSource(
    earliestResults: [nil, makeDate(2026, 6, 1)],
    stepsToReturn: [DailySteps(day: makeDay(2026, 6, 27), steps: 8_432)]
  )
  let model = try makeModel(source: source, today: makeDate(2026, 6, 28))

  // Act
  let firstStart = Task { await model.start() }
  await source.waitForEarliestRequest()

  let overlappingStart = Task { await model.start() }
  await overlappingStart.value
  source.releaseEarliestRequest()

  await source.waitForEarliestRequest()
  source.releaseEarliestRequest()
  await firstStart.value

  // Assert: the overlapping call is collapsed into one retry after the current run.
  #expect(source.earliestRequestCount == 2)
  #expect(model.completedSyncCount == 2)
  #expect(model.phase == .ready)
}
