import XCTest

/// UI tests for the startup recovery screen, launched against the
/// `persistenceFailure` `#if DEBUG` `UITestScenario` so a container-open
/// failure is reached deterministically without a real, broken on-disk store.
final class StartupUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testPersistenceFailure_showsRecoveryScreenAndSurvivesRetry() throws {
    // Arrange
    let app = XCUIApplication()

    // Act
    app.launch(scenario: .persistenceFailure)

    // Assert: the recovery screen renders instead of a crash.
    let retryButton = app.buttons["startup.failureView.retryButton"]
    XCTAssertTrue(retryButton.waitForExistence(timeout: 5))

    // Act: the scenario's container factory always throws, so retrying can
    // never succeed — this proves retrying does not crash, not that it recovers.
    retryButton.tap()

    // Assert: still on the recovery screen.
    XCTAssertTrue(retryButton.waitForExistence(timeout: 5))
  }
}
