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

    /// M2 criterion 7: the pre-account statement is one tap from Today, and in Settings → Privacy.
    func testPreAccountStatementReachableFromTodayAndSettings() {
        let app = XCUIApplication()
        app.launch()
        let footer = app.buttons["today.localOnly"]
        XCTAssertTrue(footer.waitForExistence(timeout: 10))
        XCTAssertEqual(footer.label, "On this iPhone only")
        footer.tap()
        XCTAssertTrue(app.staticTexts["privacy.statement"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        app.tabBars.buttons["Settings"].tap()
        app.buttons["settings.privacy"].tap()
        XCTAssertTrue(app.staticTexts["privacy.statement"].waitForExistence(timeout: 5))
    }

    /// M2 criterion 4: with protected data available, the journal opens:
    /// Today shows the editor, not the locked state.
    func testJournalOpensOnLaunch() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.textViews["today.editor"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Unlock your iPhone to open your journal."].exists)
        XCTAssertFalse(app.staticTexts["Your journal couldn't be opened just now."].exists)
    }

    /// M3 1a: no visible label; the empty editor shows the placeholder and is
    /// named "Today's reflection" for VoiceOver.
    func testEditorPlaceholderAndAccessibilityName() {
        let app = XCUIApplication()
        app.launch()
        let editor = app.textViews["today.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        clear(app)
        XCTAssertEqual(app.staticTexts["today.placeholder"].label, "What are you grateful for today?")
        XCTAssertEqual(editor.label, "Today's reflection")
        XCTAssertFalse(app.staticTexts["Today's reflection"].exists, "no visible label")
    }

    /// M2 criterion 1 / M3 criterion 1: type, kill the app within ~1 s of the
    /// last keystroke, relaunch: the text is intact. Then delete it (M3 #4).
    func testTypedTextSurvivesAKillWithinOneSecondThenDelete() {
        let app = XCUIApplication()
        app.launch()
        let editor = app.textViews["today.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        clear(app)
        editor.tap()
        editor.typeText("Grateful for the morning light")
        Thread.sleep(forTimeInterval: 0.9)
        app.terminate()

        app.launch()
        let reopened = app.textViews["today.editor"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 10))
        XCTAssertEqual(reopened.value as? String, "Grateful for the morning light")

        app.buttons["today.delete"].tap()
        XCTAssertTrue(app.staticTexts["Delete this reflection? This can't be undone."].waitForExistence(timeout: 5))
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["today.placeholder"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["today.placeholder"].waitForExistence(timeout: 10), "deletion persisted")
    }

    /// Audit M1 L2: system accessibility audit on Today (clipped text,
    /// contrast, missing labels, small hit targets).
    func testTodayPassesAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.textViews["today.editor"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit()
    }

    /// Delete today's reflection if there is one, so tests start empty.
    private func clear(_ app: XCUIApplication) {
        let delete = app.buttons["today.delete"]
        guard delete.exists else { return }
        delete.tap()
        app.buttons["Delete"].tap()
        _ = app.staticTexts["today.placeholder"].waitForExistence(timeout: 5)
    }
}
