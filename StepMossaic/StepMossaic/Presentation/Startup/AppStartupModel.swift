import Observation
import SwiftData

/// Resolves the app's `ModelContainer` into a state the root view can render,
/// so a container that fails to open (storage pressure, a corrupt store, a
/// future schema migration gap) is a recoverable screen instead of a
/// `fatalError` at launch.
///
/// Owns no persistence itself — `makeContainer` is the only place that can
/// throw, and this model's whole job is turning that throw into `State`
/// rather than letting it propagate into `StepMossaicApp.init()`.
@MainActor
@Observable
final class AppStartupModel {
  /// Builds the app's `ModelContainer`, or throws if it couldn't be opened.
  /// Injected so tests can simulate a persistence failure without needing a
  /// real, broken on-disk store — see `AppModelContainer.make`.
  typealias ModelContainerFactory = () async throws -> ModelContainer

  /// The outcome of resolving the container.
  ///
  /// Not `Equatable`: `.ready` holds `AppEnvironment` (a class with no
  /// meaningful equality) and `ModelContainer` (not `Equatable`). Tests and
  /// call sites pattern-match with `if case`/`switch` instead of `==`.
  enum State {
    case loading
    case ready(AppEnvironment, ModelContainer)
    /// The container couldn't be opened. Carries no `Error`: the recovery
    /// screen never shows SwiftData failure detail, only that a retry is
    /// possible and Health data itself is unaffected.
    case persistenceFailure
  }

  private(set) var state: State = .loading

  private let makeContainer: ModelContainerFactory
  private let reporter: DiagnosticsReporter
  /// Guards the synchronous store-opening boundary across `Task.yield()`, so
  /// overlapping start/retry requests cannot create two containers for the same
  /// persistent store.
  private var isAttempting = false

  init(
    makeContainer: @escaping ModelContainerFactory,
    reporter: @escaping DiagnosticsReporter = { _, _ in }
  ) {
    self.makeContainer = makeContainer
    self.reporter = reporter
  }

  /// Resolves the container for the first time. Called once, from the root
  /// view's `.task`.
  func start() async {
    await attempt()
  }

  /// Re-resolves the container after `.persistenceFailure`, non-destructively
  /// (nothing is deleted; this just calls `makeContainer` again).
  ///
  /// Overlapping calls are ignored while an attempt is in flight. Opening a
  /// persistent container can touch store files or run a migration, so even a
  /// rapid double-tap must never invoke the factory twice concurrently.
  func retry() async {
    await attempt()
  }

  private func attempt() async {
    // Main-actor isolation makes this check-and-set atomic with respect to every
    // other `start()`/`retry()` call, including across the yield below.
    guard !isAttempting else { return }
    isAttempting = true
    defer { isAttempting = false }

    state = .loading
    // `ModelContainer(...)` is a synchronous, potentially slow call (disk I/O,
    // a store migration). Yielding first gives SwiftUI a chance to actually
    // paint the `.loading` state before that work blocks the main actor,
    // instead of jumping straight from the previous state to the next one.
    await Task.yield()

    do {
      let container = try await makeContainer()
      state = .ready(AppEnvironment(modelContainer: container), container)
      reporter(.startup, .success)
    } catch {
      state = .persistenceFailure
      reporter(.startup, .failure(.persistence))
    }
  }
}
