import XCTest

/// M1 acceptance checks that need the running app.
final class AppShellUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Criterion 1: cold launch lands on Today, with nothing in the way.
    func testColdLaunchLandsOnToday() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["today.date"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
        XCTAssertEqual(app.alerts.count, 0, "No permission prompt or alert on launch")
    }

    /// Criterion 3: each tab is reachable in one tap from any other.
    func testEveryTabIsOneTapFromEveryOther() {
        let app = XCUIApplication()
        app.launch()
        let tabs = ["Today", "Calendar", "Settings"]
        for from in tabs {
            for to in tabs where to != from {
                app.tabBars.buttons[from].tap()
                app.tabBars.buttons[to].tap()
                XCTAssertTrue(app.tabBars.buttons[to].isSelected, "\(from) → \(to)")
            }
        }
    }

    /// Criterion 4: Today's date is not truncated at the largest accessibility size.
    func testTodayAtLargestTextSize() {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let date = app.staticTexts["today.date"]
        XCTAssertTrue(date.waitForExistence(timeout: 10))
        XCTAssertFalse(date.label.isEmpty)
        XCTAssertTrue(date.frame.width <= app.windows.firstMatch.frame.width, "Date fits the screen width")
    }
}
