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

  /// Current observation identity for cache-backed sections.
  var observationKey: ObservationKey {
    ObservationKey(phase: phase, completedSyncCount: completedSyncCount)
  }

  private let coordinator: StepSyncCoordinator
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

  init(coordinator: StepSyncCoordinator) {
    self.coordinator = coordinator
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
      if current == .rebuild {
        // Drops before the reset so no observer sees stale `.ready` content in
        // the gap before the reset resolves.
        phase = .loading
        try? coordinator.rebuildCache()
      }
      await runOnce()
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

  /// Executes one coordinator sync and publishes its settled result.
  private func runOnce() async {
    do {
      try await coordinator.sync { [weak self] progress in
        // Only the long initial backfill drives a progress phase; the quick
        // differential sync stays on the current phase to avoid a progress flash.
        if case .backfilling(let completed, let total) = progress {
          self?.phase = .backfilling(completedDays: completed, totalDays: total)
        }
      }
    } catch {
      // Swallow: read-only HealthKit access can't be confirmed, so render whatever
      // coverage reports from the cache rather than surfacing an error.
    }
    // Reconcile the frozen monthly marimos from the freshly-synced cache so the
    // shelf reflects newly completed and grace-period months. Done before the
    // count bumps, so observers see the updated store on the same observation key.
    // Swallowed like the sync: a read-only failure should not block rendering what
    // coverage already has.
    try? coordinator.refreshFrozenMarimos()
    resolveSettledPhase()
    completedSyncCount += 1
  }

  /// Settles the phase from coverage alone, with no live source query.
  ///
  /// No first available day means no step data has ever existed: show `.empty`
  /// rather than `.ready` over an all-unavailable cache.
  private func resolveSettledPhase() {
    let hasData = (try? coordinator.coverage())?.firstAvailableDay != nil
    phase = hasData ? .ready : .empty
  }
}
