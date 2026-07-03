import SwiftUI

struct SettingsView: View {
  // Wired ahead of the Step 3 UI implementation, which connects `body` to these
  // (Health status display, Connect/Open Settings actions, cache rebuild).
  @State private var model: SettingsViewModel
  @State private var syncModel: StepSyncModel

  init(model: SettingsViewModel, syncModel: StepSyncModel) {
    _model = State(initialValue: model)
    _syncModel = State(initialValue: syncModel)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Health") {
          LabeledContent("Steps", value: "Not connected")
          Button("Connect Health") {}
        }

        Section("Data") {
          Button("Rebuild cache", role: .destructive) {}
        }
      }
      .navigationTitle("Settings")
    }
  }
}

#Preview {
  let environment = AppEnvironment(modelContainer: try! AppModelContainer.make(inMemory: true))
  SettingsView(model: environment.makeSettingsViewModel(), syncModel: environment.syncModel)
}
