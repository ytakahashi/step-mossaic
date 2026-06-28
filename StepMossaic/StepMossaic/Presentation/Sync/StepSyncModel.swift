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
  /// Guards against a second concurrent run (e.g. a re-appear while a backfill is
  /// still in flight) launching a duplicate sync against the same store.
  private var isSyncing = false
  /// Records that another sync was requested while one was in flight, so auth
  /// grants or re-appears are not lost when they race the current run.
  private var needsFollowUpSync = false

  init(coordinator: StepSyncCoordinator) {
    self.coordinator = coordinator
  }

  /// Syncs the cache once, reporting backfill progress, then settles on `.ready`
  /// or `.empty` from coverage. A call made while a sync is already running is
  /// folded into one follow-up run after the current sync settles.
  ///
  /// Safe to invoke on every appearance and after an authorization grant: the
  /// guard collapses overlapping calls, and a settled run re-runs the cheap
  /// differential sync without flashing back to `.loading`.
  func start() async {
    guard !isSyncing else {
      needsFollowUpSync = true
      return
    }
    isSyncing = true
    defer { isSyncing = false }

    repeat {
      needsFollowUpSync = false
      await runOnce()
    } while needsFollowUpSync
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
