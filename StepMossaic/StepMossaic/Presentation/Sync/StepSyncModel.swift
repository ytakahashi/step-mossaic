import Foundation
import Observation
import StepMossaicDomain

/// Owns the single cache-sync lifecycle for the app's cache-backed sections.
///
/// M2 kept the sync coupled inside the heatmap view model; lifting it here lets
/// every section that renders from the cached daily logs (the heatmap, and the
/// growing marimo next) observe one sync rather than each triggering its own —
/// which on a first launch would race two backfills against the same store.
///
/// Main-actor isolated because it drives the main-actor `StepSyncCoordinator`. It
/// only resolves the shared lifecycle; each section maps `phase` onto its own UI
/// and reads the cache itself, so this model never holds rendered data.
@MainActor
@Observable
final class StepSyncModel {
  /// The shared sync lifecycle each cache-backed section maps onto its own state.
  enum Phase: Equatable {
    /// Resolving the first load (or a quick differential sync).
    case loading
    /// Initial backfill in flight; `completedDays` advances toward `totalDays`.
    case backfilling(completedDays: Int, totalDays: Int)
    /// Sync settled and at least one day of step data exists.
    case ready
    /// Sync settled but no step data exists at all.
    case empty
    /// Sync, cache-freshness reconciliation, or coverage read failed this turn.
    /// `hasCachedData` reports whether a previously-synced cache can still be
    /// shown, so a section can keep rendering it instead of blanking out.
    case failed(hasCachedData: Bool)
  }

  /// Stable identity for section observers: changes for both visible phase
  /// transitions and same-phase sync completions.
  struct ObservationKey: Equatable {
    let phase: Phase
    let completedSyncCount: Int
  }

  private(set) var phase: Phase = .loading
  /// Monotonic completion count so observers can refresh after a differential
  /// sync that settles back to the same phase.
  private(set) var completedSyncCount = 0
  /// Set alongside every `.failed` phase and cleared on the next fully-settled
  /// `.ready`/`.empty`; `nil` whenever `phase` is not `.failed`.
  private(set) var failureKind: DiagnosticFailureKind?

  /// Current observation identity for cache-backed sections.
  var observationKey: ObservationKey {
    ObservationKey(phase: phase, completedSyncCount: completedSyncCount)
  }

  private let coordinator: StepSyncCoordinator
  private let reporter: DiagnosticsReporter
  /// What the currently in-flight run should do on its next turn once it loops,
  /// so a call arriving mid-run is never lost. `.rebuild` always wins over a
  /// pending `.sync`/`.liveSync` and is never downgraded back — see
  /// `request(_:)`.
  private enum PendingRun: Equatable {
    case none
    case sync
    case liveSync
    case rebuild
  }
  private var pending: PendingRun = .none
  /// The single serialized run loop currently draining queued sync work.
  ///
  /// Set before the task is launched, so additional requests arriving before the
  /// task body starts still fold into `pending` instead of launching a duplicate.
  private var runTask: Task<Void, Never>?

  /// `reporter` defaults to a no-op so existing call sites (and most tests)
  /// don't need to care about diagnostics; the composition root passes
  /// `DiagnosticsLogger.report` explicitly for the real app.
  init(
    coordinator: StepSyncCoordinator,
    reporter: @escaping DiagnosticsReporter = { _, _ in }
  ) {
    self.coordinator = coordinator
    self.reporter = reporter
  }

  /// Re-requests a sync after `.failed`, through the same serialized queue as
  /// `start()`. A separate name from `start()` so call sites read as "the user
  /// asked to retry" rather than "a section appeared", even though both drive
  /// the identical sync path.
  func retry() async {
    await request(.sync)
  }

  /// Syncs the cache once, reporting backfill progress, then settles on `.ready`
  /// or `.empty` from coverage. A call made while a run is already in flight is
  /// folded into one follow-up turn after the current run loops.
  ///
  /// Safe to invoke on every appearance and after an authorization grant: the
  /// guard collapses overlapping calls, and a settled run re-runs the cheap
  /// differential sync without flashing back to `.loading`.
  func start() async {
    await request(.sync)
  }

  /// Wipes the cached daily logs and every frozen marimo, then redrives the
  /// normal sync lifecycle as if this were a first launch.
  ///
  /// Serialized through the same run loop as `start()` rather than resetting
  /// immediately: `phase` stays `.ready` for the whole *duration* of a
  /// differential sync (e.g. one driven by a live tick), so a UI guard that only
  /// checks `phase` cannot rule out a rebuild request racing an in-flight run.
  /// Resetting out from under that run would let its own `upsert`/`saveAnchor`
  /// land *after* the reset — leaving a partial cache with a fresh anchor, which
  /// would send the very next turn down the differential path instead of a full
  /// backfill and permanently lose history. Queuing through `request(_:)`
  /// instead guarantees the reset always happens immediately before its own
  /// dedicated `runOnce()`, inside one serialized turn.
  func rebuild() async {
    await request(.rebuild)
  }

  /// Runs `kind` now if nothing is in flight, otherwise folds it into the
  /// in-flight run's next turn.
  private func request(_ kind: PendingRun) async {
    let request = enqueue(kind)
    if request.startedNewRun {
      await request.task.value
    }
  }

  /// Queues a run request synchronously and returns the task draining the queue.
  ///
  /// This is the critical coalescing boundary for live ticks: observing code
  /// queues the request before it awaits any work, so an already-running sync
  /// sees the tick immediately as `pending` instead of depending on when child
  /// tasks happen to start running.
  @discardableResult
  private func enqueue(_ kind: PendingRun) -> (task: Task<Void, Never>, startedNewRun: Bool) {
    if let task = runTask {
      // A pending rebuild is never downgraded back to a plain sync/live tick,
      // since the rebuild's redrive already covers whatever they would have done.
      switch (pending, kind) {
      case (_, .rebuild):
        pending = kind
      case (.none, _):
        pending = kind
      default:
        break
      }
      return (task, false)
    }

    let task = Task { [weak self] in
      guard let self else { return }
      await self.drainRequests(startingWith: kind)
    }
    runTask = task
    return (task, true)
  }

  /// Drains the current request and every folded follow-up in one serialized loop.
  private func drainRequests(startingWith kind: PendingRun) async {
    defer {
      runTask = nil
    }

    var current = kind
    repeat {
      pending = .none
      var rebuildSucceeded = true
      if current == .rebuild {
        // Drops before the reset so no observer sees stale `.ready` content in
        // the gap before the reset resolves.
        setPhase(.loading)
        do {
          try coordinator.rebuildCache()
          reporter(.rebuild, .success)
        } catch {
          // Not left un-cleared: an unreset store must never read as a
          // completed rebuild, so this turn settles `.failed` immediately
          // instead of continuing into a sync over a possibly-partial wipe.
          rebuildSucceeded = false
          settle(failing: .persistence, operation: .rebuild)
          completedSyncCount += 1
        }
      }
      if rebuildSucceeded {
        await runOnce()
      }
      current = pending
    } while pending != .none
  }

  /// Keeps the cache fresh during a foreground session: each live tick requests a
  /// differential sync turn, which (once settled) bumps `completedSyncCount`
  /// without changing the visible phase, so the cache-backed sections re-render
  /// through their existing `observe` path. Empty caches with no anchor yet can
  /// even promote to `.ready` once the first samples appear.
  ///
  /// Live ticks use their own request kind so their overlap/coalescing rules
  /// live beside normal `start()` and destructive `rebuild()` requests. The loop
  /// waits for the drain task after each relayed tick, leaving rapid subsequent
  /// ticks in the coordinator's newest-only buffer while sync work is in flight.
  /// If a tick is consumed while another request is already running, it folds
  /// into the same pending slot as any other overlap. Rebuild still wins if it is
  /// requested while live work is in flight.
  ///
  /// Driven by `.task` so the underlying observer query is torn down on disappear.
  func observeLiveUpdates() async {
    for await _ in coordinator.observeStepUpdates() {
      let request = enqueue(.liveSync)
      await request.task.value
    }
  }

  /// Executes one coordinator sync turn and publishes its settled result.
  ///
  /// Each step only runs once the previous one has succeeded: `.ready`/`.empty`
  /// require sync, frozen-marimo reconciliation, *and* the coverage read to all
  /// succeed, so a partial failure never reads as a clean settle. Whichever step
  /// fails first ends the turn on `.failed` rather than continuing over data
  /// that may now be stale relative to what the failed step would have changed.
  private func runOnce() async {
    do {
      try await coordinator.sync { [weak self] progress in
        // Only the long initial backfill drives a progress phase; the quick
        // differential sync stays on the current phase to avoid a progress flash.
        if case .backfilling(let completed, let total) = progress {
          self?.setPhase(.backfilling(completedDays: completed, totalDays: total))
        }
      }
    } catch {
      settle(failing: classifyFailure(from: error), operation: .sync)
      completedSyncCount += 1
      return
    }
    reporter(.sync, .success)

    // Reconcile the frozen monthly marimos from the freshly-synced cache so the
    // shelf reflects newly completed and grace-period months. A failure here
    // still leaves the daily cache trustworthy, but the turn as a whole did not
    // fully succeed, so it settles `.failed` rather than `.ready`/`.empty`.
    do {
      try coordinator.refreshFrozenMarimos()
    } catch {
      settle(failing: .persistence, operation: .refreshFrozenMarimos)
      completedSyncCount += 1
      return
    }
    reporter(.refreshFrozenMarimos, .success)

    resolveSettledPhase()
    completedSyncCount += 1
  }

  /// Settles the phase from coverage alone, with no live source query.
  ///
  /// No first available day means no step data has ever existed: show `.empty`
  /// rather than `.ready` over an all-unavailable cache. A coverage read
  /// failure is itself a `.persistence` failure (`coverage()` only reads the
  /// cache) — it must not be mistaken for the ordinary "no data" `.empty`.
  private func resolveSettledPhase() {
    do {
      let coverage = try coordinator.coverage()
      setPhase(coverage.firstAvailableDay != nil ? .ready : .empty)
      reporter(.coverage, .success)
    } catch {
      settle(failing: .persistence, operation: .coverage)
    }
  }

  /// Classifies a `sync()` failure from the `StepSyncCoordinator.Failure` it is
  /// expected to throw, falling back to `.unknown` for anything else.
  private func classifyFailure(from error: Error) -> DiagnosticFailureKind {
    switch error {
    case StepSyncCoordinator.Failure.source: .source
    case StepSyncCoordinator.Failure.persistence: .persistence
    default: .unknown
    }
  }

  /// Moves to `.failed`, preserving whether a previously-synced cache can still
  /// be shown, and reports the outcome for diagnostics.
  ///
  /// Cache presence is re-derived from `coverage()` on a best-effort basis: if
  /// that read itself fails, `hasCachedData` is `false` rather than assumed —
  /// this is still `.failed`, never the ordinary `.empty`, so a real cache is
  /// never mistaken for "no data".
  private func settle(failing kind: DiagnosticFailureKind, operation: DiagnosticOperation) {
    let hasCachedData = (try? coordinator.coverage())?.firstAvailableDay != nil
    setPhase(.failed(hasCachedData: hasCachedData), failureKind: kind)
    reporter(operation, .failure(kind))
  }

  /// Publishes one phase transition while preserving the state invariant that
  /// only `.failed` carries a failure classification. Centralizing assignments
  /// here prevents a retry or rebuild from leaving the previous failure attached
  /// to a later `.loading`, `.backfilling`, `.ready`, or `.empty` phase.
  private func setPhase(_ newPhase: Phase, failureKind newFailureKind: DiagnosticFailureKind? = nil)
  {
    switch newPhase {
    case .failed:
      precondition(newFailureKind != nil, "A failed sync phase requires a failure kind")
    default:
      precondition(newFailureKind == nil, "Only a failed sync phase can carry a failure kind")
    }

    failureKind = newFailureKind
    phase = newPhase
  }
}
