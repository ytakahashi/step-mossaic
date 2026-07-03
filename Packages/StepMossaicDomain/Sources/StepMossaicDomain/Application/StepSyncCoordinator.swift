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
  /// Persists the frozen monthly marimos the shelf renders. Non-`Sendable` and
  /// driven only from this main-actor coordinator, like `stepLogStore`.
  private let marimoStore: any MarimoStore
  private let calendar: Calendar
  /// Injected clock so "today" stays deterministic in tests instead of reading
  /// the wall clock.
  private let now: @MainActor () -> Date
  /// Backfill window size. The history is fetched one window at a time so progress
  /// can be reported and a long range never lands in a single HealthKit request.
  private let chunkSizeInDays: Int
  /// Tunables for marimo generation, injected like the calendar so the same
  /// instance drives both the heatmap's coverage and the growing marimo.
  private let marimoConfig: MarimoGenerationConfig
  /// Decides when a past month's marimo locks, injected so the grace window is a
  /// composition-root tuning value rather than a constant buried here.
  private let freezePolicy: MarimoFreezePolicy

  public init(
    source: any StepSource,
    stepLogStore: any StepLogStore,
    marimoStore: any MarimoStore,
    calendar: Calendar,
    now: @escaping @MainActor () -> Date,
    chunkSizeInDays: Int = 365,
    marimoConfig: MarimoGenerationConfig = MarimoGenerationConfig(),
    freezePolicy: MarimoFreezePolicy = MarimoFreezePolicy(gracePeriodDays: 5)
  ) {
    precondition(chunkSizeInDays >= 1, "StepSyncCoordinator chunkSizeInDays must be >= 1")
    self.source = source
    self.stepLogStore = stepLogStore
    self.marimoStore = marimoStore
    self.calendar = calendar
    self.now = now
    self.chunkSizeInDays = chunkSizeInDays
    self.marimoConfig = marimoConfig
    self.freezePolicy = freezePolicy
  }

  private var today: Day { Day(containing: now(), calendar: calendar) }

  /// Relays the source's live "today changed" tick so the sync owner can keep the
  /// cache fresh mid-session without itself depending on the `StepSource`.
  ///
  /// Each emission means today's samples may have changed, so the consumer should
  /// run a differential `sync()`. Bursts are coalesced to the newest pending tick:
  /// the cache is re-read from the source, so intermediate tick identities carry
  /// no information and do not need one sync each. The underlying query is
  /// foreground-only and stops when the returned stream is cancelled.
  public func observeStepUpdates() -> AsyncStream<Void> {
    AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let task = Task { [source] in
        for await _ in source.observeTodayUpdates() {
          continuation.yield(())
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

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

  /// Builds the data coverage the domain aggregates over, from the persisted
  /// cache alone — no live source query.
  ///
  /// Rendering must survive HealthKit being momentarily unavailable or access not
  /// yet (re)resolved, so coverage is derived from what has been synced:
  /// - `firstAvailableDay` is the earliest cached day. Since 0-step days are not
  ///   stored, that is the user's first day with samples — the same day a live
  ///   earliest-sample query would report — and it also stays consistent with
  ///   differential sync, which does not backfill older history.
  /// - `lastSyncedDay` is how far sync has reached (the anchor), falling back to
  ///   today before the first sync so an empty interval is still valid.
  public func coverage() throws -> StepDataCoverage {
    guard let anchor = try stepLogStore.anchorState() else {
      return StepDataCoverage(firstAvailableDay: nil, lastSyncedDay: today)
    }
    let lastSyncedDay = Day(containing: anchor.lastSyncedDate, calendar: calendar)
    let firstAvailableDay = try stepLogStore.earliestLoggedDay()

    // Keep the `firstAvailableDay <= lastSyncedDay` invariant even if a log
    // exists past the anchor (e.g. the clock moved backward).
    let clampedLast = firstAvailableDay.map { max($0, lastSyncedDay) } ?? lastSyncedDay
    return StepDataCoverage(firstAvailableDay: firstAvailableDay, lastSyncedDay: clampedLast)
  }

  /// The current month's growing marimo, computed on demand from the cached logs —
  /// no live source query and no persistence (this month is never frozen).
  ///
  /// Returns `nil` when the month has no available target day yet (e.g. the cache
  /// is empty, or coverage has not reached this month). `MarimoGenerator` drops
  /// future days and days before coverage on its own, so the marimo grows from the
  /// month start through today.
  public func growingMarimo() throws -> MarimoParameters? {
    // Pin the render instant once so the selected month and "today" cannot split
    // across local midnight while this read-only render is being assembled.
    let renderDate = now()
    let renderDay = Day(containing: renderDate, calendar: calendar)
    let month = YearMonth(date: renderDate, calendar: calendar)
    let coverage = try coverage()
    let logs = try stepLogStore.logs(in: month.interval(calendar: calendar))

    return MarimoGenerator.parameters(
      for: month,
      daily: logs,
      coverage: coverage,
      today: renderDay,
      calendar: calendar,
      config: marimoConfig
    )
  }

  /// Reconciles the persisted frozen marimos for every completed past month, from
  /// the first available month through last month. Idempotent, so it is safe to
  /// run after each sync:
  ///
  /// - A locked month is an immutable monument: it is skipped without re-reading
  ///   its logs, so a late HealthKit edit cannot alter it. Refreshing a locked
  ///   month is only possible through a full cache rebuild.
  /// - A grace-period month is regenerated every run, so late-arriving samples and
  ///   past corrections are absorbed until the grace window closes and it locks.
  /// - A month with no available day (e.g. entirely outside coverage) is skipped.
  ///
  /// The current month is never persisted here — it is the growing marimo, drawn
  /// on demand. Month rollover needs no separate detection: once a month ends it
  /// simply enters this past-month range on the next run.
  public func refreshFrozenMarimos() throws {
    // Pin the instant so the month boundary and lock decisions share one "now".
    let renderDate = now()
    let today = Day(containing: renderDate, calendar: calendar)
    let coverage = try coverage()
    guard let firstAvailableDay = coverage.firstAvailableDay else { return }

    let firstMonth = YearMonth(date: firstAvailableDay.start, calendar: calendar)
    let currentMonth = YearMonth(date: renderDate, calendar: calendar)
    // Nothing to freeze until at least one month has fully completed.
    guard firstMonth < currentMonth else { return }

    // Read existing snapshots once so a locked month is recognized and skipped
    // without a per-month store round trip.
    let lockedMonths = Set(try marimoStore.allFrozen().lazy.filter(\.isLocked).map(\.yearMonth))

    var month = firstMonth
    while month < currentMonth {
      defer { month = month.next() }
      guard !lockedMonths.contains(month) else { continue }

      let logs = try stepLogStore.logs(in: month.interval(calendar: calendar))
      guard
        let parameters = MarimoGenerator.parameters(
          for: month,
          daily: logs,
          coverage: coverage,
          today: today,
          calendar: calendar,
          config: marimoConfig
        )
      else { continue }

      // A past month is only ever `.grace` or `.locked`; `.growing` is reserved
      // for the current/future month, which this loop never reaches.
      let isLocked = freezePolicy.lockState(for: month, now: today, calendar: calendar) == .locked
      try marimoStore.save(
        FrozenMarimo(
          yearMonth: month, parameters: parameters, frozenAt: renderDate, isLocked: isLocked))
    }
  }

  /// Clears the persisted daily-step cache and every frozen marimo, including
  /// locked months, so a full rebuild can start clean.
  ///
  /// HealthKit itself is never touched — this only wipes the SwiftData caches
  /// derived from it. Re-populating the cleared stores is the caller's job: with
  /// the anchor gone, the next `sync()` takes the same full-backfill path as a
  /// first launch, and `refreshFrozenMarimos()` regenerates every past month from
  /// scratch once that backfill lands.
  public func rebuildCache() throws {
    try stepLogStore.reset()
    try marimoStore.reset()
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
