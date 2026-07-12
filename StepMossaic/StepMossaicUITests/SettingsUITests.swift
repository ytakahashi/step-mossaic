import XCTest

/// UI tests for the Settings tab, launched against `#if DEBUG`
/// `UITestScenario`s so each state is reached deterministically without
/// depending on real HealthKit data or the on-disk cache.
final class SettingsUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testRebuildCache_confirmAlertCancelLeavesStateUnchanged() throws {
    // Arrange
    let app = XCUIApplication()
    app.launch(scenario: .withData)
    // Tab bar buttons expose their label text, not a custom identifier —
    // SwiftUI does not reliably propagate `.accessibilityIdentifier` through
    // `.tabItem` onto the underlying tab bar button in this OS version.
    app.tabBars.buttons["Settings"].tap()
    let rebuildButton = app.buttons["settings.rebuildCacheButton"]
    XCTAssertTrue(rebuildButton.waitForExistence(timeout: 5))

    // Rebuild is disabled while the shared sync is still loading/backfilling;
    // wait for it to settle before tapping so the alert reliably appears.
    let becameEnabled = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"), object: rebuildButton)
    wait(for: [becameEnabled], timeout: 10)

    // Act
    rebuildButton.tap()

    // Assert: the confirmation alert appears.
    let alert = app.alerts["Rebuild cache?"]
    XCTAssertTrue(alert.waitForExistence(timeout: 5))

    // Act
    alert.buttons["Cancel"].tap()

    // Assert: the alert dismisses and the seeded Shelf content remains. Checking
    // the persisted result catches a Cancel action that accidentally starts the
    // destructive rebuild even if its transient progress state has already gone.
    XCTAssertFalse(alert.exists)
    app.tabBars.buttons["Shelf"].tap()
    // SwiftUI may expose the identified thumbnail container under different
    // XCUI element types across OS versions, so match its stable identifier
    // without coupling the test to one generated element type.
    let seededMonth = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "shelf.month.")
    ).firstMatch
    XCTAssertTrue(seededMonth.waitForExistence(timeout: 5))
  }
}
