import SwiftUI

struct SettingsView: View {
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
  SettingsView()
}
