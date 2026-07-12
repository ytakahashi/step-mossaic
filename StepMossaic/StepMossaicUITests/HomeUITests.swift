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

    // Assert: the cache-backed sections don't render at all before access is
    // resolved — syncing pre-authorization is doomed and would otherwise
    // surface as a misleading "Step data couldn't be loaded" error.
    XCTAssertFalse(app.staticTexts["home.marimo.emptyState"].exists)
    XCTAssertFalse(app.staticTexts["home.heatmap.emptyState"].exists)
  }

  @MainActor
  func testEmptyState_showsEmptyMarimoAndHeatmap() throws {
    // Arrange
    let app = XCUIApplication()

    // Act
    app.launch(scenario: .emptyState)

    // Assert: sync settles `.empty` (not `.failed`), so both cache-backed
    // sections show their empty-state copy rather than a redacted placeholder
    // or a retry prompt.
    XCTAssertTrue(app.staticTexts["home.marimo.emptyState"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["home.heatmap.emptyState"].exists)

    // Assert: the marimo's empty state also hints at Settings, since a
    // granted-but-genuinely-empty month and a denied Health read render
    // identically here — HealthKit never reveals denial for read access.
    XCTAssertTrue(app.staticTexts["home.marimo.emptyState.healthAccessHint"].exists)
  }
}
