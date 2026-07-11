import SwiftData
import SwiftUI

/// Resolves `AppStartupModel.State` into what's on screen: a brief loading
/// spinner, the real app, or the persistence-failure recovery screen.
///
/// Confining `.environment`/`.modelContainer` to the `.ready` branch here —
/// rather than applying them at the `Scene` level in `StepMossaicApp` — is
/// what makes an unopenable container recoverable instead of a hard crash:
/// nothing downstream ever sees an `AppEnvironment`/`ModelContainer` that
/// doesn't exist. No view currently reads `\.modelContext`/`@Query` (every
/// store goes through `AppEnvironment`'s own `ModelContext`), so
/// `.modelContainer` is unused today; it's kept so a future `@Query`-based
/// view stays correct without rediscovering this wiring.
struct AppRootView: View {
  @State var startup: AppStartupModel

  var body: some View {
    Group {
      switch startup.state {
      case .loading:
        ProgressView()
      case .ready(let environment, let container):
        ContentView()
          .environment(environment)
          .modelContainer(container)
      case .persistenceFailure:
        StartupFailureView(onRetry: retry)
      }
    }
    .task { await startup.start() }
  }

  private func retry() {
    Task { await startup.retry() }
  }
}

#Preview("Startup failure") {
  AppRootView(
    startup: AppStartupModel(makeContainer: {
      throw NSError(domain: "AppRootViewPreview", code: 1)
    })
  )
}
