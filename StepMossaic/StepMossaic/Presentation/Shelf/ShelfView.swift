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

  /// Adaptive columns: as many ~96pt thumbnails as fit, so the grid scales from
  /// iPhone to iPad without a fixed column count.
  private let columns = [GridItem(.adaptive(minimum: 96), spacing: 16)]

  init(model: ShelfViewModel, syncModel: StepSyncModel) {
    _model = State(initialValue: model)
    _syncModel = State(initialValue: syncModel)
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
    }
  }

  private func grid(_ marimos: [FrozenMarimo]) -> some View {
    ScrollView {
      // `LazyVGrid` builds only the cells near the viewport, so each marimo's
      // Canvas draw happens on demand rather than all at once — the whole shelf can
      // scroll however far back without rendering off-screen months.
      LazyVGrid(columns: columns, spacing: 20) {
        ForEach(marimos, id: \.yearMonth.storageKey) { marimo in
          ShelfMarimoThumbnail(marimo: marimo)
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
  }
}

#Preview("Empty shelf") {
  let environment = AppEnvironment(modelContainer: try! AppModelContainer.make(inMemory: true))
  ShelfView(model: environment.makeShelfViewModel(), syncModel: environment.syncModel)
}
