import StepMossaicDomain
import SwiftUI

/// The Home "this month" section: a header, the growing marimo, and the month's
/// step total — or the import/empty states while there's nothing to draw yet.
struct GrowingMarimoView: View {
  @State private var model: GrowingMarimoViewModel

  init(model: GrowingMarimoViewModel) {
    _model = State(initialValue: model)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("This month")
        .font(.headline)
      content
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }
  }

  @ViewBuilder
  private var content: some View {
    switch model.phase {
    case .loading, .backfilling:
      placeholder
    case .ready(let parameters):
      VStack(spacing: 10) {
        MarimoView(parameters: parameters)
          .frame(height: 168)
          // Interpolate as the month grows: a settled differential sync that nudges
          // the parameters animates rather than snapping.
          .animation(.easeInOut(duration: 0.4), value: parameters)
        Text("\(parameters.totalSteps.formatted()) steps")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    case .empty:
      emptyState
    }
  }

  /// A faint stand-in while the cache is still loading or backfilling.
  private var placeholder: some View {
    Circle()
      .fill(Color.secondary.opacity(0.12))
      .frame(width: 150, height: 150)
      .redacted(reason: .placeholder)
  }

  private var emptyState: some View {
    Text("Take a walk and this month's marimo starts to grow.")
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
