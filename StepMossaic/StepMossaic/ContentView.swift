import SwiftUI

struct ContentView: View {
  @Environment(AppEnvironment.self) private var environment

  var body: some View {
    TabView {
      HomeView(
        model: environment.makeHomeViewModel(),
        syncModel: environment.syncModel,
        marimoModel: environment.makeGrowingMarimoViewModel(),
        heatmapModel: environment.makeHeatmapViewModel()
      )
      .tabItem {
        Label("Home", systemImage: "circle.grid.2x2")
      }

      ShelfView(model: environment.makeShelfViewModel(), syncModel: environment.syncModel)
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
    .environment(AppEnvironment(modelContainer: try! AppModelContainer.make(inMemory: true)))
}
