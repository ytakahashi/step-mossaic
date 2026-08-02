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
      content
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
    // racing its own backfill. Gated on Health access being resolved: syncing
    // beforehand always fails (no permission to read yet), which would surface
    // as a misleading "Step data couldn't be loaded" error, so the sync — and
    // the sections that mirror its phase — simply don't run until `.ready`.
    .task(id: model.phase) {
      guard model.phase == .ready else { return }
      await syncModel.start()
    }
    // Keep the cache fresh while foregrounded after Health access is resolved:
    // live step ticks run a differential sync, so "This month" and the marimo
    // grow mid-session rather than only on launch/foreground re-entry.
    .task(id: model.phase) {
      guard model.phase == .ready else { return }
      await syncModel.observeLiveUpdates()
    }
    .task(id: syncModel.observationKey) { await heatmapModel.observe(syncModel.phase) }
    .task(id: syncModel.observationKey) { await marimoModel.observe(syncModel.phase) }
  }

  /// The whole screen, switched on the authorization phase.
  ///
  /// The unresolved and unavailable phases replace the screen rather than just the
  /// today figure: neither has step data behind it, so the stats/marimo/heatmap
  /// stack has nothing to render, and each of those phases has its own thing to
  /// say about why (see `HealthAccessRequestView` and `healthUnavailableState`).
  @ViewBuilder
  private var content: some View {
    switch model.phase {
    case .needsAuthorization:
      HealthAccessRequestView { await model.requestAccess() }
    case .unavailable:
      healthUnavailableState
    case .loading, .ready:
      liveContent
    }
  }

  /// The step-data screen itself. No outer scroll: the marimo area absorbs the
  /// leftover height so the whole screen — stats, marimo, heatmap — fits without
  /// scrolling.
  private var liveContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      // Sync is gated on authorization being resolved: syncing before access is
      // granted is doomed to fail, and surfacing that as a "Step data couldn't be
      // loaded" error is misleading — nothing is broken. `content` routes the
      // unresolved phase away from here entirely, so these sections only ever
      // render once there is something real behind them.
      if model.phase == .ready {
        if isSyncFailing, hasCachedHomeContent {
          SyncFailureBanner(onRetry: retrySync)
        }
        GrowingMarimoView(model: marimoModel, onRetry: retrySync)
        StepHeatmapView(model: heatmapModel, onRetry: retrySync)
      }
    }
  }

  /// Today's and this month's totals, stacked tightly above the marimo.
  private var header: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Redacted while the phase is still resolving, so the figure doesn't flash a
      // zero before the first read lands.
      StepStat(title: "Today", steps: model.todaySteps ?? 0)
        .redacted(reason: model.phase == .loading ? .placeholder : [])
      // This month's total moved here from under the marimo; redacted until the
      // first marimo computation lands so it doesn't flash a zero either.
      if model.phase == .ready {
        StepStat(title: "This month", steps: marimoModel.parameters?.totalSteps ?? 0)
          .redacted(reason: marimoModel.parameters == nil ? .placeholder : [])
      }
    }
  }

  /// Shown where HealthKit itself is missing. Second line names the requirement:
  /// this device will never have step data, which is worth stating outright rather
  /// than leaving the screen looking broken.
  private var healthUnavailableState: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Apple Health isn't available here.")
        .font(.subheadline)
      Text("Step Mossaic needs an iPhone.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier("home.healthUnavailable")
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
