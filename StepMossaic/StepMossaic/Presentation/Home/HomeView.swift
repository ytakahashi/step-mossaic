import SwiftUI

struct HomeView: View {
  @State private var model: HomeViewModel
  @State private var heatmapModel: HeatmapViewModel

  init(model: HomeViewModel, heatmapModel: HeatmapViewModel) {
    _model = State(initialValue: model)
    _heatmapModel = State(initialValue: heatmapModel)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          todaySection
          GrowingMarimoPlaceholder()
          StepHeatmapView(model: heatmapModel)
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
    // The heatmap self-syncs on appear, but that runs before access is granted.
    // When the user grants it from the prompt, re-sync so the heatmap backfills
    // instead of staying on the empty state until the next launch.
    .onChange(of: model.phase) { oldPhase, newPhase in
      guard oldPhase == .needsAuthorization, newPhase == .ready else { return }
      Task { await heatmapModel.start() }
    }
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
  let environment = AppEnvironment(modelContainer: try! AppModelContainer.make(inMemory: true))
  HomeView(
    model: environment.makeHomeViewModel(),
    heatmapModel: environment.makeHeatmapViewModel()
  )
}
