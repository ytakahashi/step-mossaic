import Foundation
import Observation
import StepMossaicDomain

/// Drives the shelf: the frozen monthly marimos, newest month first.
///
/// Cache-render only — it does not own the sync. `StepSyncModel` owns the single
/// sync lifecycle (and the frozen-marimo reconciliation that runs as it settles);
/// this model mirrors that shared phase via `observe(_:)` and reads the persisted
/// snapshots, exactly like `HeatmapViewModel` and `GrowingMarimoViewModel`.
@MainActor
@Observable
final class ShelfViewModel {
  /// What the shelf should present.
  enum Phase: Equatable {
    /// Resolving the first load (or a quick differential sync). The shelf shows a
    /// redacted grid rather than the heatmap's import progress bar, since the
    /// monuments simply appear once they exist.
    case loading
    /// Frozen marimos to display, newest month first.
    case ready([FrozenMarimo])
    /// Sync settled but no month has been frozen yet (e.g. only the current,
    /// still-growing month has data).
    case empty
  }

  private(set) var phase: Phase = .loading

  private let marimoStore: any MarimoStore

  init(marimoStore: any MarimoStore) {
    self.marimoStore = marimoStore
  }

  /// The frozen marimos when ready, for the view and tests to read directly.
  var marimos: [FrozenMarimo] {
    if case .ready(let marimos) = phase { return marimos }
    return []
  }

  /// Mirrors the shared sync lifecycle into this section's own phase.
  ///
  /// - `.loading` / `.backfilling` both show the redacted grid: the shelf has no
  ///   per-section progress, so an in-flight backfill reads the same as a first
  ///   load.
  /// - `.ready` / `.empty` reload the frozen snapshots from the store.
  func observe(_ syncPhase: StepSyncModel.Phase) async {
    switch syncPhase {
    case .loading, .backfilling:
      phase = .loading
    case .ready, .empty:
      reload()
    }
  }

  /// Rebuilds the shelf from the persisted frozen marimos (no sync).
  ///
  /// `.ready` vs `.empty` is decided by the snapshots, not the sync phase: a
  /// settled-with-data cache whose only month is the current growing one has no
  /// frozen monument yet, so the shelf is still empty. A read failure also surfaces
  /// as `.empty`, like the other cache-backed sections.
  func reload() {
    do {
      // `allFrozen()` is chronological; reverse so the newest month leads the shelf.
      let marimos = Array(try marimoStore.allFrozen().reversed())
      phase = marimos.isEmpty ? .empty : .ready(marimos)
    } catch {
      phase = .empty
    }
  }
}
