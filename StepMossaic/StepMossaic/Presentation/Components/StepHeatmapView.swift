import StepMossaicDomain
import SwiftUI

/// Renders the Home heatmap: a `HeatmapGrid` of daily cells with cumulative and
/// average step figures, a range selector, and backfill/empty states.
struct StepHeatmapView: View {
  @State private var model: HeatmapViewModel
  let onRetry: () -> Void

  init(model: HeatmapViewModel, onRetry: @escaping () -> Void) {
    _model = State(initialValue: model)
    self.onRetry = onRetry
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      content
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
      HeatmapGrid(
        weeks: model.weeks,
        orderedWeekdaySymbols: model.orderedWeekdaySymbols,
        positiveLevelCount: model.positiveLevelCount,
        referenceColumnCount: model.referenceColumnCount
      )
      .accessibilityIdentifier("home.heatmap.content")
      footer(heatmap)
    case .empty:
      emptyState
    case .failed:
      failedState
    }
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

  /// A faint redacted stand-in while the cache is still loading. A fixed cell edge
  /// is enough here — the placeholder never needs the measured, range-fitted size.
  private var loadingGrid: some View {
    HStack(alignment: .top, spacing: 4) {
      ForEach(0..<8, id: \.self) { _ in
        VStack(spacing: 4) {
          ForEach(0..<7, id: \.self) { _ in
            RoundedRectangle(cornerRadius: 3)
              .fill(Color.secondary.opacity(0.12))
              .frame(width: 22, height: 22)
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
      .accessibilityIdentifier("home.heatmap.emptyState")
  }

  /// Shown when the sync failed and there is no cached range to draw instead.
  private var failedState: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Step data couldn't be loaded.")
        .font(.subheadline)
      Text("Your Health data is not affected.")
        .font(.caption)
        .foregroundStyle(.secondary)
      Button("Try Again", action: onRetry)
    }
    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
  }

  private func averageText(_ heatmap: StepHeatmap) -> String {
    Int(heatmap.averageStepsPerAvailableDay.rounded()).formatted()
  }
}
