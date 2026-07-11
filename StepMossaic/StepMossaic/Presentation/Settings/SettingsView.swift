import StepMossaicDomain
import SwiftUI

/// The Settings tab: Health authorization status/connection, and a destructive
/// cache rebuild.
///
/// Renders from `SettingsViewModel` (Health status/actions) and the shared
/// `StepSyncModel` (rebuild progress) directly — unlike Home/Shelf, Settings
/// only ever reacts to its own explicit actions, so it has no need to observe
/// `syncModel.observationKey` the way those screens passively do.
struct SettingsView: View {
  @State private var model: SettingsViewModel
  @State private var syncModel: StepSyncModel
  @State private var isConfirmingRebuild = false

  init(model: SettingsViewModel, syncModel: StepSyncModel) {
    _model = State(initialValue: model)
    _syncModel = State(initialValue: syncModel)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Health") {
          healthContent
        }

        Section("Setting") {
          settingContent
        }

        Section("Data") {
          rebuildContent
        }
      }
      .navigationTitle("Settings")
    }
    .task { model.refreshStatus() }
    // A plain `.alert` rather than `.confirmationDialog`: on-device the
    // dialog's action-sheet presentation rendered as a small floating bubble
    // anchored oddly above the tab bar rather than a proper bottom sheet.
    // `.alert` is a centered, unambiguous modal regardless of OS version.
    .alert("Rebuild cache?", isPresented: $isConfirmingRebuild) {
      Button("Rebuild", role: .destructive) {
        Task { await model.rebuildCache() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "This deletes your cached step history and re-downloads it from Health. "
          + "Your Health data itself is not affected.")
    }
  }

  @ViewBuilder
  private var healthContent: some View {
    switch model.authorizationStatus {
    case .unavailable:
      Text("Health data isn't available on this device.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    case .notDetermined:
      LabeledContent("Steps", value: "Not connected")
      Button("Connect Health") {
        Task { await model.requestAccess() }
      }
    case .requested:
      // No status value here (not even a neutral one): granted and denied
      // read the same from the API, so any label would either misreport a
      // denial as fine or, once actually granted, sit there looking
      // permanently unresolved. Explaining where the real toggle lives is
      // more useful than a status this screen can't actually know.
      //
      // Kept as its own block, separate from the "Open App Settings" button
      // below: pairing this sentence directly with "Open App Settings" reads
      // as if the button takes you there, but `openHealthSettings()` only
      // opens this app's own Settings.app page, not the Health app.
      Text("Health access is managed in the Health app: Sharing > Apps > Step Mossaic.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var settingContent: some View {
    Button("Open App Settings") {
      model.openHealthSettings()
    }
  }

  @ViewBuilder
  private var rebuildContent: some View {
    Button("Rebuild cache", role: .destructive) {
      isConfirmingRebuild = true
    }
    .disabled(!canRebuild)

    // Only `.backfilling` gets the progress treatment, matching the Home
    // heatmap: `.loading` is a quick differential re-check with nothing
    // meaningful to show a bar for.
    if case .backfilling(let completed, let total) = syncModel.phase {
      VStack(alignment: .leading, spacing: 8) {
        ProgressView(value: Double(completed), total: Double(max(total, 1)))
        Text("Importing your step history…")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  /// Enabled whenever sync work is settled, regardless of Health authorization
  /// or whether any data exists yet — this doubles as the retry path right
  /// after granting Health access. Disabling only while `.loading`/
  /// `.backfilling` is a UX nicety (avoids a button that looks pressable but
  /// does nothing visible yet); the actual race safety comes from
  /// `StepSyncModel`'s own request queue regardless of this guard.
  ///
  /// `.failed` is also enabled: Rebuild remains a usable (if heavier-handed)
  /// retry path when the shared sync has failed, alongside a lighter Retry
  /// affordance that lands separately.
  private var canRebuild: Bool {
    switch syncModel.phase {
    case .ready, .empty, .failed: true
    case .loading, .backfilling: false
    }
  }
}

#Preview {
  let environment = AppEnvironment(modelContainer: try! AppModelContainer.make(inMemory: true))
  SettingsView(model: environment.makeSettingsViewModel(), syncModel: environment.syncModel)
}
