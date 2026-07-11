import Foundation
import Observation
import StepMossaicDomain

/// Selectable span the heatmap displays, anchored at today.
enum HeatmapRange: CaseIterable, Identifiable, Sendable {
  case month
  case threeMonths
  case year

  var id: Self { self }

  /// Calendar months the span reaches back from today.
  private var monthsBack: Int {
    switch self {
    case .month: 1
    case .threeMonths: 3
    case .year: 12
    }
  }

  var shortTitle: String {
    switch self {
    case .month: "1M"
    case .threeMonths: "3M"
    case .year: "1Y"
    }
  }

  var displayTitle: String {
    switch self {
    case .month: "Last month"
    case .threeMonths: "Last 3 months"
    case .year: "Last year"
    }
  }

  /// The display interval ending today, reaching back `monthsBack` months.
  ///
  /// The start is shifted one day past the month boundary so the window length is
  /// the span itself rather than the span plus the anchor day.
  func interval(endingAt today: Day, calendar: Calendar) -> DayInterval {
    let monthBoundary = calendar.date(byAdding: .month, value: -monthsBack, to: today.start)!
    let start = Day(containing: monthBoundary, calendar: calendar).adding(
      days: 1, calendar: calendar)
    return DayInterval(start: start, end: today)
  }
}

/// Drives the Home heatmap: renders the stored daily totals over the selected
/// range as an aggregated `StepHeatmap`.
///
/// Cache-render only — it does not own the sync. `StepSyncModel` owns the single
/// sync lifecycle; this model mirrors that shared phase via `observe(_:)` and
/// reads the cache once sync settles. Aggregation itself lives in
/// `StepHeatmapGenerator`; this model wires the store reads and display range to
/// it, exposing a single `phase` for the view to switch on.
@MainActor
@Observable
final class HeatmapViewModel {
  /// What the heatmap section should present.
  enum Phase: Equatable {
    /// Resolving the first load (or a quick differential sync).
    case loading
    /// Initial backfill in flight; `completedDays` advances toward `totalDays`.
    case backfilling(completedDays: Int, totalDays: Int)
    /// Aggregated heatmap ready to draw.
    case ready(StepHeatmap)
    /// Sync finished but no step data exists at all.
    case empty
  }

  private(set) var phase: Phase = .loading
  private(set) var range: HeatmapRange = .threeMonths

  private let coordinator: StepSyncCoordinator
  private let stepLogStore: any StepLogStore
  private let calendar: Calendar
  private let levelScale: StepLevelScale
  private let today: @MainActor () -> Date

  init(
    coordinator: StepSyncCoordinator,
    stepLogStore: any StepLogStore,
    calendar: Calendar,
    levelScale: StepLevelScale = StepLevelScale(),
    today: @escaping @MainActor () -> Date
  ) {
    self.coordinator = coordinator
    self.stepLogStore = stepLogStore
    self.calendar = calendar
    self.levelScale = levelScale
    self.today = today
  }

  /// Positive levels the cells can rank into, so the view can map a level to a
  /// shade without knowing the scale.
  var positiveLevelCount: Int { levelScale.positiveLevelCount }

  /// The aggregated heatmap when ready, for the view and tests to read directly.
  var heatmap: StepHeatmap? {
    if case .ready(let heatmap) = phase { return heatmap }
    return nil
  }

  /// The ready heatmap laid out into weekday-aligned week rows for drawing;
  /// empty until ready.
  var weeks: [HeatmapWeek] {
    guard let heatmap else { return [] }
    return HeatmapLayout.weeks(for: heatmap.cells, calendar: calendar)
  }

  /// Week-column count of the 3-month range, used by the view as the reference
  /// span to size cells to, so three months fit without horizontal scrolling.
  var referenceColumnCount: Int {
    let todayDay = Day(containing: today(), calendar: calendar)
    let interval = HeatmapRange.threeMonths.interval(endingAt: todayDay, calendar: calendar)
    return HeatmapLayout.weekCount(for: interval, calendar: calendar)
  }

  /// Single-letter weekday labels ordered from the calendar's `firstWeekday`, so
  /// the grid's row axis matches the column layout.
  var orderedWeekdaySymbols: [String] { calendar.orderedVeryShortWeekdaySymbols }

  /// Mirrors the shared sync lifecycle into this section's own phase.
  ///
  /// Driven by the owner (`StepSyncModel`) so the heatmap shows the import progress
  /// in its own area without itself triggering a sync:
  /// - `.loading` / `.backfilling` reflect straight through.
  /// - `.ready` / `.empty` re-render from the cache; `reload()` then decides
  ///   `.ready` vs `.empty` from coverage, staying consistent with the owner.
  /// - `.failed` currently reads the same as `.loading`; a dedicated failed
  ///   presentation that keeps showing the last-good cache lands separately.
  func observe(_ syncPhase: StepSyncModel.Phase) async {
    switch syncPhase {
    case .loading, .failed:
      phase = .loading
    case .backfilling(let completed, let total):
      phase = .backfilling(completedDays: completed, totalDays: total)
    case .ready, .empty:
      await reload()
    }
  }

  /// Switches the displayed range and re-renders from the cache (no re-sync).
  func selectRange(_ range: HeatmapRange) async {
    guard range != self.range else { return }
    self.range = range
    await reload()
  }

  /// Rebuilds the heatmap for the current range from the cached logs and coverage.
  func reload() async {
    do {
      let coverage = try coordinator.coverage()
      // No first available day means no step data has ever existed: show the empty
      // state rather than a grid of unavailable cells.
      guard coverage.firstAvailableDay != nil else {
        phase = .empty
        return
      }

      let interval = range.interval(
        endingAt: Day(containing: today(), calendar: calendar), calendar: calendar)
      let logs = try stepLogStore.logs(in: interval)
      let stepsByDay = Dictionary(uniqueKeysWithValues: logs.map { ($0.day, $0.steps) })

      phase = .ready(
        StepHeatmapGenerator.heatmap(
          for: interval,
          stepsByDay: stepsByDay,
          coverage: coverage,
          calendar: calendar,
          levelScale: levelScale
        )
      )
    } catch {
      phase = .empty
    }
  }
}
