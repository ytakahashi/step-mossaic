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

  @MainActor
  func testWithData_showsMultipleFrozenMonths() throws {
    // Arrange
    let app = XCUIApplication()
    app.launch(scenario: .withData)
    app.tabBars.buttons["Shelf"].tap()

    // Act
    let months = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "shelf.month."))
    XCTAssertTrue(months.firstMatch.waitForExistence(timeout: 10))

    // Assert: both seeded prior months froze onto the grid, not just one.
    XCTAssertGreaterThanOrEqual(months.count, 2)
  }

  @MainActor
  func testWithData_opensAndClosesMonthDetailSheet() throws {
    // Arrange
    let app = XCUIApplication()
    app.launch(scenario: .withData)
    app.tabBars.buttons["Shelf"].tap()
    let monthTile = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "shelf.month.")
    ).firstMatch
    XCTAssertTrue(monthTile.waitForExistence(timeout: 10))

    // Act
    monthTile.tap()

    // Assert: the detail sheet opens.
    let sheet = app.descendants(matching: .any)["shelf.monthDetail.sheet"]
    XCTAssertTrue(sheet.waitForExistence(timeout: 5))

    // Act: `MonthDetailSheet` has no close button, only the system drag
    // indicator, so dismiss it the way a user would — a swipe down.
    sheet.swipeDown()

    // Assert: the sheet is dismissed rather than stuck open.
    let dismissed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: sheet)
    wait(for: [dismissed], timeout: 5)
  }
}
