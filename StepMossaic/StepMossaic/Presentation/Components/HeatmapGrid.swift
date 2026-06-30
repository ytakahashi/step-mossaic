import StepMossaicDomain
import SwiftUI

/// The weekday-aligned heatmap grid, with tap-to-inspect day detail — and nothing
/// else (no header, range selector, or sync).
///
/// Pure presentation over already-laid-out weeks, so it is shared by the Home
/// heatmap section and the shelf's month detail without coupling either to the
/// other's chrome. The owner supplies the weeks, the weekday axis labels, the
/// palette's positive-level count, and the reference column span the cells size to.
struct HeatmapGrid: View {
  let weeks: [HeatmapWeek]
  /// Single-letter weekday labels, ordered from the calendar's `firstWeekday`.
  let orderedWeekdaySymbols: [String]
  /// Positive levels a cell can rank into, so a level maps to a shade without the
  /// grid knowing the scale.
  let positiveLevelCount: Int
  /// Week-column count the cells size to: this span exactly fills the width, so a
  /// shorter span leaves a margin and a longer one scrolls horizontally.
  let referenceColumnCount: Int
  /// Whether the grid scrolls horizontally. Home scrolls so a multi-month range can
  /// reach back past the width and open on the latest week. A single month always
  /// fits, so the month detail turns this off to lay the grid out inline and center
  /// it, instead of clinging to the trailing edge.
  var scrolls = true

  /// The day whose detail popover is open, if any.
  @State private var selection: DaySelection?
  /// Measured width of the grid, used to size cells to the reference span.
  @State private var availableWidth: CGFloat = 0

  private let cellSpacing: CGFloat = 4
  /// Left axis width reserved for weekday labels.
  private let weekdayAxisWidth: CGFloat = 18
  /// Height reserved above each week column for its month label.
  private let monthLabelHeight: CGFloat = 12

  /// Wraps the tapped cell so a single popover can key off the selected day.
  private struct DaySelection: Identifiable {
    let cell: StepHeatmapCell
    var id: Date { cell.day.start }
  }

  /// Cell edge sized so the reference span exactly fills the available width:
  /// shorter ranges leave a margin, longer ones scroll horizontally.
  private var cellSize: CGFloat {
    let columns = max(referenceColumnCount, 1)
    guard availableWidth > 0 else { return 22 }
    let scrollWidth = availableWidth - weekdayAxisWidth - cellSpacing
    let size = (scrollWidth - CGFloat(columns - 1) * cellSpacing) / CGFloat(columns)
    return max(10, min(28, size))
  }

  var body: some View {
    calendarGrid
      .background {
        GeometryReader { proxy in
          Color.clear
            .onAppear { availableWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, newValue in availableWidth = newValue }
        }
      }
  }

  /// The weekday-aligned grid: columns are weeks (oldest left), rows are weekdays.
  private var calendarGrid: some View {
    HStack(alignment: .top, spacing: cellSpacing) {
      weekdayAxis
      if scrolls {
        ScrollView(.horizontal, showsIndicators: false) {
          weekColumns
        }
        // Open on the most recent week rather than the oldest, so today is visible.
        .defaultScrollAnchor(.trailing)
      } else {
        weekColumns
      }
    }
    // A scrolling range fills the width; a non-scrolling month centers its compact
    // grid (axis kept adjacent to the columns) instead of pinning to one edge.
    .frame(maxWidth: .infinity, alignment: scrolls ? .leading : .center)
  }

  private var weekColumns: some View {
    HStack(alignment: .top, spacing: cellSpacing) {
      ForEach(weeks) { week in
        weekColumn(week)
      }
    }
  }

  /// Left axis labelling alternating weekday rows, aligned past the month-label row.
  private var weekdayAxis: some View {
    VStack(spacing: cellSpacing) {
      Color.clear.frame(width: weekdayAxisWidth, height: monthLabelHeight)
      ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { row, symbol in
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
      .fill(cell.state.fill(positiveLevelCount: positiveLevelCount))
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
}
