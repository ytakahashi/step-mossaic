import StepMossaicDomain
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
      // No outer scroll: the marimo area absorbs the leftover height so the whole
      // screen — stats, marimo, heatmap — fits without scrolling.
      VStack(alignment: .leading, spacing: 16) {
        header
        if isSyncFailing, hasCachedHomeContent {
          SyncFailureBanner(onRetry: retrySync)
        }
        GrowingMarimoView(model: marimoModel, onRetry: retrySync)
        StepHeatmapView(model: heatmapModel, onRetry: retrySync)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .padding()
      .navigationTitle("Step Mossaic")
      .navigationBarTitleDisplayMode(.inline)
    }
    // Resolve the phase once on appear, then (re)run the live loop whenever the
    // phase changes; `.task(id:)` cancels the loop on disappear or phase change.
    .task { model.refreshPhase() }
    .task(id: model.phase) { await model.activate() }
    // Own the single cache sync here and fan its shared phase out to each
    // cache-backed section, so the sections render one sync rather than each
    // racing its own backfill.
    .task { await syncModel.start() }
    // Keep the cache fresh while foregrounded after Health access is resolved:
    // live step ticks run a differential sync, so "This month" and the marimo
    // grow mid-session rather than only on launch/foreground re-entry. Keying by
    // phase recreates the Health observer after the user grants access.
    .task(id: model.phase) {
      guard model.phase == .ready else { return }
      await syncModel.observeLiveUpdates()
    }
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

  /// Today's and this month's totals, stacked tightly above the marimo.
  private var header: some View {
    VStack(alignment: .leading, spacing: 12) {
      todayStat
      // This month's total moved here from under the marimo; redacted until the
      // first marimo computation lands so it doesn't flash a zero.
      StepStat(title: "This month", steps: marimoModel.parameters?.totalSteps ?? 0)
        .redacted(reason: marimoModel.parameters == nil ? .placeholder : [])
    }
  }

  @ViewBuilder
  private var todayStat: some View {
    switch model.phase {
    case .loading:
      StepStat(title: "Today", steps: model.todaySteps ?? 0)
        .redacted(reason: .placeholder)
    case .ready:
      StepStat(title: "Today", steps: model.todaySteps ?? 0)
    case .needsAuthorization:
      authorizationPrompt
    case .unavailable:
      Text("Health data isn't available on this device.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  /// Whether the shared sync failed this turn, read directly from `syncModel`
  /// rather than through either section's own phase — a section's `phase` stays
  /// `.ready` whenever its cached content survives a failed sync, so it alone
  /// can't tell the view whether to show the retry banner.
  private var isSyncFailing: Bool {
    if case .failed = syncModel.phase { true } else { false }
  }

  /// Whether either cache-backed Home section still has content worth keeping
  /// visible. The shared failure banner appears once for the whole screen in
  /// that case; a section without cached content renders its own failed state.
  private var hasCachedHomeContent: Bool {
    if case .ready = marimoModel.phase { return true }
    if case .ready = heatmapModel.phase { return true }
    return false
  }

  private func retrySync() {
    Task { await syncModel.retry() }
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
