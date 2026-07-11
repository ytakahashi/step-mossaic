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
  private let stepLogStore: any StepLogStore
  private let coordinator: StepSyncCoordinator
  private let calendar: Calendar
  private let levelScale: StepLevelScale

  init(
    marimoStore: any MarimoStore,
    stepLogStore: any StepLogStore,
    coordinator: StepSyncCoordinator,
    calendar: Calendar,
    levelScale: StepLevelScale = StepLevelScale()
  ) {
    self.marimoStore = marimoStore
    self.stepLogStore = stepLogStore
    self.coordinator = coordinator
    self.calendar = calendar
    self.levelScale = levelScale
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
  /// - `.failed` currently reads the same as `.loading`; a dedicated failed
  ///   presentation that keeps showing the last-good shelf lands separately.
  func observe(_ syncPhase: StepSyncModel.Phase) async {
    switch syncPhase {
    case .loading, .backfilling, .failed:
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

  /// Builds the heatmap detail for a tapped month, drawn alongside its frozen
  /// marimo in the detail sheet.
  ///
  /// Computed on demand for the one selected month (cheap, one month of logs) from
  /// the same cache and coverage the Home heatmap reads, so the day shading,
  /// total, and average match. Returns `nil` on a read failure, so the sheet falls
  /// back to showing the marimo alone rather than surfacing an error.
  func monthDetail(for yearMonth: YearMonth) -> MonthDetail? {
    do {
      let coverage = try coordinator.coverage()
      let interval = yearMonth.interval(calendar: calendar)
      let logs = try stepLogStore.logs(in: interval)
      let stepsByDay = Dictionary(uniqueKeysWithValues: logs.map { ($0.day, $0.steps) })
      let heatmap = StepHeatmapGenerator.heatmap(
        for: interval,
        stepsByDay: stepsByDay,
        coverage: coverage,
        calendar: calendar,
        levelScale: levelScale
      )
      return MonthDetail(
        weeks: HeatmapLayout.weeks(for: heatmap.cells, calendar: calendar),
        orderedWeekdaySymbols: calendar.orderedVeryShortWeekdaySymbols,
        positiveLevelCount: levelScale.positiveLevelCount,
        referenceColumnCount: HeatmapLayout.weekCount(for: interval, calendar: calendar),
        totalSteps: heatmap.totalSteps,
        averageStepsPerAvailableDay: heatmap.averageStepsPerAvailableDay
      )
    } catch {
      return nil
    }
  }
}

/// The heatmap figures and layout for a single month, ready for the detail sheet
/// to render through `HeatmapGrid` without recomputing aggregation or layout.
struct MonthDetail {
  let weeks: [HeatmapWeek]
  let orderedWeekdaySymbols: [String]
  let positiveLevelCount: Int
  let referenceColumnCount: Int
  let totalSteps: Int
  let averageStepsPerAvailableDay: Double
}
