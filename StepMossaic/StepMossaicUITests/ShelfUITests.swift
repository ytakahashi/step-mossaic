import XCTest

/// UI tests for the Shelf tab, launched against `#if DEBUG` `UITestScenario`s
/// so each state is reached deterministically without depending on real
/// HealthKit data or the on-disk cache.
final class ShelfUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testEmptyState_showsEmptyStateMessage() throws {
    // Arrange
    let app = XCUIApplication()
    app.launch(scenario: .emptyState)

    // Act: tab bar buttons expose their label text, not a custom identifier —
    // SwiftUI does not reliably propagate `.accessibilityIdentifier` through
    // `.tabItem` onto the underlying tab bar button in this OS version.
    app.tabBars.buttons["Shelf"].tap()

    // Assert
    XCTAssertTrue(app.staticTexts["shelf.emptyState"].waitForExistence(timeout: 5))
  }
}
