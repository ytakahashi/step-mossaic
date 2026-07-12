#if DEBUG
  import Foundation
  import StepMossaicDomain
  import SwiftData

  /// Scenario switch read from `XCUIApplication.launchEnvironment`, letting UI
  /// tests force a deterministic startup path without touching real HealthKit
  /// data or the on-disk cache. Compiled only into Debug builds so this path
  /// never ships in a Release/App Store binary.
  enum UITestScenario: String {
    /// HealthKit access has not been requested yet; Home/Settings should show
    /// their connect prompts.
    case healthNotDetermined
    /// Sync settles with no step data at all; Home/Shelf should show their
    /// empty states.
    case emptyState
    /// A full prior month plus the current month are pre-seeded (see
    /// `UITestFixtures`), so every screen renders real content.
    case withData
    /// The `ModelContainer` factory always throws, so the app never leaves
    /// `AppStartupModel.State.persistenceFailure`.
    case persistenceFailure

    static let launchEnvironmentKey = "UITEST_SCENARIO"

    static var current: UITestScenario? {
      ProcessInfo.processInfo.environment[launchEnvironmentKey]
        .flatMap(UITestScenario.init(rawValue:))
    }

    /// Builds the `AppStartupModel` for this scenario: an in-memory container
    /// (never the real on-disk cache) paired with a fake `StepSource`.
    func makeStartupModel() -> AppStartupModel {
      if self == .persistenceFailure {
        return AppStartupModel(makeContainer: { throw UITestScenarioError.forcedFailure })
      }
      return AppStartupModel(
        makeContainer: {
          let container = try AppModelContainer.make(inMemory: true)
          if self == .withData {
            try UITestFixtures.seedSampleData(into: container)
          }
          return container
        },
        makeEnvironment: { container in
          AppEnvironment(modelContainer: container, source: makeStepSource())
        }
      )
    }

    private func makeStepSource() -> any StepSource {
      switch self {
      case .healthNotDetermined:
        return UITestFakeStepSource(status: .notDetermined)
      case .emptyState, .withData, .persistenceFailure:
        return UITestFakeStepSource(status: .requested)
      }
    }
  }

  /// The forced failure `persistenceFailure` throws from its container
  /// factory. Carries no detail — the scenario only needs *a* failure, and
  /// `AppStartupModel.State.persistenceFailure` never surfaces error detail.
  enum UITestScenarioError: Error {
    case forcedFailure
  }
#endif
