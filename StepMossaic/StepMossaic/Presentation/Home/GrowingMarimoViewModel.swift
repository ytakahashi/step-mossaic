import Foundation
import Observation
import StepMossaicDomain

/// Drives the Home "this month" growing marimo: renders the current month's
/// `MarimoParameters`, recomputed from the cached logs.
///
/// Cache-render only — it does not own the sync. `StepSyncModel` owns the single
/// sync lifecycle; this model mirrors that shared phase via `observe(_:)` and
/// reads the marimo from the coordinator once sync settles, exactly like
/// `HeatmapViewModel`.
@MainActor
@Observable
final class GrowingMarimoViewModel {
  /// What the marimo section should present.
  enum Phase: Equatable {
    /// Resolving the first load (or a quick differential sync).
    case loading
    /// Initial backfill in flight; the section shows it's still gathering data.
    case backfilling(completedDays: Int, totalDays: Int)
    /// This month's marimo is ready to draw.
    case ready(MarimoParameters)
    /// Sync settled but no step data exists for this month yet.
    case empty
    /// The shared sync failed and there is no cache to render — distinct from
    /// `.empty`, which means sync succeeded and genuinely found nothing.
    case failed
  }

  private(set) var phase: Phase = .loading
  /// Whether the most recently observed sync phase was `.failed`, so `reload()`
  /// can tell "no content because sync failed" apart from the ordinary
  /// "no content, sync is fine".
  private var lastSyncFailed = false

  private let coordinator: StepSyncCoordinator

  init(coordinator: StepSyncCoordinator) {
    self.coordinator = coordinator
  }

  /// This month's parameters when ready, for the view and tests to read directly.
  var parameters: MarimoParameters? {
    if case .ready(let parameters) = phase { return parameters }
    return nil
  }

  /// Mirrors the shared sync lifecycle into this section's own phase.
  ///
  /// Driven by the owner (`StepSyncModel`) so the marimo shows the import progress
  /// in its own area without itself triggering a sync:
  /// - `.loading` / `.backfilling` reflect straight through.
  /// - `.ready` / `.empty` / `.failed` all recompute this month's marimo from the
  ///   cache; `reload()` then decides `.ready` vs `.empty` vs `.failed`, so a
  ///   `.failed` turn with a readable cache still renders it.
  func observe(_ syncPhase: StepSyncModel.Phase) async {
    switch syncPhase {
    case .loading:
      phase = .loading
    case .backfilling(let completed, let total):
      phase = .backfilling(completedDays: completed, totalDays: total)
    case .ready, .empty:
      lastSyncFailed = false
      reload()
    case .failed:
      lastSyncFailed = true
      reload()
    }
  }

  /// Recomputes this month's marimo from the cached logs (no sync).
  ///
  /// Whether "no marimo to draw" reads as the ordinary empty state or a failed
  /// one depends on whether this turn's sync actually succeeded —
  /// `lastSyncFailed` is how `observe(_:)` communicates that. A local read
  /// failure is always `.failed`, regardless of `lastSyncFailed`.
  func reload() {
    do {
      if let parameters = try coordinator.growingMarimo() {
        phase = .ready(parameters)
      } else {
        phase = lastSyncFailed ? .failed : .empty
      }
    } catch {
      phase = .failed
    }
  }
}
