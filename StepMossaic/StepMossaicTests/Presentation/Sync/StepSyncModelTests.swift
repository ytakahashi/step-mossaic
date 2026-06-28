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
  let store = SwiftDataStepLogStore(
    context: try InMemoryStore.makeContext(), calendar: testCalendar, now: { today })
  let coordinator = StepSyncCoordinator(
    source: source, stepLogStore: store, calendar: testCalendar, now: { today })
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
