import Foundation

/// Orchestrates syncing the daily-step cache from `StepSource` into `StepLogStore`
/// and reports the data `coverage` the rest of the app aggregates over.
///
/// Main-actor isolated because it drives a non-`Sendable` `StepLogStore`; the only
/// genuinely concurrent work is the `StepSource` reads, which are `async` and hop
/// off the main actor on their own. The store sees a single serialized caller.
///
/// Scope grows over later milestones (monthly marimo generation, month-rollover
/// regeneration, cache rebuild); for now it owns the backfill, differential sync,
/// and coverage construction.
@MainActor
public final class StepSyncCoordinator {
  private let source: any StepSource
  private let stepLogStore: any StepLogStore
  private let calendar: Calendar
  /// Injected clock so "today" stays deterministic in tests instead of reading
  /// the wall clock.
  private let now: @MainActor () -> Date
  /// Backfill window size. The history is fetched one window at a time so progress
  /// can be reported and a long range never lands in a single HealthKit request.
  private let chunkSizeInDays: Int

  public init(
    source: any StepSource,
    stepLogStore: any StepLogStore,
    calendar: Calendar,
    now: @escaping @MainActor () -> Date,
    chunkSizeInDays: Int = 365
  ) {
    precondition(chunkSizeInDays >= 1, "StepSyncCoordinator chunkSizeInDays must be >= 1")
    self.source = source
    self.stepLogStore = stepLogStore
    self.calendar = calendar
    self.now = now
    self.chunkSizeInDays = chunkSizeInDays
  }

  private var today: Day { Day(containing: now(), calendar: calendar) }

  /// Brings the cache up to date, choosing the path from the stored anchor:
  /// the first run (no anchor) backfills the whole history, later runs re-read
  /// only the window since the last sync. `onProgress` is invoked on the main
  /// actor and always ends with `.finished`.
  public func sync(onProgress: (SyncProgress) -> Void = { _ in }) async throws {
    // Pin the sync instant once per run so the queried interval end and the saved
    // anchor stay consistent even if the work straddles local midnight; reading
    // `now()` separately for each would record a different day than was fetched.
    let syncDate = now()
    let syncDay = Day(containing: syncDate, calendar: calendar)

    if let anchor = try stepLogStore.anchorState() {
      try await differentialSync(
        from: anchor, syncDate: syncDate, syncDay: syncDay, onProgress: onProgress)
    } else {
      try await backfill(syncDate: syncDate, syncDay: syncDay, onProgress: onProgress)
    }
    onProgress(.finished)
  }

  /// Builds the data coverage the domain aggregates over.
  ///
  /// `firstAvailableDay` is derived from the earliest *sample* (a cheap limit-1
  /// query), not the earliest stored log: days between the first sample and today
  /// with no recorded steps are available 0-step days, not gaps. `lastSyncedDay`
  /// comes from the anchor, falling back to today before the first sync.
  public func coverage() async throws -> StepDataCoverage {
    let earliest = try await source.earliestSampleDate()
    let firstAvailableDay = earliest.map { Day(containing: $0, calendar: calendar) }

    let lastSyncedDay: Day
    if let anchor = try stepLogStore.anchorState() {
      lastSyncedDay = Day(containing: anchor.lastSyncedDate, calendar: calendar)
    } else {
      lastSyncedDay = today
    }

    // Keep the `firstAvailableDay <= lastSyncedDay` invariant even if data exists
    // but no sync has been recorded, or the clock moved backward.
    let clampedLast = firstAvailableDay.map { max($0, lastSyncedDay) } ?? lastSyncedDay
    return StepDataCoverage(firstAvailableDay: firstAvailableDay, lastSyncedDay: clampedLast)
  }

  private func backfill(
    syncDate: Date,
    syncDay: Day,
    onProgress: (SyncProgress) -> Void
  ) async throws {
    guard let earliest = try await source.earliestSampleDate() else {
      // No samples yet: leave the anchor unset so a later launch retries the full
      // backfill once data exists (e.g. the user starts accruing steps, or a
      // device restore imports history) instead of locking into differential sync
      // from today and missing everything before it.
      return
    }

    let fullInterval = DayInterval(
      start: Day(containing: earliest, calendar: calendar),
      end: syncDay
    )
    let totalDays = fullInterval.days(calendar: calendar).count
    var completedDays = 0
    onProgress(.backfilling(completedDays: completedDays, totalDays: totalDays))

    for chunk in fullInterval.chunked(maxDays: chunkSizeInDays, calendar: calendar) {
      let daily = try await source.dailySteps(in: chunk)
      try stepLogStore.upsert(daily)
      completedDays += chunk.days(calendar: calendar).count
      onProgress(.backfilling(completedDays: completedDays, totalDays: totalDays))
    }

    try stepLogStore.saveAnchor(SyncAnchor(lastSyncedDate: syncDate))
  }

  private func differentialSync(
    from anchor: SyncAnchor,
    syncDate: Date,
    syncDay: Day,
    onProgress: (SyncProgress) -> Void
  ) async throws {
    onProgress(.syncing)

    let lastSynced = Day(containing: anchor.lastSyncedDate, calendar: calendar)
    // Re-reads only the last-synced-day..today window. This catches new days and
    // same-day corrections, but by design does NOT pick up edits to days before
    // `lastSynced` or historical samples that arrive late (e.g. a delayed sync or
    // a device restore backfilling old data). Recovering those is the job of a
    // full cache rebuild; re-scanning the whole history every launch is the cost
    // this trade deliberately avoids.
    //
    // Clamp the start to today so a clock that moved backward can't form an
    // invalid (start > end) interval; re-reading the last synced day is harmless.
    let interval = DayInterval(start: min(lastSynced, syncDay), end: syncDay)
    let daily = try await source.dailySteps(in: interval)
    try stepLogStore.upsert(daily)

    try stepLogStore.saveAnchor(SyncAnchor(lastSyncedDate: syncDate))
  }
}
