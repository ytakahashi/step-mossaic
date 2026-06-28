import SwiftData
import SwiftUI

@main
struct StepMossaicApp: App {
  private let sharedModelContainer: ModelContainer
  /// The composition root, owned for the app's lifetime.
  @State private var environment: AppEnvironment

  init() {
    let container: ModelContainer
    do {
      container = try AppModelContainer.make()
    } catch {
      fatalError("Could not create ModelContainer: \(error)")
    }
    sharedModelContainer = container
    _environment = State(initialValue: AppEnvironment(modelContainer: container))
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(environment)
    }
    .modelContainer(sharedModelContainer)
  }
}
