import XCTest

/// UI tests for the Home tab, launched against `#if DEBUG` `UITestScenario`s so
/// each state is reached deterministically without depending on real HealthKit
/// data or the on-disk cache.
final class HomeUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testHealthNotDetermined_showsConnectHealthPrompt() throws {
    // Arrange
    let app = XCUIApplication()

    // Act
    app.launch(scenario: .healthNotDetermined)

    // Assert: existence only — tapping the button would trigger the real
    // system HealthKit permission dialog, which XCUITest cannot drive reliably.
    XCTAssertTrue(app.buttons["home.allowHealthAccessButton"].waitForExistence(timeout: 5))
  }
}
