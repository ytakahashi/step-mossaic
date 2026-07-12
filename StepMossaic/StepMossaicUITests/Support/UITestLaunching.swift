import XCTest

/// Scenario names and the launch-environment key shared with the app
/// target's `#if DEBUG`-only `UITestScenario`. Duplicated here rather than
/// imported: UI tests drive the app as a separate process via
/// `XCUIApplication` and cannot see the app target's internal Swift types.
/// Keep the raw values in sync with
/// `StepMossaic/App/UITestSupport/UITestScenario.swift`.
enum UITestScenario: String {
  case healthNotDetermined

  static let launchEnvironmentKey = "UITEST_SCENARIO"
}

extension XCUIApplication {
  /// Launches the app pinned to a deterministic `#if DEBUG` scenario instead
  /// of the real HealthKit / on-disk-cache startup path.
  func launch(scenario: UITestScenario) {
    launchEnvironment[UITestScenario.launchEnvironmentKey] = scenario.rawValue
    launch()
  }
}
