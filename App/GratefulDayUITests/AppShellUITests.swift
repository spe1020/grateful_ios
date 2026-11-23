import XCTest

/// M1 acceptance checks that need the running app.
final class AppShellUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Criterion 1: cold launch lands on Today, with nothing in the way.
    func testColdLaunchLandsOnToday() {
        let app = Self.app()
        app.launch()
        XCTAssertTrue(app.staticTexts["today.date"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
        XCTAssertEqual(app.alerts.count, 0, "No permission prompt or alert on launch")
    }

    /// Criterion 3: each tab is reachable in one tap from any other.
    func testEveryTabIsOneTapFromEveryOther() {
        let app = Self.app()
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
        let app = Self.app()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let date = app.staticTexts["today.date"]
        XCTAssertTrue(date.waitForExistence(timeout: 10))
        XCTAssertFalse(date.label.isEmpty)
        XCTAssertTrue(date.frame.width <= app.windows.firstMatch.frame.width, "Date fits the screen width")
    }

    /// M2 criterion 7: the pre-account statement is one tap from Today, and in Settings → Privacy.
    func testPreAccountStatementReachableFromTodayAndSettings() {
        let app = Self.app()
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
        let app = Self.app()
        app.launch()
        XCTAssertTrue(app.textViews["today.editor"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Unlock your iPhone to open your journal."].exists)
        XCTAssertFalse(app.staticTexts["Your journal couldn't be opened just now. Nothing has been deleted."].exists)
    }

    /// M3 1a: no visible label; the empty editor shows the placeholder and is
    /// named "Today's reflection" for VoiceOver.
    func testEditorPlaceholderAndAccessibilityName() {
        let app = Self.app()
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
        let app = Self.app()
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
        let app = Self.app()
        app.launch()
        XCTAssertTrue(app.textViews["today.editor"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit()
    }

    /// Audit M3a I2: the accessibility audit at the largest text size, on
    /// Today and on the Calendar.
    @MainActor
    func testAccessibilityAuditAtLargestTextSize() throws {
        let app = Self.app()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.textViews["today.editor"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit { issue in
            Self.isBehindTabBar(issue, app)
        }
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.staticTexts["calendar.month"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit { issue in
            Self.isBehindTabBar(issue, app)
        }
    }

    /// M3 criteria 5 and 6: writing today marks today in the calendar and
    /// updates the counts; future days are unavailable.
    func testCalendarMarksTodayAfterWriting() {
        let app = Self.app()
        app.launch()
        let editor = app.textViews["today.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        clear(app)
        editor.tap()
        editor.typeText("Calendar check")
        app.buttons["today.keyboardDone"].tap()
        Thread.sleep(forTimeInterval: 1)

        app.tabBars.buttons["Calendar"].tap()
        let todayCell = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Today' AND label CONTAINS 'Reflection written'")).firstMatch
        XCTAssertTrue(todayCell.waitForExistence(timeout: 10))
        let monthCount = app.staticTexts["calendar.monthCount"]
        XCTAssertTrue(monthCount.label.hasSuffix("this month"), monthCount.label)
        XCTAssertNotEqual(monthCount.label, "No reflections this month")
        let future = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Unavailable'")).firstMatch
        if future.exists { XCTAssertFalse(future.isEnabled) }

        // Tapping today goes to Today.
        todayCell.tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
        clear(app)
    }

    /// M4 criteria 1–2: today's wisdom shows above the editor, and
    /// "Reflect on this" pins the question without touching the entry.
    func testReflectOnThisPinsTheQuestionAndInsertsNothing() {
        let app = Self.app()
        app.launch()
        let editor = app.textViews["today.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        clear(app)
        XCTAssertTrue(app.staticTexts["wisdom.passage"].exists)
        let question = app.descendants(matching: .any)["wisdom.question"].label
        XCTAssertFalse(question.isEmpty)
        app.buttons["wisdom.reflect"].tap()
        let pinned = app.staticTexts["today.pinnedQuestion"]
        XCTAssertTrue(pinned.waitForExistence(timeout: 5))
        XCTAssertTrue(question.contains(pinned.label) || pinned.label == question)
        XCTAssertTrue(app.staticTexts["today.placeholder"].exists, "the entry is still empty")
        XCTAssertEqual((editor.value as? String) ?? "", "")
        app.buttons["today.unpin"].tap()
        XCTAssertFalse(pinned.exists)
    }

    /// M4 criterion 4: a first reflection can be saved within 30 seconds of
    /// launch, with no account step and no permission prompt.
    func testFirstReflectionWithinThirtySeconds() {
        let app = Self.app()
        app.launch()
        // The clock starts once the app is open (M4: "first reflection within
        // 30 s of opening the app"). `launch()` also includes XCUITest
        // terminating the previous test's instance and starting its automation
        // session, which took 2–49 s on CI runners on both main and #14 and
        // isn't the app (Chief P26). The 30 s limit is unchanged.
        let start = Date()
        let editor = app.textViews["today.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        clear(app)
        editor.tap()
        editor.typeText("Thirty seconds")
        app.buttons["today.keyboardDone"].tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(app.alerts.count, 0, "no permission prompt")
        XCTAssertTrue(app.buttons["today.delete"].exists, "saved")
        XCTAssertLessThan(Date().timeIntervalSince(start), 30)
        clear(app)
    }

    /// Prep F1/F4/F2/F7: create a journal key (always confirmed), decline the
    /// backup (one extra confirmation), then sign out: the journal stays.
    func testCreateKeyDeclineBackupThenSignOutKeepsTheJournal() {
        let app = Self.app()
        app.launch()
        let editor = app.textViews["today.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        clear(app)
        editor.tap()
        editor.typeText("Kept after sign-out")
        app.buttons["today.keyboardDone"].tap()
        Thread.sleep(forTimeInterval: 1)

        app.tabBars.buttons["Settings"].tap()
        app.buttons["settings.account"].tap()
        if app.buttons["account.signOut"].waitForExistence(timeout: 3) {
            // Left over from an earlier run: sign out first.
            app.buttons["account.signOut"].tap()
            app.buttons["signOut.confirm"].tap()
        }
        XCTAssertTrue(app.buttons["account.usedBefore"].waitForExistence(timeout: 5), "restore comes first")
        app.buttons["account.create"].tap()
        XCTAssertTrue(app.staticTexts["Make a new journal key?"].waitForExistence(timeout: 5))
        app.buttons["Make a new key"].tap()

        XCTAssertTrue(app.buttons["backup.no"].waitForExistence(timeout: 5), "the backup offer follows")
        XCTAssertTrue(app.buttons["backup.yes"].exists)
        app.buttons["backup.no"].tap()
        app.buttons["Continue without backup"].tap()

        XCTAssertTrue(app.buttons["account.signOut"].waitForExistence(timeout: 5))
        app.buttons["account.signOut"].tap()
        XCTAssertTrue(app.staticTexts["signOut.noBackup"].waitForExistence(timeout: 5), "warns: no backup")
        app.buttons["signOut.confirm"].tap()
        XCTAssertTrue(app.buttons["account.usedBefore"].waitForExistence(timeout: 5), "signed out")

        app.tabBars.buttons["Today"].tap()
        XCTAssertEqual(app.textViews["today.editor"].value as? String, "Kept after sign-out", "the journal stays")
        clear(app)
    }

    /// At the largest text sizes, scrolled content passes under the
    /// translucent tab bar, and the audit's screenshot then measures text
    /// against the bar's blur. Only that contrast case is skipped; every
    /// other issue, and contrast anywhere else on screen, still fails.
    @MainActor
    private static func isBehindTabBar(_ issue: XCUIAccessibilityAuditIssue, _ app: XCUIApplication) -> Bool {
        guard issue.auditType == .contrast, let element = issue.element else { return false }
        return element.frame.intersects(app.tabBars.firstMatch.frame)
    }

    /// Delete today's reflection if there is one, so tests start empty.
    /// Every UI test runs with no relays (Chief P48): a pass ends unresolved,
    /// so nothing reaches the network and no sheet appears by itself.
    static func app(relays: String = "-uiTestNoRelays") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(relays)
        return app
    }

    /// Spec A, on purpose: with relays that answer "nothing here", connecting
    /// a new key brings up the disclosure sheet once the backup offer closes,
    /// and Not now leaves the journal local. Signs out after.
    func testConnectingAnAccountBringsUpTheDisclosureSheet() {
        let app = Self.app(relays: "-uiTestEmptyRelays")
        app.launch()
        XCTAssertTrue(app.textViews["today.editor"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()
        app.buttons["settings.account"].tap()
        if app.buttons["account.signOut"].waitForExistence(timeout: 3) {
            // Left over from an earlier run: sign out first.
            app.buttons["account.signOut"].tap()
            app.buttons["signOut.confirm"].tap()
            XCTAssertTrue(app.buttons["account.usedBefore"].waitForExistence(timeout: 5))
            app.terminate()
            app.launch()
            app.tabBars.buttons["Settings"].tap()
            app.buttons["settings.account"].tap()
        }
        XCTAssertTrue(app.buttons["account.create"].waitForExistence(timeout: 5))
        app.buttons["account.create"].tap()
        app.buttons["Make a new key"].tap()
        XCTAssertTrue(app.buttons["backup.no"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["disclosure.heading"].exists, "the sheet waits for the backup offer")
        app.buttons["backup.no"].tap()
        app.buttons["Continue without backup"].tap()

        // With #20 a pass starts when the account connects; before it, at the
        // next return to the foreground. Either way, the sheet comes up.
        if !app.staticTexts["disclosure.heading"].waitForExistence(timeout: 5) {
            XCUIDevice.shared.press(.home)
            app.activate()
        }
        XCTAssertTrue(app.staticTexts["disclosure.heading"].waitForExistence(timeout: 15), "the spec A sheet")
        app.buttons["disclosure.notNow"].tap()
        // Not now: nothing is published (the empty relays reject every event
        // anyway, and UITestRelaysTests checks that no rejection counts as an
        // acknowledgement), and the screen underneath can be used again.
        XCTAssertTrue(app.buttons["account.signOut"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["account.signOut"].isHittable, "the sheet is gone")
        XCTAssertTrue(app.tabBars.buttons["Today"].isHittable)
        app.buttons["account.signOut"].tap()
        app.buttons["signOut.confirm"].tap()
        XCTAssertTrue(app.buttons["account.usedBefore"].waitForExistence(timeout: 5), "signed out")
    }

    private func clear(_ app: XCUIApplication) {
        let delete = app.buttons["today.delete"]
        guard delete.exists else { return }
        delete.tap()
        app.buttons["Delete"].tap()
        _ = app.staticTexts["today.placeholder"].waitForExistence(timeout: 5)
    }
}
