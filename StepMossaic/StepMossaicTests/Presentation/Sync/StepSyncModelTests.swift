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

/// Wires a sync model to fake, individually-throwable stores instead of a real
/// SwiftData container, so failure-path tests can force a specific persistence
/// call to fail deterministically (something an in-memory `ModelContainer`
/// cannot be made to do).
@MainActor
private func makeFailableModel(
  source: FakeStepSource,
  stepLogStore: FakeStepLogStore,
  marimoStore: FakeMarimoStore = FakeMarimoStore(),
  today: Date,
  reporter: @escaping DiagnosticsReporter = { _, _ in }
) -> StepSyncModel {
  let coordinator = StepSyncCoordinator(
    source: source, stepLogStore: stepLogStore, marimoStore: marimoStore, calendar: testCalendar,
    now: { today })
  return StepSyncModel(coordinator: coordinator, reporter: reporter)
}

private struct TestError: Error {}

/// Source that fails its first earliest-sample read, then lets a retry pause
/// first at that read and later at the daily backfill read. Tests use the two
/// suspension points to inspect the model's transient `.loading` and
/// `.backfilling` phases rather than only its final settled state.
private final class FailingThenPausingStepSource: StepSource, @unchecked Sendable {
  var status: HealthAuthorizationStatus = .requested
  private var shouldFail = true
  private var earliestContinuation: CheckedContinuation<Date?, Never>?
  private var dailyContinuation: CheckedContinuation<[DailySteps], Never>?
  private var earliestWaiter: CheckedContinuation<Void, Never>?
  private var dailyWaiter: CheckedContinuation<Void, Never>?

  func authorizationStatus() -> HealthAuthorizationStatus { status }

  func requestAuthorization() async throws {}

  func earliestSampleDate() async throws -> Date? {
    if shouldFail {
      shouldFail = false
      throw TestError()
    }
    earliestWaiter?.resume()
    earliestWaiter = nil
    return await withCheckedContinuation { earliestContinuation = $0 }
  }

  func dailySteps(in interval: DayInterval) async throws -> [DailySteps] {
    dailyWaiter?.resume()
    dailyWaiter = nil
    return await withCheckedContinuation { dailyContinuation = $0 }
  }

  func observeTodayUpdates() -> AsyncStream<Void> {
    AsyncStream { $0.finish() }
  }

  func waitForEarliestRequest() async {
    guard earliestContinuation == nil else { return }
    await withCheckedContinuation { earliestWaiter = $0 }
  }

  func releaseEarliestRequest() {
    let continuation = earliestContinuation
    earliestContinuation = nil
    continuation?.resume(returning: makeDate(2026, 6, 1))
  }

  func waitForDailyRequest() async {
    guard dailyContinuation == nil else { return }
    await withCheckedContinuation { dailyWaiter = $0 }
  }

  func releaseDailyRequest() {
    let continuation = dailyContinuation
    dailyContinuation = nil
    continuation?.resume(
      returning: [DailySteps(day: makeDay(2026, 6, 27), steps: 8_432)])
  }
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

/// Step source whose live-tick stream is driven by hand (`emitTick()` /
/// `finishTicks()`) rather than firing a fixed burst at stream-creation time,
/// combined with a `dailySteps(in:)` that pauses on its first call. A source
/// that just yields N ticks upfront makes coalescing a real Task-scheduling
/// race (how many land before the coordinator's forwarding task reacts is
/// scheduler luck); driving ticks by hand instead lets a test pin the exact
/// moment further ticks arrive relative to an in-flight sync.
private final class ControlledTickSource: StepSource, @unchecked Sendable {
  var status: HealthAuthorizationStatus = .requested
  private let stepsToReturn: [DailySteps]
  private(set) var dailyStepsRequestCount = 0

  private var tickContinuation: AsyncStream<Void>.Continuation?
  private var didPauseOnce = false
  private var pausedContinuation: CheckedContinuation<Void, Never>?
  private var waitContinuation: CheckedContinuation<Void, Never>?
  /// Resumed once `observeTodayUpdates()` has actually been called, so a test
  /// can wait for the stream to exist before calling `emitTick()`. Needed
  /// because `Task { await model.observeLiveUpdates() }` only *schedules* that
  /// work — the very next line of the test runs before the task body has
  /// reached `observeTodayUpdates()`, so `emitTick()` called too early would
  /// silently no-op against a still-nil `tickContinuation`.
  private var observingContinuation: CheckedContinuation<Void, Never>?

  init(stepsToReturn: [DailySteps]) {
    self.stepsToReturn = stepsToReturn
  }

  func authorizationStatus() -> HealthAuthorizationStatus { status }

  func requestAuthorization() async throws {}

  /// Never expected to be called: every test using this fixture pre-seeds an
  /// anchor so `sync()` always takes the differential path.
  func earliestSampleDate() async throws -> Date? { nil }

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
    return stepsToReturn
  }

  func observeTodayUpdates() -> AsyncStream<Void> {
    AsyncStream { continuation in
      tickContinuation = continuation
      observingContinuation?.resume()
      observingContinuation = nil
    }
  }

  /// Waits until `observeTodayUpdates()` has been called, so `emitTick()`
  /// can't be called before the stream exists to receive it.
  func waitUntilObserving() async {
    guard tickContinuation == nil else { return }
    await withCheckedContinuation { continuation in
      observingContinuation = continuation
    }
  }

  /// Emits one live tick. Synchronous and never suspends, so a test can create a
  /// burst while the first sync is still paused; the production coalescing
  /// guarantee comes from `StepSyncModel` not reading ahead while that sync runs.
  func emitTick() {
    tickContinuation?.yield(())
  }

  func finishTicks() {
    tickContinuation?.finish()
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
@Test("A burst of live ticks arriving mid-sync coalesces into one follow-up, not one per tick")
func rapidLiveTicksCoalesce() async throws {
  // Arrange: pre-seed an anchor (as if already synced through June 20) so the
  // tick-driven syncs below take the differential path directly. No initial
  // `model.start()` is made — that would consume the source's one-time
  // `dailySteps` pause on an unrelated backfill instead of the tick we want
  // paused.
  let context = try InMemoryStore.makeContext()
  let today = makeDate(2026, 6, 28)
  let stepLogStore = SwiftDataStepLogStore(context: context, calendar: testCalendar, now: { today })
  let marimoStore = SwiftDataMarimoStore(context: context)
  try stepLogStore.saveAnchor(SyncAnchor(lastSyncedDate: makeDate(2026, 6, 20)))

  let source = ControlledTickSource(
    stepsToReturn: [DailySteps(day: makeDay(2026, 6, 27), steps: 8_432)]
  )
  let coordinator = StepSyncCoordinator(
    source: source, stepLogStore: stepLogStore, marimoStore: marimoStore, calendar: testCalendar,
    now: { today })
  let model = StepSyncModel(coordinator: coordinator)

  // Act: observe live updates in the background, then drive the burst by hand
  // instead of letting the source fire a fixed number of ticks upfront and
  // hoping real scheduling coalesces them.
  let observeTask = Task { await model.observeLiveUpdates() }

  // `Task { }` only schedules that work — this line runs before its body has
  // reached `observeTodayUpdates()`. Without waiting here, `emitTick()` below
  // would race a still-nil stream and silently drop the tick, hanging the test
  // forever on the `waitForFirstDailyStepsRequest()` that follows.
  await source.waitUntilObserving()

  // The first tick kicks off a differential sync, which pauses on its
  // `dailySteps` read. `waitForFirstDailyStepsRequest()` only returns once that
  // read has actually started — which, since everything here runs
  // cooperatively on the main actor, guarantees the coordinator's forwarding
  // task has already relayed this tick and looped back to await the next one.
  source.emitTick()
  await source.waitForFirstDailyStepsRequest()

  // Two more ticks arrive while that sync is still in flight. Since
  // `observeLiveUpdates()` is awaiting the first drain rather than reading ahead,
  // the coordinator's newest-only buffer exposes the burst as one relayed signal.
  source.emitTick()
  source.emitTick()
  source.finishTicks()

  // Release the paused read: the first sync completes, then the single
  // coalesced signal above drives exactly one more (unpaused) sync before the
  // now-finished tick stream ends the observation loop.
  //
  // Unlike `rebuildDuringInFlightDifferentialSyncStillFullBackfills` and
  // `syncQueuesFollowUpWhenStartOverlaps` below, this test does not pin the
  // race by holding a continuation open until the overlap is confirmed — the
  // two `emitTick()` calls above just queue their resumption ahead of this
  // one in program order and rely on the cooperative scheduler draining
  // already-ready work in that same order. That has held up over repeated
  // full-suite runs, but it is a softer guarantee than the other two tests'
  // pinned overlap. If this test ever turns flaky again, this ordering
  // assumption — not the `enqueue`/`runTask` fold logic itself — is the first
  // place to look.
  source.releaseFirstDailyStepsRequest()
  await observeTask.value

  // Assert: the burst produced exactly one folded follow-up rather than one
  // sync per tick — two `dailySteps` reads and two completed sync turns, not
  // three of each.
  #expect(model.phase == .ready)
  #expect(model.completedSyncCount == 2)
  #expect(source.dailyStepsRequestCount == 2)
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
  // request a rebuild while that read is paused and the run is still in flight.
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

@MainActor
@Test("A source failure with an existing cache settles .failed but keeps the cache readable")
func sourceFailureWithCacheSettlesFailedKeepingCache() async throws {
  // Arrange: a cache already synced through June 20, so `sync()` takes the
  // differential path, which fails once it reads the source.
  let stepLogStore = FakeStepLogStore(
    seedLogs: [DailySteps(day: makeDay(2026, 6, 10), steps: 5_000)],
    anchor: SyncAnchor(lastSyncedDate: makeDate(2026, 6, 20))
  )
  let source = FakeStepSource()
  source.errorToThrow = TestError()
  let model = makeFailableModel(
    source: source, stepLogStore: stepLogStore, today: makeDate(2026, 6, 28))

  // Act
  await model.start()

  // Assert: the existing cache is still there, so the section can keep showing it.
  #expect(model.phase == .failed(hasCachedData: true))
  #expect(model.failureKind == .source)
}

@MainActor
@Test("A source failure with no prior cache settles .failed with no cache to show")
func sourceFailureWithoutCacheSettlesFailedWithoutCache() async throws {
  // Arrange: no anchor yet, so `sync()` takes the backfill path, which fails on
  // its very first source read.
  let stepLogStore = FakeStepLogStore()
  let source = FakeStepSource()
  source.errorToThrow = TestError()
  let model = makeFailableModel(
    source: source, stepLogStore: stepLogStore, today: makeDate(2026, 6, 28))

  // Act
  await model.start()

  // Assert
  #expect(model.phase == .failed(hasCachedData: false))
  #expect(model.failureKind == .source)
}

@MainActor
@Test("A coverage read failure after a successful sync settles .failed, not .empty")
func coverageFailureSettlesFailedNotEmpty() async throws {
  // Arrange: the sync itself succeeds and writes real data, but the dedicated
  // `earliestLoggedDay()` hook — reached only from `coverage()` — fails, so the
  // sync/refresh steps this turn are unaffected.
  let stepLogStore = FakeStepLogStore()
  let source = FakeStepSource(earliest: makeDate(2026, 6, 1))
  source.stepsToReturn = [DailySteps(day: makeDay(2026, 6, 27), steps: 8_432)]
  stepLogStore.earliestLoggedDayErrorToThrow = TestError()
  let model = makeFailableModel(
    source: source, stepLogStore: stepLogStore, today: makeDate(2026, 6, 28))

  // Act
  await model.start()

  // Assert: a coverage-read failure must not be mistaken for the ordinary
  // "no data" empty state.
  #expect(model.phase == .failed(hasCachedData: false))
  #expect(model.failureKind == .persistence)
}

@MainActor
@Test("A frozen-marimo refresh failure settles .failed while the daily cache is kept")
func refreshFrozenMarimosFailureSettlesFailedKeepingCache() async throws {
  // Arrange: history spanning April..June (today), so April is a completed past
  // month `refreshFrozenMarimos()` actually attempts to freeze — reaching the
  // marimo store, which is the one made to fail.
  let stepLogStore = FakeStepLogStore()
  let source = FakeStepSource(earliest: makeDate(2026, 4, 1))
  source.stepsToReturn = [
    DailySteps(day: makeDay(2026, 4, 5), steps: 5_000),
    DailySteps(day: makeDay(2026, 6, 15), steps: 8_000),
  ]
  let marimoStore = FakeMarimoStore()
  marimoStore.errorToThrow = TestError()
  let model = makeFailableModel(
    source: source, stepLogStore: stepLogStore, marimoStore: marimoStore,
    today: makeDate(2026, 6, 15))

  // Act
  await model.start()

  // Assert: the daily cache the sync just wrote is intact even though the turn
  // as a whole settled `.failed`.
  #expect(model.phase == .failed(hasCachedData: true))
  #expect(model.failureKind == .persistence)
  #expect(
    try stepLogStore.logs(in: DayInterval(start: makeDay(2026, 4, 1), end: makeDay(2026, 6, 15)))
      .count == 2)
}

@MainActor
@Test("Retry succeeds from .failed and settles back on .ready")
func retrySucceedsFromFailed() async throws {
  // Arrange: the first sync fails outright.
  let stepLogStore = FakeStepLogStore()
  let source = FakeStepSource()
  source.errorToThrow = TestError()
  let model = makeFailableModel(
    source: source, stepLogStore: stepLogStore, today: makeDate(2026, 6, 28))
  await model.start()
  #expect(model.phase == .failed(hasCachedData: false))

  // Act: the underlying condition clears, then the user retries.
  source.errorToThrow = nil
  source.earliest = makeDate(2026, 6, 1)
  source.stepsToReturn = [DailySteps(day: makeDay(2026, 6, 27), steps: 8_432)]
  await model.retry()

  // Assert
  #expect(model.phase == .ready)
  #expect(model.failureKind == nil)
}

@MainActor
@Test("Retry clears the previous failure when backfill begins")
func retryClearsFailureWhenBackfillBegins() async throws {
  // Arrange
  let source = FailingThenPausingStepSource()
  let model = try makeModel(source: source, today: makeDate(2026, 6, 28))
  await model.start()
  #expect(model.phase == .failed(hasCachedData: false))
  #expect(model.failureKind == .source)

  // Act: release the earliest read so retry advances to backfill, then hold the
  // daily read to inspect that transient phase before the run can settle.
  let retry = Task { await model.retry() }
  await source.waitForEarliestRequest()
  source.releaseEarliestRequest()
  await source.waitForDailyRequest()

  // Assert
  guard case .backfilling = model.phase else {
    Issue.record("Expected retry to be backfilling")
    source.releaseDailyRequest()
    await retry.value
    return
  }
  #expect(model.failureKind == nil)

  source.releaseDailyRequest()
  await retry.value
}

@MainActor
@Test("Rebuild clears the previous failure when loading begins")
func rebuildClearsFailureWhenLoadingBegins() async throws {
  // Arrange
  let source = FailingThenPausingStepSource()
  let model = try makeModel(source: source, today: makeDate(2026, 6, 28))
  await model.start()
  #expect(model.phase == .failed(hasCachedData: false))
  #expect(model.failureKind == .source)

  // Act: rebuild resets the empty cache and then pauses at the first source read,
  // leaving its `.loading` transition observable.
  let rebuild = Task { await model.rebuild() }
  await source.waitForEarliestRequest()

  // Assert
  #expect(model.phase == .loading)
  #expect(model.failureKind == nil)

  source.releaseEarliestRequest()
  await source.waitForDailyRequest()
  source.releaseDailyRequest()
  await rebuild.value
}

@MainActor
@Test("Overlapping retry requests collapse into one follow-up, sharing start()'s queue")
func retryRequestsCoalesceThroughSharedQueue() async throws {
  // Arrange: mirrors `syncQueuesFollowUpWhenStartOverlaps`, but through
  // `retry()`, to confirm it drives the same serialized request queue as
  // `start()` rather than a queue of its own.
  let source = PausingStepSource(
    earliestResults: [nil, makeDate(2026, 6, 1)],
    stepsToReturn: [DailySteps(day: makeDay(2026, 6, 27), steps: 8_432)]
  )
  let model = try makeModel(source: source, today: makeDate(2026, 6, 28))

  // Act
  let firstRetry = Task { await model.retry() }
  await source.waitForEarliestRequest()

  let overlappingRetry = Task { await model.retry() }
  await overlappingRetry.value
  source.releaseEarliestRequest()

  await source.waitForEarliestRequest()
  source.releaseEarliestRequest()
  await firstRetry.value

  // Assert: the overlapping call is collapsed into one retry after the current run.
  #expect(source.earliestRequestCount == 2)
  #expect(model.completedSyncCount == 2)
  #expect(model.phase == .ready)
}

@MainActor
@Test("A rebuild reset failure settles .failed without continuing into a sync")
func rebuildResetFailureSkipsSync() async throws {
  // Arrange: a working cache, so a sync that incorrectly ran after the failed
  // reset would be observable as `.ready` instead of the expected `.failed`.
  let stepLogStore = FakeStepLogStore()
  let source = FakeStepSource(earliest: makeDate(2026, 6, 1))
  source.stepsToReturn = [DailySteps(day: makeDay(2026, 6, 27), steps: 8_432)]
  let model = makeFailableModel(
    source: source, stepLogStore: stepLogStore, today: makeDate(2026, 6, 28))
  await model.start()
  #expect(model.phase == .ready)

  // The reset itself now fails; every other store call still succeeds.
  stepLogStore.resetErrorToThrow = TestError()

  // Act
  await model.rebuild()

  // Assert: settles `.failed` rather than a `.ready` that would mean a sync ran
  // over a possibly-partial wipe. `hasCachedData` is `true` because this fake's
  // `reset()` throws before mutating its storage, leaving the prior cache
  // intact and still readable by the best-effort coverage re-check.
  #expect(model.phase == .failed(hasCachedData: true))
  #expect(model.failureKind == .persistence)
}

@MainActor
@Test("Diagnostics reports only the operation and coarse failure kind, never the raw error")
func diagnosticsReportsOperationAndKindOnly() async throws {
  // Arrange: a source failure with an existing cache, so both a `.sync`
  // failure and (if reached) later successes could be reported.
  let stepLogStore = FakeStepLogStore(
    seedLogs: [DailySteps(day: makeDay(2026, 6, 10), steps: 5_000)],
    anchor: SyncAnchor(lastSyncedDate: makeDate(2026, 6, 20))
  )
  let source = FakeStepSource()
  source.errorToThrow = TestError()
  var reported: [(DiagnosticOperation, DiagnosticOutcome)] = []
  let model = makeFailableModel(
    source: source, stepLogStore: stepLogStore, today: makeDate(2026, 6, 28),
    reporter: { operation, outcome in reported.append((operation, outcome)) }
  )

  // Act
  await model.start()

  // Assert: exactly one event, naming the failed operation and its coarse
  // classification — the closure's signature makes a raw `Error` or its
  // description structurally unreachable here.
  #expect(reported.count == 1)
  #expect(reported.first?.0 == .sync)
  #expect(reported.first?.1 == .failure(.source))
}
