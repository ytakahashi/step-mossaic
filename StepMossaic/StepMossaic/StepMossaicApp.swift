import SwiftUI

@main
struct StepMossaicApp: App {
  /// Owns the container-resolution lifecycle for the app's lifetime; see
  /// `AppRootView` for how each `AppStartupModel.State` renders.
  @State private var startup = AppStartupModel(
    makeContainer: { try AppModelContainer.make() },
    reporter: DiagnosticsLogger.report
  )

  var body: some Scene {
    WindowGroup {
      AppRootView(startup: startup)
    }
  }
}
