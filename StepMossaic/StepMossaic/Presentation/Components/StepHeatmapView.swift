import StepMossaicDomain
import SwiftUI

/// Renders the Home heatmap: a weekday-aligned grid of daily cells with
/// cumulative and average step figures, a range selector, tap-to-inspect day
/// detail, and backfill/empty states.
struct StepHeatmapView: View {
  @State private var model: HeatmapViewModel
  /// The day whose detail popover is open, if any.
  @State private var selection: DaySelection?

  init(model: HeatmapViewModel) {
    _model = State(initialValue: model)
  }

  /// Wraps the tapped cell so a single popover can key off the selected day.
  private struct DaySelection: Identifiable {
    let cell: StepHeatmapCell
    var id: Date { cell.day.start }
  }

  /// Measured width of the section, used to size cells so the 3-month range fits.
  @State private var availableWidth: CGFloat = 0

  private let cellSpacing: CGFloat = 4
  /// Left axis width reserved for weekday labels.
  private let weekdayAxisWidth: CGFloat = 18
  /// Height reserved above each week column for its month label.
  private let monthLabelHeight: CGFloat = 12

  /// Cell edge sized so the reference (3-month) span exactly fills the available
  /// width: shorter ranges leave a margin, longer ones scroll horizontally.
  private var cellSize: CGFloat {
    let columns = max(model.referenceColumnCount, 1)
    guard availableWidth > 0 else { return 22 }
    let scrollWidth = availableWidth - weekdayAxisWidth - cellSpacing
    let size = (scrollWidth - CGFloat(columns - 1) * cellSpacing) / CGFloat(columns)
    return max(10, min(28, size))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      content
    }
    .background {
      GeometryReader { proxy in
        Color.clear
          .onAppear { availableWidth = proxy.size.width }
          .onChange(of: proxy.size.width) { _, newValue in availableWidth = newValue }
      }
    }
  }

  @ViewBuilder
  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(model.range.displayTitle)
        .font(.headline)

      Spacer()

      if let heatmap = model.heatmap {
        Text("\(averageText(heatmap)) avg")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch model.phase {
    case .loading:
      loadingGrid
    case .backfilling(let completed, let total):
      backfillProgress(completed: completed, total: total)
    case .ready(let heatmap):
      calendarGrid
      footer(heatmap)
    case .empty:
      emptyState
    }
  }

  /// The weekday-aligned grid: columns are weeks (oldest left), rows are weekdays.
  /// Scrolls horizontally, opening on the most recent week.
  private var calendarGrid: some View {
    HStack(alignment: .top, spacing: cellSpacing) {
      weekdayAxis
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: cellSpacing) {
          ForEach(model.weeks) { week in
            weekColumn(week)
          }
        }
      }
      // Open on the most recent week rather than the oldest, so today is visible.
      .defaultScrollAnchor(.trailing)
    }
  }

  /// Left axis labelling alternating weekday rows, aligned past the month-label row.
  private var weekdayAxis: some View {
    VStack(spacing: cellSpacing) {
      Color.clear.frame(width: weekdayAxisWidth, height: monthLabelHeight)
      ForEach(Array(model.orderedWeekdaySymbols.enumerated()), id: \.offset) { row, symbol in
        // Label every other row to stay legible at this cell size.
        Text(row.isMultiple(of: 2) ? "" : symbol)
          .font(.system(size: 9))
          .foregroundStyle(.secondary)
          .frame(width: weekdayAxisWidth, height: cellSize, alignment: .trailing)
      }
    }
  }

  private func weekColumn(_ week: HeatmapWeek) -> some View {
    VStack(spacing: cellSpacing) {
      Text(week.monthLabel ?? "")
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
        .frame(width: cellSize, height: monthLabelHeight, alignment: .leading)
      ForEach(week.slots) { slot in
        slotView(slot)
      }
    }
  }

  @ViewBuilder
  private func slotView(_ slot: HeatmapSlot) -> some View {
    switch slot {
    case .padding:
      Color.clear.frame(width: cellSize, height: cellSize)
    case .day(let cell):
      dayCell(cell)
    }
  }

  private func dayCell(_ cell: StepHeatmapCell) -> some View {
    RoundedRectangle(cornerRadius: 3)
      .fill(cell.state.fill(positiveLevelCount: model.positiveLevelCount))
      .frame(width: cellSize, height: cellSize)
      // Make the whole cell square the hit area, not just the filled shape.
      .contentShape(Rectangle())
      .onTapGesture { selection = DaySelection(cell: cell) }
      .popover(
        isPresented: Binding(
          get: { selection?.id == cell.day.start },
          set: { isPresented in if !isPresented { selection = nil } }
        )
      ) {
        dayDetail(cell)
          .presentationCompactAdaptation(.popover)
      }
  }

  private func dayDetail(_ cell: StepHeatmapCell) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(cell.day.start, format: .dateTime.year().month(.abbreviated).day())
        .font(.caption)
        .foregroundStyle(.secondary)
      switch cell.state {
      case .available(let steps, _):
        Text("\(steps.formatted()) steps")
          .font(.headline)
      case .unavailable:
        Text("No data")
          .font(.headline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(12)
  }

  private func footer(_ heatmap: StepHeatmap) -> some View {
    HStack {
      Text("\(heatmap.totalSteps.formatted()) total")
      Spacer()
      rangePicker
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  private var rangePicker: some View {
    Picker(
      "Range",
      selection: Binding(
        get: { model.range },
        set: { newRange in Task { await model.selectRange(newRange) } }
      )
    ) {
      ForEach(HeatmapRange.allCases) { range in
        Text(range.shortTitle).tag(range)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .fixedSize()
  }

  private func backfillProgress(completed: Int, total: Int) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      // Guard a zero denominator before any progress is reported.
      ProgressView(value: Double(completed), total: Double(max(total, 1)))
      Text("Importing your step history…")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var loadingGrid: some View {
    HStack(alignment: .top, spacing: cellSpacing) {
      ForEach(0..<8, id: \.self) { _ in
        VStack(spacing: cellSpacing) {
          ForEach(0..<7, id: \.self) { _ in
            RoundedRectangle(cornerRadius: 3)
              .fill(Color.secondary.opacity(0.12))
              .frame(width: cellSize, height: cellSize)
          }
        }
      }
    }
    .redacted(reason: .placeholder)
  }

  private var emptyState: some View {
    Text("No step data yet. Take a walk and it'll show up here.")
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
  }

  private func averageText(_ heatmap: StepHeatmap) -> String {
    Int(heatmap.averageStepsPerAvailableDay.rounded()).formatted()
  }
}
