import SwiftUI

struct HomeView: View {
  @State private var model: HomeViewModel

  init(model: HomeViewModel) {
    _model = State(initialValue: model)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          todaySection
          GrowingMarimoPlaceholder()
          HeatmapPlaceholder(title: "Last 3 months")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
      }
      .navigationTitle("Step Mossaic")
    }
    // Resolve the phase once on appear, then (re)run the live loop whenever the
    // phase changes; `.task(id:)` cancels the loop on disappear or phase change.
    .task { model.refreshPhase() }
    .task(id: model.phase) { await model.activate() }
  }

  @ViewBuilder
  private var todaySection: some View {
    switch model.phase {
    case .loading:
      TodayStepsCard(steps: model.todaySteps ?? 0)
        .redacted(reason: .placeholder)
    case .ready:
      TodayStepsCard(steps: model.todaySteps ?? 0)
    case .needsAuthorization:
      authorizationPrompt
    case .unavailable:
      Text("Health data isn't available on this device.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private var authorizationPrompt: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Connect Health to see your steps.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Button("Allow Health Access") {
        Task { await model.requestAccess() }
      }
      .buttonStyle(.borderedProminent)
    }
  }
}

#Preview {
  HomeView(model: HomeViewModel())
}
