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
  private let marimoStore: any MarimoStore
  private let coordinator: StepSyncCoordinator
  private let calendar: Calendar

  /// The single cache-sync owner, shared across every cache-backed section so the
  /// app drives one sync rather than one per view model.
  let syncModel: StepSyncModel

  init(
    modelContainer: ModelContainer,
    calendar: Calendar = .current,
    // Overridable only so `#if DEBUG` UI-test scenarios can force a
    // deterministic, HealthKit-free `StepSource`; production call sites always
    // pass `nil` and get the real HealthKit-backed source.
    source: (any StepSource)? = nil
  ) {
    let context = ModelContext(modelContainer)
    let source = source ?? HealthKitStepSource(calendar: calendar)
    let stepLogStore = SwiftDataStepLogStore(context: context, calendar: calendar)
    let marimoStore = SwiftDataMarimoStore(context: context)
    // Marimo tuning is assembled here, in the composition root, rather than left as
    // a generator default — this is the seam a future Settings screen feeds a
    // persisted `sizeReferenceMonthlySteps` (the monthly-steps reference) into.
    let marimoConfig = MarimoGenerationConfig()
    let coordinator = StepSyncCoordinator(
      source: source,
      stepLogStore: stepLogStore,
      marimoStore: marimoStore,
      calendar: calendar,
      now: { Date() },
      marimoConfig: marimoConfig,
      freezePolicy: MarimoFreezePolicy(gracePeriodDays: 5)
    )

    self.source = source
    self.stepLogStore = stepLogStore
    self.marimoStore = marimoStore
    self.coordinator = coordinator
    self.calendar = calendar
    self.syncModel = StepSyncModel(coordinator: coordinator, reporter: DiagnosticsLogger.report)
  }

  /// Builds the Home today-steps view model bound to the shared step source.
  func makeHomeViewModel() -> HomeViewModel {
    HomeViewModel(source: source, calendar: calendar)
  }

  /// Builds the heatmap view model bound to the shared sync coordinator and cache.
  func makeHeatmapViewModel() -> HeatmapViewModel {
    HeatmapViewModel(
      coordinator: coordinator,
      stepLogStore: stepLogStore,
      calendar: calendar,
      today: { Date() }
    )
  }

  /// Builds the growing-marimo view model bound to the shared sync coordinator.
  func makeGrowingMarimoViewModel() -> GrowingMarimoViewModel {
    GrowingMarimoViewModel(coordinator: coordinator)
  }

  /// Builds the shelf view model bound to the shared frozen-marimo store and the
  /// cache it reads each tapped month's heatmap detail from.
  func makeShelfViewModel() -> ShelfViewModel {
    ShelfViewModel(
      marimoStore: marimoStore,
      stepLogStore: stepLogStore,
      coordinator: coordinator,
      calendar: calendar
    )
  }

  /// Builds the Settings view model bound to the shared step source (for Health
  /// status/connection) and the shared sync model (for triggering a rebuild).
  func makeSettingsViewModel() -> SettingsViewModel {
    SettingsViewModel(source: source, syncModel: syncModel)
  }
}
