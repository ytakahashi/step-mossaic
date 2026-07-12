import StepMossaicDomain
import SwiftUI

/// The Home "this month" marimo area: just the growing marimo, sized to fill the
/// space the layout gives it.
///
/// The month's step total and any label live in the Home header now, so this view
/// is only the drawing (or the import/empty states), kept square and centered so a
/// small month still reads clearly without wasted side margin.
struct GrowingMarimoView: View {
  @State private var model: GrowingMarimoViewModel
  let onRetry: () -> Void

  init(model: GrowingMarimoViewModel, onRetry: @escaping () -> Void) {
    _model = State(initialValue: model)
    self.onRetry = onRetry
  }

  var body: some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private var content: some View {
    switch model.phase {
    case .loading, .backfilling:
      placeholder
    case .ready(let parameters):
      MarimoView(parameters: parameters)
        // Square and centered: fills the smaller of the available width/height, so
        // the marimo is as large as the area allows without distorting.
        .aspectRatio(1, contentMode: .fit)
        // A little breathing room outside the marimo so it never touches the edges.
        .padding(8)
        // Interpolate as the month grows rather than snapping on each sync.
        .animation(.easeInOut(duration: 0.4), value: parameters)
        .accessibilityIdentifier("home.marimo.content")
    case .empty:
      emptyState
    case .failed:
      failedState
    }
  }

  /// A faint stand-in while the cache is still loading or backfilling.
  private var placeholder: some View {
    Circle()
      .fill(Color.secondary.opacity(0.12))
      .aspectRatio(1, contentMode: .fit)
      .padding(24)
      .redacted(reason: .placeholder)
  }

  private var emptyState: some View {
    VStack(spacing: 4) {
      Text("Take a walk and this month's marimo starts to grow.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("home.marimo.emptyState")
      // This state is indistinguishable from a denied Health read: HealthKit
      // never reveals denial for read access, so "granted but genuinely no
      // steps yet" and "denied" both settle here forever. The hint costs
      // nothing for the ordinary new-user case and is the only recovery path
      // for the denied one, since Settings is where access can actually be
      // changed (see `SettingsView`'s `.requested` case).
      Text("Steps not showing up? Check Health access in Settings.")
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .accessibilityIdentifier("home.marimo.emptyState.healthAccessHint")
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
    .padding()
  }

  /// Shown when the sync failed and there is no cached month to draw instead.
  private var failedState: some View {
    VStack(spacing: 8) {
      Text("Step data couldn't be loaded.")
        .font(.subheadline)
      Text("Your Health data is not affected.")
        .font(.caption)
        .foregroundStyle(.secondary)
      Button("Try Again", action: onRetry)
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
    .padding()
  }
}
