#if DEBUG
  import Foundation
  import StepMossaicDomain

  /// Scenario switch read from `XCUIApplication.launchEnvironment`, letting UI
  /// tests force a deterministic startup path without touching real HealthKit
  /// data or the on-disk cache. Compiled only into Debug builds so this path
  /// never ships in a Release/App Store binary.
  enum UITestScenario: String {
    case healthNotDetermined

    static let launchEnvironmentKey = "UITEST_SCENARIO"

    static var current: UITestScenario? {
      ProcessInfo.processInfo.environment[launchEnvironmentKey]
        .flatMap(UITestScenario.init(rawValue:))
    }

    /// Builds the `AppStartupModel` for this scenario: an in-memory container
    /// (never the real on-disk cache) paired with a fake `StepSource`.
    func makeStartupModel() -> AppStartupModel {
      AppStartupModel(
        makeContainer: { try AppModelContainer.make(inMemory: true) },
        makeEnvironment: { container in
          AppEnvironment(modelContainer: container, source: makeStepSource())
        }
      )
    }

    private func makeStepSource() -> any StepSource {
      switch self {
      case .healthNotDetermined:
        return UITestFakeStepSource(status: .notDetermined)
      }
    }
  }
#endif
