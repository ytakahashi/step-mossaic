import Foundation
import StepMossaicDomain
import SwiftData

/// Composition root: owns the app's long-lived collaborators and builds the
/// screen view models, so the SwiftUI tree never constructs HealthKit or SwiftData
/// dependencies itself.
///
/// Main-actor isolated because it wires up main-actor stores, the sync
/// coordinator, and view models. One `StepSource` is shared across screens so the
/// app drives a single HealthKit authorization flow rather than one per view
/// model, and the today view and the heatmap sync read the same source.
///
/// `@Observable` only so it can be injected through the SwiftUI environment; it
/// holds no observable state of its own.
@MainActor
@Observable
final class AppEnvironment {
  private let source: any StepSource
  private let stepLogStore: any StepLogStore
  private let coordinator: StepSyncCoordinator
  private let calendar: Calendar

  init(modelContainer: ModelContainer, calendar: Calendar = .current) {
    let context = ModelContext(modelContainer)
    let source = HealthKitStepSource(calendar: calendar)
    let stepLogStore = SwiftDataStepLogStore(context: context, calendar: calendar)

    self.source = source
    self.stepLogStore = stepLogStore
    self.coordinator = StepSyncCoordinator(
      source: source,
      stepLogStore: stepLogStore,
      calendar: calendar,
      now: { Date() }
    )
    self.calendar = calendar
  }

  /// Builds the Home today-steps view model bound to the shared step source.
  func makeHomeViewModel() -> HomeViewModel {
    HomeViewModel(source: source, calendar: calendar)
  }
}
