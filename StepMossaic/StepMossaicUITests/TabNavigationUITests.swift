import XCTest

/// Cross-tab navigation, launched against the `withData` `#if DEBUG`
/// `UITestScenario` so every screen has real content to render instead of a
/// loading placeholder.
final class TabNavigationUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testWithData_navigatesHomeShelfSettings() throws {
    // Arrange
    let app = XCUIApplication()
    app.launch(scenario: .withData)

    // Assert: Home is the initial tab and renders both seeded data sections.
    XCTAssertTrue(app.navigationBars["Step Mossaic"].waitForExistence(timeout: 10))
    // SwiftUI may expose Canvas-backed and container views under different
    // XCUI element types across OS versions, so match their stable identifiers
    // without coupling the test to generated element types.
    XCTAssertTrue(
      app.descendants(matching: .any)["home.marimo.content"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.descendants(matching: .any)["home.heatmap.content"].exists)

    // Act: tab bar buttons expose their label text, not a custom identifier —
    // SwiftUI does not reliably propagate `.accessibilityIdentifier` through
    // `.tabItem` onto the underlying tab bar button in this OS version.
    app.tabBars.buttons["Shelf"].tap()

    // Assert: the seeded prior month is rendered, not an empty/loading state.
    XCTAssertTrue(app.navigationBars["Shelf"].waitForExistence(timeout: 10))
    let seededMonth = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "shelf.month.")
    ).firstMatch
    XCTAssertTrue(seededMonth.waitForExistence(timeout: 10))

    // Act
    app.tabBars.buttons["Settings"].tap()

    // Assert: Settings renders its primary cache-management control.
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["settings.rebuildCacheButton"].waitForExistence(timeout: 5))
  }
}
