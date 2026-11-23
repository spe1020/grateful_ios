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
    @MainActor
    func testTodayPassesAccessibilityAudit() throws {
        let app = Self.app()
        app.launch()
        XCTAssertTrue(app.textViews["today.editor"].waitForExistence(timeout: 10))
        // P59: the audit runs with Today scrolled to its end (its only
        // exemption is P60/P62's, below),
        // where "On this iPhone only" must sit fully above the floating tab
        // bar. The pill is measured by its buttons: `tabBars.firstMatch`'s
        // frame doesn't match what's drawn on iOS 26 (CI run 45301430098).
        let date = app.staticTexts["today.date"]
        let footer = app.staticTexts["On this iPhone only"].firstMatch
        XCTAssertTrue(footer.exists)
        Self.logLayout(app, "at launch")
        let window = app.windows.firstMatch
        Self.scrollToEnd(app)
        Self.logLayout(app, "at the end")
        // P59, checked at rest: at the end of the content, with nothing
        // dragged, the footer sits fully above the tab bar. If it doesn't,
        // that is an app layout defect, not test timing.
        let barTop = Self.tabBarTop(app)
        let atRest = XCTAttachment(screenshot: app.screenshot())
        atRest.name = "Today at rest at the end"
        atRest.lifetime = .keepAlways
        add(atRest)
        guard footer.frame.maxY <= barTop else {
            XCTFail("app layout: at the at-rest end of Today the footer (maxY \(footer.frame.maxY)) is under the tab bar (top \(barTop))")
            return
        }
        // P140: at the very end, a text line can sit half above the top
        // edge (wisdom.author, CI run 45773428298), and the Xcode 26 audit
        // reports a line cut by the screen edge as "Potentially inaccessible
        // text" with no element. Text scrolled partly off the top is normal
        // scroll state, not an app defect, so the audit runs at a settled
        // end position instead: nudge the content back down in small slow
        // drags until no static text straddles y=0. Fail closed if it never
        // settles, rather than auditing a frame that can misfire.
        // P146: a 20 pt nudge once moved the content 144 pt (CI run
        // 46004022373), pushing the footer under the tab bar. A drag's
        // distance doesn't bound the scroll, so each nudge is checked: one
        // that leaves the footer under the bar is undone by scrolling back
        // to the end, and the 12 attempts still bound the loop.
        var settled = Self.textsStraddlingTop(app).isEmpty
        for _ in 0..<12 where !settled {
            let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 8, dy: window.frame.height * 0.3))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 20)), withVelocity: .slow, thenHoldForDuration: 0.5)
            Self.waitUntilStill(date)
            print("A11Y-SETTLE date=\(date.frame.minY) footer=\(footer.frame.maxY) barTop=\(barTop) straddling=\(Self.textsStraddlingTop(app))")
            if footer.frame.maxY > barTop {
                print("A11Y-SETTLE overshoot: the footer went under the tab bar; back to the end")
                Self.scrollToEnd(app)
                continue
            }
            settled = Self.textsStraddlingTop(app).isEmpty
        }
        Self.logLayout(app, "settled for the audit")
        let straddling = Self.textsStraddlingTop(app)
        guard straddling.isEmpty, footer.frame.maxY <= barTop else {
            XCTFail("no position near the end leaves every text line clear of the top edge with the footer above the tab bar (top \(barTop)): footer maxY \(footer.frame.maxY), straddling \(straddling)")
            return
        }
        XCTAssertLessThan(date.frame.maxY, 0, "the audit still runs with Today scrolled down, content off the top")
        XCTAssertLessThanOrEqual(footer.frame.maxY, Self.tabBarTop(app), "the footer is fully above the tab bar")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Today at the audited position"
        shot.lifetime = .keepAlways
        add(shot)
        // One plain audit of every type. The only exemption is P60/P62's
        // contrast skip inside the wisdom card.
        try app.performAccessibilityAudit { issue in
            Self.log(issue)
            return Self.isWisdomCardContrastFalsePositive(issue, app)
        }
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
        Self.waitOutMidnight()
        let app = Self.app()
        app.launch()
        let editor = app.textViews["today.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        clear(app)
        editor.tap()
        editor.typeText("Calendar check")
        Self.dismissKeyboard(app)
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
        TodayCardUITests.showWisdom(app)
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
        Self.dismissKeyboard(app)
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
        Self.dismissKeyboard(app)
        Thread.sleep(forTimeInterval: 1)

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings.account"].waitForExistence(timeout: 10), "Settings is showing")
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

    /// P55: name the element behind an audit failure in the CI log. Never
    /// ignores the issue: it only prints it before the audit fails.
    @MainActor
    private static func log(_ issue: XCUIAccessibilityAuditIssue) {
        let element = issue.element.map { "\($0.elementType.rawValue) id=\"\($0.identifier)\" label=\"\($0.label)\" frame=\($0.frame)" } ?? "nil"
        print("A11Y-AUDIT-ISSUE type=\(issue.auditType.rawValue) compact=\"\(issue.compactDescription)\" detail=\"\(issue.detailedDescription)\" element=\(element)")
    }

    /// P60/P62 (Chief): Apple's contrast audit sometimes reports dark text on
    /// the cream wisdom card although it is 11.54:1. CI run 45312897251 hit
    /// "Reflect on this", and run 45320442017 also hit "Carry it with you", a
    /// child of a `.combine` group the audit reported with `id=""`. Every
    /// text in `WisdomCard` is `GDColor.foreground` on the card's
    /// `GDColor.secondary` fill (`WisdomCard.swift`), the pair
    /// `ColorContrastTests` computes from the tokens. So only a `.contrast`
    /// issue whose element lies entirely inside the card's frame, read now,
    /// is skipped, and each skip is printed. Matching is by frame because a
    /// child identifier inside `.combine` never surfaces as its own element.
    /// Fails closed: no card, no element or an empty frame (an element that
    /// no longer resolves) fails the issue,
    /// and so does any other issue type, or contrast anywhere else.
    @MainActor
    private static func isWisdomCardContrastFalsePositive(_ issue: XCUIAccessibilityAuditIssue, _ app: XCUIApplication) -> Bool {
        guard issue.auditType == .contrast, let element = issue.element else { return false }
        let card = app.descendants(matching: .any)["wisdom.card"].firstMatch
        guard card.exists else { return false }
        let cardFrame = card.frame, issueFrame = element.frame
        guard !cardFrame.isEmpty, !issueFrame.isEmpty, cardFrame.contains(issueFrame) else { return false }
        print("A11Y-AUDIT-SKIPPED P62 type=\(issue.auditType.rawValue) id=\"\(element.identifier)\" label=\"\(element.label)\" frame=\(issueFrame) card=\(cardFrame)")
        return true
    }

    /// Drags in the left margin, where nothing can be pressed, until the
    /// date stops moving: the end of Today's content.
    @MainActor
    static func scrollToEnd(_ app: XCUIApplication) {
        let date = app.staticTexts["today.date"]
        let window = app.windows.firstMatch
        for _ in 0..<4 {
            let before = date.frame
            let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 8, dy: window.frame.height * 0.7))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -400)))
            waitUntilStill(date)
            if date.frame == before { break }
        }
    }

    /// P140: the static texts cut by the top edge of the screen.
    @MainActor
    static func textsStraddlingTop(_ app: XCUIApplication) -> [String] {
        app.staticTexts.allElementsBoundByIndex
            .filter { $0.exists && $0.frame.minY < 0 && $0.frame.maxY > 0 }
            .map { "\($0.identifier.isEmpty ? "(no id)" : $0.identifier) \($0.frame)" }
    }

    /// The top of the drawn tab bar, taken from its buttons (P59).
    @MainActor
    static func tabBarTop(_ app: XCUIApplication) -> CGFloat {
        app.tabBars.firstMatch.buttons.allElementsBoundByIndex.map(\.frame.minY).min() ?? app.windows.firstMatch.frame.maxY
    }

    /// P59 evidence: the frames that decide whether the footer clears the
    /// floating tab bar.
    @MainActor
    static func logLayout(_ app: XCUIApplication, _ moment: String) {
        let bar = app.tabBars.firstMatch
        let buttons = bar.buttons.allElementsBoundByIndex.map { "\($0.label)=\($0.frame)" }.joined(separator: " ")
        print("A11Y-LAYOUT \(moment): window=\(app.windows.firstMatch.frame) tabBar=\(bar.frame) tabButtons=[\(buttons)] date=\(app.staticTexts["today.date"].frame) footerText=\(app.staticTexts["On this iPhone only"].firstMatch.frame) footerButton=\(app.buttons["today.localOnly"].frame)")
    }

    /// Waits (up to 10 s) until `element` keeps the same frame for half a
    /// second, so the audit never measures a scroll still settling.
    static func waitUntilStill(_ element: XCUIElement) {
        var last = element.frame
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
            let now = element.frame
            if now == last { return }
            last = now
        }
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

    /// Done on the keyboard, then wait until the keyboard has gone: a tab tap
    /// made while it is still animating away can be dropped (#23 CI run
    /// 45205166133, Chief P54). A wait for a known state, not a retry.
    /// Key export §1.3/§1.7: the Advanced row appears once connected, opens
    /// Screen 1 with Prep's copy, and Cancel goes back. Nothing here
    /// authenticates, so no key is read. Signs out after.
    func testExportRowOpensScreen1AndCancelGoesBack() {
        let app = Self.app()
        app.launch()
        XCTAssertTrue(app.textViews["today.editor"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings.account"].waitForExistence(timeout: 10))
        app.buttons["settings.account"].tap()
        if app.buttons["account.signOut"].waitForExistence(timeout: 3) {
            app.buttons["account.signOut"].tap()
            app.buttons["signOut.confirm"].tap()
        }
        XCTAssertTrue(app.buttons["account.create"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["account.export"].exists, "not offered while signed out")
        app.buttons["account.create"].tap()
        app.buttons["Make a new key"].tap()
        XCTAssertTrue(app.buttons["backup.no"].waitForExistence(timeout: 5))
        app.buttons["backup.no"].tap()
        app.buttons["Continue without backup"].tap()

        let row = app.buttons["account.export"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "offered once connected")
        row.tap()
        XCTAssertTrue(app.staticTexts["Your journal key is your account"].waitForExistence(timeout: 5))
        // Seth P165: the Save Password bullet is on Screen 1 (literal, so
        // removing it from the copy fails here too).
        let savePassword = app.staticTexts["If your browser offers to save your private key as a password, choose Not Now."]
        if !savePassword.exists { app.swipeUp() }
        XCTAssertTrue(savePassword.waitForExistence(timeout: 5), "Save Password bullet shown")
        XCTAssertTrue(app.buttons["export.show"].exists)
        XCTAssertFalse(app.staticTexts["export.key"].exists, "no key on Screen 1")
        app.buttons["export.cancel"].tap()
        XCTAssertTrue(app.buttons["account.signOut"].waitForExistence(timeout: 5), "back on Account")

        app.buttons["account.signOut"].tap()
        app.buttons["signOut.confirm"].tap()
        XCTAssertTrue(app.buttons["account.usedBefore"].waitForExistence(timeout: 5), "signed out")
    }

    static func dismissKeyboard(_ app: XCUIApplication) {
        app.buttons["today.keyboardDone"].tap()
        let gone = NSPredicate(format: "count == 0")
        let wait = XCTNSPredicateExpectation(predicate: gone, object: app.keyboards)
        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 10), .completed, "the keyboard went away")
    }

    /// P55: a test that writes today and then looks for "Today" fails when
    /// the date changes in between (CI run 45292710132 typed at 23:59:51 UTC
    /// and looked at 00:00:12). Close to midnight, start after it instead.
    /// The app and this runner share the simulator's time zone.
    static func waitOutMidnight(margin: TimeInterval = 300) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        guard let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0),
                                               matchingPolicy: .nextTime) else { return }
        let left = midnight.timeIntervalSince(now)
        if left < margin { Thread.sleep(forTimeInterval: left + 2) }
    }

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

    /// Delete today's reflection if there is one, so tests start empty.
    private func clear(_ app: XCUIApplication) {
        let delete = app.buttons["today.delete"]
        guard delete.exists else { return }
        delete.tap()
        app.buttons["Delete"].tap()
        _ = app.staticTexts["today.placeholder"].waitForExistence(timeout: 5)
    }
}
