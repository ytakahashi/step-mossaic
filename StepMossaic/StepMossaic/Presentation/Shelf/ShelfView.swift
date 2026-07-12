import StepMossaicDomain
import SwiftUI

/// The shelf tab: a vertically scrolling grid of frozen monthly marimos, newest
/// month first.
///
/// Renders from the cache only. The sync is owned by `HomeView` via the shared
/// `StepSyncModel`; this view subscribes to that shared lifecycle so the shelf
/// fills in (and refreshes after a month rolls over) without driving its own sync.
struct ShelfView: View {
  @State private var model: ShelfViewModel
  @State private var syncModel: StepSyncModel
  /// The month whose detail sheet is open, if any.
  @State private var selection: MonthSelection?

  /// Adaptive columns: as many ~96pt thumbnails as fit, so the grid scales from
  /// iPhone to iPad without a fixed column count.
  private let columns = [GridItem(.adaptive(minimum: 96), spacing: 16)]

  init(model: ShelfViewModel, syncModel: StepSyncModel) {
    _model = State(initialValue: model)
    _syncModel = State(initialValue: syncModel)
  }

  /// Wraps the tapped month so `sheet(item:)` can key off it; the marimo carries
  /// its own month identity.
  private struct MonthSelection: Identifiable {
    let marimo: FrozenMarimo
    var id: String { marimo.yearMonth.storageKey }
  }

  var body: some View {
    NavigationStack {
      content
        .navigationTitle("Shelf")
    }
    // Reflect the shared sync lifecycle: the key changes for both phase transitions
    // and same-phase differential completions, so a newly frozen month appears
    // without the shelf running its own sync.
    .task(id: syncModel.observationKey) { await model.observe(syncModel.phase) }
    .sheet(item: $selection) { selection in
      // The detail is built on selection for the one tapped month; the marimo draws
      // regardless, so a failed heatmap build still shows the monument.
      MonthDetailSheet(
        marimo: selection.marimo,
        detail: model.monthDetail(for: selection.marimo.yearMonth))
    }
  }

  @ViewBuilder
  private var content: some View {
    switch model.phase {
    case .loading:
      loadingGrid
    case .ready(let marimos):
      grid(marimos)
    case .empty:
      emptyState
    case .failed:
      failedState
    }
  }

  private func grid(_ marimos: [FrozenMarimo]) -> some View {
    ScrollView {
      VStack(spacing: 12) {
        if isSyncFailing {
          SyncFailureBanner(onRetry: retrySync)
        }
        // `LazyVGrid` builds only the cells near the viewport, so each marimo's
        // Canvas draw happens on demand rather than all at once — the whole shelf
        // can scroll however far back without rendering off-screen months.
        LazyVGrid(columns: columns, spacing: 20) {
          ForEach(marimos, id: \.yearMonth.storageKey) { marimo in
            Button {
              selection = MonthSelection(marimo: marimo)
            } label: {
              ShelfMarimoThumbnail(marimo: marimo)
            }
            .buttonStyle(.plain)
          }
        }
      }
      .padding()
    }
  }

  /// A faint stand-in grid while the cache is still loading or backfilling.
  private var loadingGrid: some View {
    ScrollView {
      LazyVGrid(columns: columns, spacing: 20) {
        ForEach(0..<6, id: \.self) { _ in
          VStack(spacing: 8) {
            Circle()
              .fill(Color.secondary.opacity(0.12))
              .aspectRatio(1, contentMode: .fit)
              .frame(maxWidth: .infinity)
            Text("0000.00")
              .font(.caption)
          }
        }
      }
      .padding()
    }
    .redacted(reason: .placeholder)
  }

  private var emptyState: some View {
    // Non-blaming, and framed as "later", since the first monument only appears
    // once a month completes.
    Text("Your first month's marimo will settle onto the shelf once the month wraps up.")
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .padding()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityIdentifier("shelf.emptyState")
  }

  /// Shown when the sync failed and there are no frozen months to draw instead.
  private var failedState: some View {
    VStack(spacing: 8) {
      Text("Step data couldn't be loaded.")
        .font(.subheadline)
      Text("Your Health data is not affected.")
        .font(.caption)
        .foregroundStyle(.secondary)
      Button("Try Again", action: retrySync)
    }
    .multilineTextAlignment(.center)
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// Whether the shared sync failed this turn, read directly from `syncModel`
  /// rather than through `model.phase` — the shelf's own phase stays `.ready`
  /// whenever its frozen marimos survive a failed sync, so it alone can't tell
  /// the view whether to show the retry banner.
  private var isSyncFailing: Bool {
    if case .failed = syncModel.phase { true } else { false }
  }

  private func retrySync() {
    Task { await syncModel.retry() }
  }
}

#Preview("Empty shelf") {
  let environment = AppEnvironment(modelContainer: try! AppModelContainer.make(inMemory: true))
  ShelfView(model: environment.makeShelfViewModel(), syncModel: environment.syncModel)
}
