import XCTest

/// D2: on the conflict screen, tapping an option chooses that option, and
/// Done applies it. Runs on the Debug-only `-uiTestConflictFixture`, which
/// covers the app with the real conflict screen for one seeded day (an
/// in-memory store under a throwaway key; no relays) and, after Done, lists
/// what was applied.
final class ConflictReviewUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // Copy (ConflictCopy, SyncCopy.swift) and the fixture's texts.
    private static let keepBoth = "Keep both"
    private static let keepThisIPhone = "Keep this iPhone's"
    private static let keepAccount = "Keep your account's"
    private static let letItStayDeleted = "Let it stay deleted"
    private static let deleteEverywhere = "Delete it everywhere"
    private static let accountText = "Fixture account text"
    private static let iPhoneText = "Fixture iPhone text"
    private static let notKept = "You kept the other version of this day."
    private static let deletedFromAccountReason = "This day was deleted from your account."
    private static let deletedHereReason = "You deleted this day here."

    /// The option, its line under the options.
    private static let bothChanged: [(String, String)] = [
        (keepBoth, "Both texts stay on this day as separate notes, your account's first."),
        (keepThisIPhone, "Your account's text goes to Set aside."),
        (keepAccount, "This iPhone's text goes to Set aside."),
    ]
    private static let deletedHere: [(String, String)] = [
        (keepAccount, "This day comes back on this iPhone with your account's text."),
        (deleteEverywhere, "Your account's text goes to Set aside on this iPhone, and this day is deleted from your account."),
    ]
    private static let deletedFromAccount: [(String, String)] = [
        (keepThisIPhone, "This day goes back to your account with what you wrote here."),
        (letItStayDeleted, "What you wrote here goes to Set aside, and this day is removed from this iPhone."),
    ]

    /// What Done should leave for the day.
    private struct Applied {
        var notes: [String]
        var deleted: Bool
        var syncState: String
        var setAside: [String] = []
        var setAsideReason: [String] = []
    }

    // MARK: - §2 both changed

    @MainActor
    func testBothChangedKeepBoth() {
        run("bothChanged", Self.bothChanged, choose: Self.keepBoth,
            Applied(notes: [Self.accountText, Self.iPhoneText], deleted: false, syncState: "localOnly"))
    }

    @MainActor
    func testBothChangedKeepThisIPhone() {
        run("bothChanged", Self.bothChanged, choose: Self.keepThisIPhone,
            Applied(notes: [Self.iPhoneText], deleted: false, syncState: "localOnly",
                    setAside: [Self.accountText], setAsideReason: [Self.notKept]))
    }

    @MainActor
    func testBothChangedKeepAccount() {
        run("bothChanged", Self.bothChanged, choose: Self.keepAccount,
            Applied(notes: [Self.accountText], deleted: false, syncState: "synced",
                    setAside: [Self.iPhoneText], setAsideReason: [Self.notKept]))
    }

    // MARK: - §9 deleted here, changed in the account

    @MainActor
    func testDeletedHereKeepAccount() {
        run("deletedHere", Self.deletedHere, choose: Self.keepAccount,
            Applied(notes: [Self.accountText], deleted: false, syncState: "synced"))
    }

    /// With no relays the deletion can only wait to be sent: the day stays
    /// deleted here, unsent (`localOnly`), the account's text in Set aside.
    @MainActor
    func testDeletedHereDeleteEverywhere() {
        run("deletedHere", Self.deletedHere, choose: Self.deleteEverywhere,
            Applied(notes: [], deleted: true, syncState: "localOnly",
                    setAside: [Self.accountText], setAsideReason: [Self.deletedHereReason]))
    }

    // MARK: - §7 deleted from the account, changed here

    @MainActor
    func testDeletedFromAccountKeepThisIPhone() {
        run("deletedFromAccount", Self.deletedFromAccount, choose: Self.keepThisIPhone,
            Applied(notes: [Self.iPhoneText], deleted: false, syncState: "localOnly"))
    }

    @MainActor
    func testDeletedFromAccountLetItStayDeleted() {
        run("deletedFromAccount", Self.deletedFromAccount, choose: Self.letItStayDeleted,
            Applied(notes: [], deleted: true, syncState: "synced",
                    setAside: [Self.iPhoneText], setAsideReason: [Self.deletedFromAccountReason]))
    }

    // MARK: - Steps

    /// Opens the fixture, checks the default, taps every option (each must
    /// become the only one selected, with its line), taps `choose`, presses
    /// Done and checks what was applied.
    @MainActor
    private func run(_ kind: String, _ options: [(String, String)], choose: String, _ expected: Applied,
                     file: StaticString = #filePath, line: UInt = #line) {
        let app = AppShellUITests.app()
        app.launchArguments += ["-uiTestConflictFixture", kind]
        app.launch()
        XCTAssertTrue(app.buttons["conflict.done"].waitForExistence(timeout: 15), "the conflict screen", file: file, line: line)

        let choices = app.buttons.matching(identifier: "conflict.choice")
        XCTAssertEqual(choices.count, options.count, "one button per option", file: file, line: line)
        XCTAssertEqual(choices.allElementsBoundByIndex.map { $0.label }, options.map(\.0), "copy and order", file: file, line: line)
        assertSelected(options[0], among: options, app, "default", file: file, line: line)

        for pick in options + options.filter({ $0.0 == choose }) {
            option(pick.0, app).tap()
            assertSelected(pick, among: options, app, "after tapping \(pick.0)", file: file, line: line)
        }

        app.buttons["conflict.done"].tap()
        XCTAssertTrue(app.staticTexts["fixture.deleted"].waitForExistence(timeout: 10), "Done closed the screen", file: file, line: line)
        XCTAssertEqual(app.staticTexts.matching(identifier: "fixture.dayNote").allElementsBoundByIndex.map { $0.label },
                       expected.notes, "the day's text", file: file, line: line)
        XCTAssertEqual(app.staticTexts["fixture.deleted"].label, expected.deleted ? "deleted" : "not deleted", file: file, line: line)
        XCTAssertEqual(app.staticTexts["fixture.syncState"].label, expected.syncState, file: file, line: line)
        XCTAssertEqual(app.staticTexts.matching(identifier: "fixture.setAside").allElementsBoundByIndex.map { $0.label },
                       expected.setAside, "Set aside", file: file, line: line)
        XCTAssertEqual(app.staticTexts.matching(identifier: "fixture.setAsideReason").allElementsBoundByIndex.map { $0.label },
                       expected.setAsideReason, "Set aside reason", file: file, line: line)
        XCTAssertEqual(app.staticTexts["fixture.openConflicts"].label, "0", "the conflict is resolved", file: file, line: line)
    }

    @MainActor
    private func option(_ title: String, _ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "conflict.choice").matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    @MainActor
    private func assertSelected(_ selected: (String, String), among options: [(String, String)], _ app: XCUIApplication,
                                _ moment: String, file: StaticString, line: UInt) {
        for (title, _) in options {
            XCTAssertEqual(option(title, app).isSelected, title == selected.0,
                           "\(moment): \(title) is \(title == selected.0 ? "" : "not ")selected", file: file, line: line)
        }
        XCTAssertEqual(app.staticTexts["conflict.choiceLine"].label, selected.1, "\(moment): the line", file: file, line: line)
    }
}
