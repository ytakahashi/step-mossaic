import StepMossaicDomain
import SwiftUI

/// The month detail presented as a bottom sheet when a shelf marimo is tapped:
/// the month's frozen marimo at full fidelity, its total and daily-average steps,
/// and the month's heatmap.
///
/// Kept as a single-marimo surface (like Home) so the full-quality `MarimoView`
/// only ever renders one at a time, while the shelf grid stays on cheap
/// thumbnails. The heatmap reuses `HeatmapGrid`, so the day shading matches Home.
struct MonthDetailSheet: View {
  let marimo: FrozenMarimo
  /// The month's heatmap detail, or `nil` if it could not be built — the sheet then
  /// shows the marimo alone rather than an error.
  let detail: MonthDetail?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 24) {
          // Full fidelity here, where the marimo is large enough for the texture to
          // read — the one place a frozen month is shown at full size.
          MarimoView(parameters: marimo.parameters)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 220)

          if let detail {
            stats(detail)
            // The month always fits, so the grid lays out inline and centers rather
            // than scrolling and pinning to the trailing edge like Home.
            HeatmapGrid(
              weeks: detail.weeks,
              orderedWeekdaySymbols: detail.orderedWeekdaySymbols,
              positiveLevelCount: detail.positiveLevelCount,
              referenceColumnCount: detail.referenceColumnCount,
              scrolls: false
            )
          }
        }
        .padding()
      }
      .navigationTitle(monthTitle)
      .navigationBarTitleDisplayMode(.inline)
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    .accessibilityIdentifier("shelf.monthDetail.sheet")
  }

  private func stats(_ detail: MonthDetail) -> some View {
    HStack(alignment: .top) {
      StepStat(title: "Total", steps: detail.totalSteps)
      StepStat(
        title: "Daily average",
        steps: Int(detail.averageStepsPerAvailableDay.rounded()))
    }
  }

  /// The month as a localized "Month Year" heading (e.g. "June 2026").
  ///
  /// `YearMonth` is a Gregorian storage key, so reconstruct and format through a
  /// Gregorian calendar even when the user's current calendar is non-Gregorian.
  private var monthTitle: String {
    let calendar = Calendar.current.stepMossaicGregorian

    var components = DateComponents()
    components.calendar = calendar
    components.year = marimo.yearMonth.year
    components.month = marimo.yearMonth.month
    components.day = 1
    let date = calendar.date(from: components) ?? .now

    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = calendar.locale ?? .current
    formatter.timeZone = calendar.timeZone
    formatter.setLocalizedDateFormatFromTemplate("yMMMM")
    return formatter.string(from: date)
  }
}
