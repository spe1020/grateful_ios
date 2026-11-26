import XCTest

/// P101 diagnostic probes (Audit f8bab5f7). Local only, never merged.
/// Each runs only the `.elementDetection` audit on Today, at one layout,
/// and logs every static text's frame, so the failing layout names the
/// cause: text cut at the top edge (candidate 1) or something else.
final class P101ElementDetectionProbe: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    /// Probe 1: the launch layout. Nothing is scrolled off the top.
    @MainActor
    func testProbeElementDetectionAtLaunch() throws {
        let app = AppShellUITests.app()
        app.launch()
        XCTAssertTrue(app.textViews["today.editor"].waitForExistence(timeout: 10))
        Self.waitUntilStill(app)
        try audit(app, "launch")
    }

    /// Probe 2: scrolled so content is off the top, but no text line
    /// straddles y=0.
    @MainActor
    func testProbeElementDetectionNoTextStraddlesTop() throws {
        let app = AppShellUITests.app()
        app.launch()
        XCTAssertTrue(app.textViews["today.editor"].waitForExistence(timeout: 10))
        let window = app.windows.firstMatch
        let date = app.staticTexts["today.date"]
        var found = false
        // Drag slowly in small steps in the left margin (where nothing can
        // be pressed), holding at the end so there's no momentum, until the
        // date is off the top and nothing straddles y=0. (A quick drag
        // flings Today straight to its end, where wisdom.author straddles.)
        for step in 0..<30 {
            let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 8, dy: window.frame.height * 0.7))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -20)), withVelocity: .slow, thenHoldForDuration: 0.5)
            Self.waitUntilStill(app)
            let straddling = Self.straddlers(app)
            print("P101-PROBE step=\(step) date=\(date.frame) straddling=\(straddling.count)")
            if date.frame.maxY < 0 && straddling.isEmpty {
                found = true
                break
            }
        }
        XCTAssertTrue(found, "reached a layout with content off the top and no text straddling y=0")
        try audit(app, "no-straddle")
    }

    /// Control: the end layout CI fails on (same drag as the real test).
    @MainActor
    func testProbeElementDetectionAtEnd() throws {
        let app = AppShellUITests.app()
        app.launch()
        XCTAssertTrue(app.textViews["today.editor"].waitForExistence(timeout: 10))
        let window = app.windows.firstMatch
        let date = app.staticTexts["today.date"]
        for _ in 0..<4 {
            let before = date.frame
            let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 8, dy: window.frame.height * 0.7))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -400)))
            Self.waitUntilStill(app)
            if date.frame == before { break }
        }
        try audit(app, "end")
    }

    @MainActor
    private func audit(_ app: XCUIApplication, _ layout: String) throws {
        AppShellUITests.logLayout(app, "probe \(layout)")
        for text in app.staticTexts.allElementsBoundByIndex where text.exists {
            let f = text.frame
            let cut = f.minY < 0 && f.maxY > 0
            print("P101-PROBE-TEXT layout=\(layout) id=\"\(text.identifier)\" frame=\(f) straddlesTop=\(cut) chars=\(text.label.count)")
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "P101 probe \(layout)"
        shot.lifetime = .keepAlways
        add(shot)
        var issues = 0
        try app.performAccessibilityAudit(for: .elementDetection) { issue in
            issues += 1
            print("P101-PROBE-ISSUE layout=\(layout) type=\(issue.auditType.rawValue) compact=\"\(issue.compactDescription)\" element=\(issue.element.map { "\($0.identifier) \($0.frame)" } ?? "nil")")
            return true // record, don't stop: the count is the result
        }
        print("P101-PROBE-RESULT layout=\(layout) elementDetectionIssues=\(issues)")
    }

    @MainActor
    private static func straddlers(_ app: XCUIApplication) -> [XCUIElement] {
        app.staticTexts.allElementsBoundByIndex.filter { $0.exists && $0.frame.minY < 0 && $0.frame.maxY > 0 }
    }

    @MainActor
    private static func waitUntilStill(_ app: XCUIApplication) {
        AppShellUITests.waitUntilStill(app.staticTexts["today.date"])
    }
}
