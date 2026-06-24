import SwiftData
import SwiftUI

@main
struct StepMossaicApp: App {
  var sharedModelContainer: ModelContainer = {
    do {
      return try AppModelContainer.make()
    } catch {
      fatalError("Could not create ModelContainer: \(error)")
    }
  }()

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .modelContainer(sharedModelContainer)
  }
}
