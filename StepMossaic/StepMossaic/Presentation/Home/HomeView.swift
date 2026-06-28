import SwiftUI

struct HomeView: View {
  @State private var model: HomeViewModel
  @State private var syncModel: StepSyncModel
  @State private var marimoModel: GrowingMarimoViewModel
  @State private var heatmapModel: HeatmapViewModel

  init(
    model: HomeViewModel,
    syncModel: StepSyncModel,
    marimoModel: GrowingMarimoViewModel,
    heatmapModel: HeatmapViewModel
  ) {
    _model = State(initialValue: model)
    _syncModel = State(initialValue: syncModel)
    _marimoModel = State(initialValue: marimoModel)
    _heatmapModel = State(initialValue: heatmapModel)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          todaySection
          GrowingMarimoView(model: marimoModel)
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
    // Own the single cache sync here and fan its shared phase out to each
    // cache-backed section, so the sections render one sync rather than each
    // racing its own backfill.
    .task { await syncModel.start() }
    .task(id: syncModel.observationKey) { await heatmapModel.observe(syncModel.phase) }
    .task(id: syncModel.observationKey) { await marimoModel.observe(syncModel.phase) }
    // The sync above runs before access is granted. When the user grants it from
    // the prompt, re-sync so the cache backfills instead of staying on the empty
    // state until the next launch.
    .onChange(of: model.phase) { oldPhase, newPhase in
      guard oldPhase == .needsAuthorization, newPhase == .ready else { return }
      Task { await syncModel.start() }
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
    syncModel: environment.syncModel,
    marimoModel: environment.makeGrowingMarimoViewModel(),
    heatmapModel: environment.makeHeatmapViewModel()
  )
}
