import SwiftData
import SwiftUI

struct ContentView: View {
  var body: some View {
    TabView {
      HomeView()
        .tabItem {
          Label("Home", systemImage: "circle.grid.2x2")
        }

      ShelfView()
        .tabItem {
          Label("Shelf", systemImage: "square.grid.3x3")
        }

      SettingsView()
        .tabItem {
          Label("Settings", systemImage: "gearshape")
        }
    }
  }
}

#Preview {
  ContentView()
    .modelContainer(
      for: [
        DailyStepLogRecord.self,
        FrozenMarimoRecord.self,
        SyncAnchorRecord.self,
      ], inMemory: true)
}
