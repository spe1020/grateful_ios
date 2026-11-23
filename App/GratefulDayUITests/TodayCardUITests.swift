import XCTest

/// Today card (Prep spec 2026-11-23): one card, Wisdom then Affirmation.
final class TodayCardUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        // Leave Today on Wisdom for the other suites.
        let app = XCUIApplication()
        if app.state == .runningForeground { TodayCardUITests.showWisdom(app) }
    }

    private func launch(largestText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.textViews["today.editor"].waitForExistence(timeout: 10))
        TodayCardUITests.showWisdom(app)
        return app
    }

    /// On screen inside the card, not only in the accessibility tree (which
    /// follows the selection even if the pager were scrolled elsewhere).
    private func isShownInCard(_ element: XCUIElement, _ app: XCUIApplication) -> Bool {
        let card = app.descendants(matching: .any)["todayCard"].frame
        let f = element.frame
        return f.minX >= card.minX - 1 && f.maxX <= card.maxX + 1
    }

    private func onWisdom(_ app: XCUIApplication) -> Bool {
        let passage = app.staticTexts["wisdom.passage"]
        guard passage.waitForExistence(timeout: 3), !app.staticTexts["affirmation.text"].exists else { return false }
        Thread.sleep(forTimeInterval: 0.5)   // let a paging scroll settle
        return isShownInCard(passage, app)
    }

    private func onAffirmation(_ app: XCUIApplication) -> Bool {
        let text = app.staticTexts["affirmation.text"]
        guard text.waitForExistence(timeout: 3), !app.staticTexts["wisdom.passage"].exists else { return false }
        Thread.sleep(forTimeInterval: 0.5)
        return isShownInCard(text, app)
    }

    /// Editor top relative to the date title, so a scroll of Today itself
    /// doesn't count as the editor moving.
    private func editorOffset(_ app: XCUIApplication) -> CGFloat {
        app.textViews["today.editor"].frame.minY - app.staticTexts["today.date"].frame.minY
    }

    private func tapDot(_ index: Int, of count: Int, _ app: XCUIApplication) {
        app.descendants(matching: .any)["todayCard.dots"]
            .coordinate(withNormalizedOffset: CGVector(dx: (CGFloat(index) + 0.5) / CGFloat(count), dy: 0.5)).tap()
    }

    /// The card is taller than the screen at the largest sizes.
    private func scrollToDots(_ app: XCUIApplication) {
        let dots = app.descendants(matching: .any)["todayCard.dots"]
        for _ in 0..<8 where !app.windows.firstMatch.frame.insetBy(dx: 0, dy: 100).contains(dots.frame) {
            if dots.frame.minY < app.windows.firstMatch.frame.midY { app.swipeDown(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
        }
    }

    /// Back to the Wisdom page with the first dot.
    static func showWisdom(_ app: XCUIApplication) {
        let dots = app.descendants(matching: .any)["todayCard.dots"]
        guard dots.exists, (dots.value as? String)?.hasPrefix("Daily Wisdom") != true else { return }
        dots.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
    }

    /// Criteria 1, 3 and 6: swipe moves one page and doesn't wrap, dots
    /// switch page, the editor stays put, "Reflect on this" is on Wisdom only.
    func testSwipeAndDotsChangePageWithoutMovingTheEditor() {
        let app = launch()
        XCTAssertTrue(onWisdom(app))
        XCTAssertTrue(app.staticTexts["todayCard.label.wisdom"].exists)
        XCTAssertEqual(app.staticTexts["todayCard.label.wisdom"].label, "Daily Wisdom")
        XCTAssertTrue(app.buttons["wisdom.reflect"].exists)
        let offset = editorOffset(app)
        let pager = app.scrollViews["todayCard.pager"]

        pager.swipeLeft()
        XCTAssertTrue(onAffirmation(app))
        XCTAssertEqual(app.staticTexts["todayCard.label.affirmation"].label, "Daily Affirmation")
        XCTAssertFalse(app.staticTexts["affirmation.text"].label.isEmpty)
        XCTAssertFalse(app.buttons["wisdom.reflect"].exists, "Reflect on this is on Wisdom only")
        XCTAssertEqual(editorOffset(app), offset, accuracy: 0.5, "the editor doesn't move")

        pager.swipeLeft()
        XCTAssertTrue(onAffirmation(app), "no wrap-around past the last page")
        pager.swipeRight()
        XCTAssertTrue(onWisdom(app))
        pager.swipeRight()
        XCTAssertTrue(onWisdom(app), "no wrap-around before the first page")
        XCTAssertEqual(editorOffset(app), offset, accuracy: 0.5)

        tapDot(1, of: 2, app)
        XCTAssertTrue(onAffirmation(app))
        tapDot(0, of: 2, app)
        XCTAssertTrue(onWisdom(app))
        XCTAssertEqual(editorOffset(app), offset, accuracy: 0.5)
    }

    /// Criterion 2: VoiceOver gets one page control, adjustable like
    /// UIPageControl (swipe up/down, or its "Show …" actions), so a page swipe
    /// is never needed, and only the page on screen is read. XCUITest can't
    /// adjust a non-slider on iOS; the step itself is a unit test
    /// (`TodayCardTests.testAdjustStepsOnePageWithoutWrapping`).
    func testVoiceOverPageControlAndOnlyTheVisiblePageIsRead() {
        let app = launch()
        let dots = app.descendants(matching: .any)["todayCard.dots"]
        XCTAssertEqual(dots.label, "Card page")
        XCTAssertEqual(dots.value as? String, "Daily Wisdom, 1 of 2")
        XCTAssertFalse(app.staticTexts["affirmation.text"].exists, "the hidden page isn't read")
        tapDot(1, of: 2, app)
        XCTAssertTrue(onAffirmation(app))
        XCTAssertEqual(dots.value as? String, "Daily Affirmation, 2 of 2")
        XCTAssertFalse(app.buttons["wisdom.reflect"].exists, "the hidden page isn't reachable")
        tapDot(0, of: 2, app)
        XCTAssertTrue(onWisdom(app))
        XCTAssertEqual(dots.value as? String, "Daily Wisdom, 1 of 2")
    }

    /// Criterion 3 at the largest accessibility text size; page text is not
    /// cut off (the system audit checks clipped text).
    func testEditorDoesNotMoveAtLargestTextSize() throws {
        let app = launch(largestText: true)
        let offset = editorOffset(app)
        scrollToDots(app)
        let afterScroll = editorOffset(app)
        XCTAssertEqual(afterScroll, offset, accuracy: 0.5, "offset is scroll-independent")
        tapDot(1, of: 2, app)
        XCTAssertTrue(onAffirmation(app))
        XCTAssertEqual(editorOffset(app), offset, accuracy: 0.5)
        try app.performAccessibilityAudit(for: [.textClipped])
        scrollToDots(app)
        tapDot(0, of: 2, app)
        XCTAssertTrue(onWisdom(app))
        XCTAssertEqual(editorOffset(app), offset, accuracy: 0.5)
        try app.performAccessibilityAudit(for: [.textClipped])
    }

    /// Criterion 7: within a day, the page viewed last is kept across a relaunch.
    func testPageIsKeptAcrossRelaunchWithinTheDay() {
        let app = launch()
        tapDot(1, of: 2, app)
        XCTAssertTrue(onAffirmation(app))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.textViews["today.editor"].waitForExistence(timeout: 10))
        XCTAssertTrue(onAffirmation(app), "kept after relaunch")
        TodayCardUITests.showWisdom(app)
        XCTAssertTrue(onWisdom(app))
    }
}
