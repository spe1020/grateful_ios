import XCTest
import Security
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import NostrCore
@testable import GratefulDay

// Show journal key: the S7, S7+, D2 and D3 tests from the key export doc
// r3 (§1.6), plus source checks. Every key here is synthetic, generated per
// test run.

/// Counts every read of the primary item (S1, S7+).
private final class CountingReader: PrimaryKeyReading {
    var result: KeyVault.PrimaryRead
    private(set) var reads = 0
    init(_ result: KeyVault.PrimaryRead) { self.result = result }
    func readPrimary() -> KeyVault.PrimaryRead {
        reads += 1
        return result
    }
}

/// Returns a fixed outcome and counts attempts.
@MainActor
private final class FakeAuthenticator: DeviceOwnerAuthenticating {
    var outcome: DeviceAuthOutcome
    private(set) var attempts = 0
    private(set) var reasons: [String] = []
    init(_ outcome: DeviceAuthOutcome) { self.outcome = outcome }
    func authenticate(reason: String) async -> DeviceAuthOutcome {
        attempts += 1
        reasons.append(reason)
        return outcome
    }
}

/// Records every write and its options, and bumps `changeCount` like
/// UIPasteboard. The protocol has only `setItems`, so the flow can't read or
/// clear the pasteboard through it.
@MainActor
private final class FakePasteboard: ExportPasteboard {
    private(set) var changeCount = 0
    private(set) var writes: [(items: [[String: Any]], options: [UIPasteboard.OptionsKey: Any])] = []
    private var stored: [[String: Any]] = []

    func setItems(_ items: [[String: Any]], options: [UIPasteboard.OptionsKey: Any]) {
        writes.append((items, options))
        stored = items
        changeCount += 1
    }

    var text: String? { stored.first?[UTType.utf8PlainText.identifier] as? String }
}

@MainActor
final class KeyExportTests: XCTestCase {
    private var secret: Data!
    private var owner: String!
    private var reader: CountingReader!
    private var pasteboard: FakePasteboard!
    private var announcements: [String] = []

    override func setUp() async throws {
        secret = try NostrKeys.generatePrivateKey()
        owner = KeyVault.pubkeyHex(for: secret)
        reader = CountingReader(.key(secret: secret, pubkey: owner))
        pasteboard = FakePasteboard()
        announcements = []
    }

    private func session(_ auth: DeviceOwnerAuthenticating, owner: String? = nil,
                         timeout: Duration = .seconds(120)) -> KeyExportSession {
        KeyExportSession(owner: owner ?? self.owner, reader: reader, authenticator: auth,
                         pasteboard: pasteboard, timeout: timeout,
                         announce: { [weak self] in self?.announcements.append($0) })
    }

    /// Authenticated, Screen 3 appeared, key shown.
    private func revealed(timeout: Duration = .seconds(120)) async -> KeyExportSession {
        let s = session(FakeAuthenticator(.success), timeout: timeout)
        await s.authenticate()
        s.load()
        s.toggleShown()
        return s
    }

    private var expectedNsec: String { try! NostrKeys.nsec(secret) }

    // MARK: S7 behaviour

    func testWithNoAuthenticationNothingIsReadOrRendered() {
        let s = session(FakeAuthenticator(.success))
        s.load()
        s.toggleShown()
        s.copy()
        XCTAssertEqual(reader.reads, 0)
        XCTAssertEqual(s.phase, .locked)
        XCTAssertNil(s.displayedGroups)
        XCTAssertFalse(s.isRevealing)
        XCTAssertTrue(pasteboard.writes.isEmpty)
    }

    func testCancelledOrFailedAuthenticationShowsNothing() async {
        let auth = FakeAuthenticator(.cancelledOrFailed)
        let s = session(auth)
        await s.authenticate()
        XCTAssertEqual(auth.attempts, 1)
        XCTAssertEqual(s.gate, .idle, "back to Screen 1 quietly, no message")
        XCTAssertFalse(s.isRevealing, "Screen 3 isn't opened")
        s.load()
        XCTAssertEqual(reader.reads, 0)
        XCTAssertNil(s.displayedGroups)
    }

    func testBackgroundingHidesTheKeyAndNeedsANewAuthentication() async {
        let s = await revealed()
        XCTAssertNotNil(s.displayedGroups)
        s.scenePhaseChanged(.background)
        XCTAssertNil(s.displayedGroups)
        XCTAssertEqual(s.phase, .locked)
        XCTAssertFalse(s.isRevealing, "popped back to Screen 1")
        s.load()
        XCTAssertEqual(reader.reads, 1, "no second read without a new authentication")
        XCTAssertNil(s.displayedGroups)
        await s.authenticate()
        s.load()
        XCTAssertEqual(reader.reads, 2)
        XCTAssertEqual(s.phase, .ready)
    }

    func testTheTwoMinuteTimeoutHidesTheKey() async throws {
        XCTAssertEqual(KeyExportSession(owner: owner, reader: reader).timeout, .seconds(120),
                       "the default is 2 minutes")
        let s = await revealed(timeout: .milliseconds(50))
        XCTAssertNotNil(s.displayedGroups)
        for _ in 0..<100 where s.isRevealing { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(s.isRevealing, "popped back to Screen 1")
        XCTAssertNil(s.displayedGroups)
        XCTAssertEqual(s.phase, .locked)
    }

    func testWhileTheScreenIsCapturedTheKeyIsNotRendered() async {
        let s = await revealed()
        XCTAssertNotNil(s.displayedGroups)
        s.isCaptured = true
        XCTAssertNil(s.displayedGroups)
        s.toggleShown()
        XCTAssertNil(s.displayedGroups, "[Show] does nothing while captured")
        s.copy()
        XCTAssertEqual(pasteboard.writes.count, 1, "Copy still works")
        s.isCaptured = false
        XCTAssertNil(s.displayedGroups, "capture ending doesn't re-show the key by itself")
    }

    func testThePasteboardItemIsLocalOnlyAndExpiresIn60Seconds() async throws {
        let s = session(FakeAuthenticator(.success))
        await s.authenticate()
        s.load()
        let before = Date.now
        s.copy()
        XCTAssertNil(s.displayedGroups, "copying doesn't need the key shown")
        XCTAssertEqual(pasteboard.writes.count, 1)
        let write = try XCTUnwrap(pasteboard.writes.first)
        XCTAssertEqual(write.items.count, 1)
        XCTAssertEqual(Array(write.items[0].keys), [UTType.utf8PlainText.identifier])
        XCTAssertEqual(write.options[.localOnly] as? Bool, true, "no Universal Clipboard")
        let expiry = try XCTUnwrap(write.options[.expirationDate] as? Date)
        XCTAssertEqual(expiry.timeIntervalSince(before), 60, accuracy: 5)
        XCTAssertEqual(s.copiedNotice, true)
        XCTAssertEqual(announcements, [AccountCopy.exportCopied], "one accessibility announcement")
    }

    func testTheRowIsOfferedOnlyWhenConnected() {
        let p = owner!
        XCTAssertTrue(KeyExport.isOffered(for: .connected(pubkey: p)))
        let hidden: [AccountModel.State] = [
            .guest, .signedOut(pubkey: p), .keyMissing(pubkey: p), .mismatch(keyPubkey: p, markerPubkey: String(repeating: "0", count: 64)),
            .unknown, .locked, .keyUnavailable(errSecInteractionNotAllowed),
        ]
        for state in hidden { XCTAssertFalse(KeyExport.isOffered(for: state), "\(state)") }
    }

    func testTheExportedNsecDecodesBackToTheAccountsPubkey() async throws {
        let s = await revealed()
        s.copy()
        let copied = try XCTUnwrap(pasteboard.text)
        XCTAssertTrue(copied.hasPrefix("nsec1"))
        let decoded = try NostrKeys.decodeNsec(copied)
        XCTAssertEqual(KeyVault.pubkeyHex(for: decoded), owner)
        XCTAssertEqual(s.displayedGroups?.joined(), copied, "what's shown is what's copied")
        XCTAssertEqual(copied, expectedNsec)
    }

    func testTheKeyIsShownInGroupsOfFour() async {
        let s = await revealed()
        let groups = s.displayedGroups ?? []
        XCTAssertFalse(groups.isEmpty)
        XCTAssertTrue(groups.dropLast().allSatisfy { $0.count == 4 })
        XCTAssertTrue((1...4).contains(groups.last?.count ?? 0))
    }

    func testAScreenshotNoticeOnlyWhenTheKeyIsShown() async {
        let s = await revealed()
        s.toggleShown()
        s.screenshotTaken()
        XCTAssertFalse(s.screenshotNotice, "hidden: nothing to warn about")
        s.toggleShown()
        s.screenshotTaken()
        XCTAssertTrue(s.screenshotNotice)
    }

    func testLeavingTheScreenDropsTheKey() async {
        let s = await revealed()
        s.hide()
        XCTAssertNil(s.displayedGroups)
        XCTAssertEqual(s.phase, .locked)
        s.copy()
        XCTAssertTrue(pasteboard.writes.isEmpty, "nothing left to copy")
    }

    // MARK: S7+

    func testTheVaultIsReadOnlyAfterAuthenticationSucceedsAndScreen3Appears() async {
        let auth = FakeAuthenticator(.cancelledOrFailed)
        let s = session(auth)
        await s.authenticate()
        XCTAssertEqual(reader.reads, 0)
        auth.outcome = .success
        await s.authenticate()
        XCTAssertTrue(s.isRevealing)
        XCTAssertEqual(reader.reads, 0, "never preloaded: read when Screen 3 appears")
        s.load()
        XCTAssertEqual(reader.reads, 1)
        s.load()
        XCTAssertEqual(reader.reads, 1, "one read per authentication")
        XCTAssertEqual(auth.reasons, [AccountCopy.exportAuthReason, AccountCopy.exportAuthReason])
    }

    func testAPubkeyMismatchRendersNothing() async throws {
        let other = try XCTUnwrap(KeyVault.pubkeyHex(for: try NostrKeys.generatePrivateKey()))
        let s = session(FakeAuthenticator(.success), owner: other)
        await s.authenticate()
        s.load()
        XCTAssertEqual(s.phase, .mismatch, "F6 copy, nothing else")
        s.toggleShown()
        XCTAssertNil(s.displayedGroups)
        s.copy()
        XCTAssertTrue(pasteboard.writes.isEmpty)
    }

    func testAMislabelledPrimaryItemIsCheckedAgainstItsOwnSecret() async throws {
        // The read reports the right pubkey, but the secret is someone else's.
        reader.result = .key(secret: try NostrKeys.generatePrivateKey(), pubkey: owner)
        let s = session(FakeAuthenticator(.success))
        await s.authenticate()
        s.load()
        XCTAssertEqual(s.phase, .mismatch)
        XCTAssertNil(s.displayedGroups)
    }

    func testNoKeyOnThisIPhoneShowsNothing() async {
        for result: KeyVault.PrimaryRead in [.notFound, .locked, .failed(errSecDecode)] {
            reader.result = result
            let s = session(FakeAuthenticator(.success))
            await s.authenticate()
            s.load()
            XCTAssertNotEqual(s.phase, .ready)
            s.toggleShown()
            XCTAssertNil(s.displayedGroups)
        }
    }

    func testInactiveHidesTheKeyAndPopsBackToScreen1() async {
        let s = await revealed()
        XCTAssertNotNil(s.displayedGroups)
        s.scenePhaseChanged(.inactive)
        XCTAssertNil(s.displayedGroups)
        XCTAssertFalse(s.isRevealing, "popped back to Screen 1")
        XCTAssertEqual(s.phase, .locked)
        s.load()
        XCTAssertEqual(reader.reads, 1, "showing it again needs a new authentication")
    }

    func testActiveDoesNotHideTheKey() async {
        let s = await revealed()
        s.scenePhaseChanged(.active)
        XCTAssertNotNil(s.displayedGroups)
    }

    // MARK: E1 (Seth, option 1): no clear-on-hide

    /// Hiding, `.inactive` and the timeout leave the pasteboard unchanged:
    /// the copied key stays until its 60 s expiry, and nothing else is written.
    func testHidingInactiveAndTimeoutLeaveThePasteboardUnchanged() async throws {
        var s = await revealed()
        s.copy()
        s.hide()
        XCTAssertEqual(pasteboard.text, expectedNsec, "hide")
        XCTAssertEqual(pasteboard.changeCount, 1)

        pasteboard = FakePasteboard()
        s = await revealed()
        s.copy()
        s.scenePhaseChanged(.inactive)
        XCTAssertEqual(pasteboard.text, expectedNsec, ".inactive")
        XCTAssertEqual(pasteboard.changeCount, 1)

        pasteboard = FakePasteboard()
        s = await revealed(timeout: .milliseconds(50))
        s.copy()
        for _ in 0..<100 where s.isRevealing { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(s.isRevealing)
        XCTAssertEqual(pasteboard.text, expectedNsec, "timeout")
        XCTAssertEqual(pasteboard.changeCount, 1)
    }

    // MARK: D2

    func testNoPasscodeReadsNothingAndShowsTheD2Copy() async {
        let s = session(FakeAuthenticator(.passcodeNotSet))
        await s.authenticate()
        XCTAssertEqual(s.gate, .noPasscode, "Screen 1 shows AccountCopy.exportNoPasscode")
        XCTAssertFalse(s.isRevealing)
        s.load()
        XCTAssertEqual(reader.reads, 0)
        XCTAssertNil(s.displayedGroups)
        XCTAssertEqual(AccountCopy.exportNoPasscode,
                       "To show your journal key, turn on a passcode for this iPhone in Settings.")
    }

    // MARK: Copy (Prep's final strings)

    func testExportCopyIsPrepsFinalWording() {
        XCTAssertEqual(AccountCopy.exportSection, "Advanced")
        XCTAssertEqual(AccountCopy.exportRow, "Use your journal key in another app")
        XCTAssertEqual(AccountCopy.exportTitle, "Journal key")
        XCTAssertEqual(AccountCopy.exportIntroHeading, "Your journal key is your account")
        XCTAssertEqual(AccountCopy.exportIntroBody1, "Your journal key is your Nostr secret key (nsec). Paste it into another Nostr app to use the same account there.")
        XCTAssertEqual(AccountCopy.exportIntroBody2, "Anyone who has it can read all your private reflections, including earlier versions, and save to your account as you. This can't be undone by changing a password. There isn't one.")
        XCTAssertEqual(AccountCopy.exportBullets, [
            "Only paste it into an app you trust.",
            "Never send it in a message or email, or post it.",
            "No one from Grateful Day will ever ask you for it.",
        ])
        XCTAssertEqual(AccountCopy.exportShow, "Show journal key")
        XCTAssertEqual(AccountCopy.cancel, "Cancel")
        XCTAssertEqual(AccountCopy.exportAuthReason, "Confirm it's you to show your journal key.")
        XCTAssertEqual(AccountCopy.exportReveal, "Show")
        XCTAssertEqual(AccountCopy.exportConceal, "Hide")
        XCTAssertEqual(AccountCopy.exportCopy, "Copy journal key")
        XCTAssertEqual(AccountCopy.exportCopied, "Copied. It will be cleared from the clipboard in 1 minute. Paste it now.")
        XCTAssertEqual(AccountCopy.exportCaptured, "Your screen is being recorded or shared, so your key is hidden.")
        XCTAssertEqual(AccountCopy.exportScreenshot, "Your screenshot includes your journal key. Delete it from Photos, and from Recently Deleted.")
        XCTAssertEqual(AccountCopy.exportHiddenLabel, "Journal key, hidden")
        XCTAssertEqual(AccountCopy.exportVoiceOverHint, "VoiceOver reads your key aloud. Use headphones if others are nearby.")
        XCTAssertEqual(AccountCopy.exportDone, "Done")
    }

    /// S4+: the Face ID reason is in the built Info.plist, matching the prompt.
    func testFaceIDUsageDescriptionMatchesTheReason() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "NSFaceIDUsageDescription") as? String,
                       AccountCopy.exportAuthReason)
    }

    // MARK: Source checks

    private static let appRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    private static let exportFiles = ["GratefulDay/Account/KeyExport.swift", "GratefulDay/Account/KeyExportView.swift"]

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.appRoot.appendingPathComponent(path), encoding: .utf8)
    }

    /// Every Swift file in the app target, by path relative to App/.
    private func appSources() throws -> [(path: String, text: String)] {
        let dir = Self.appRoot.appendingPathComponent("GratefulDay")
        let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertGreaterThan(files.count, 10, "found the app sources")
        return try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// Code only: comment lines removed.
    private func code(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).filter {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
        }
    }

    private func exportCode() throws -> String {
        try Self.exportFiles.map { try code(source($0)).joined(separator: "\n") }.joined(separator: "\n")
    }

    /// S7+: no SyncLog, StorageLog or Logger call takes a key or nsec, anywhere in the app.
    func testNoLogCallTakesAKeyOrNsec() throws {
        let call = try NSRegularExpression(pattern: #"(SyncLog|StorageLog)\.\w+\(|[Ll]ogger\.\w+\(|\bLogger\("#)
        let literal = try NSRegularExpression(pattern: #""[^"]*""#)
        for (path, text) in try appSources() {
            for line in code(text) {
                let range = NSRange(line.startIndex..., in: line)
                guard call.firstMatch(in: line, range: range) != nil else { continue }
                let withoutLiterals = literal.stringByReplacingMatches(in: line, range: range, withTemplate: "\"\"")
                XCTAssertNil(withoutLiterals.range(of: #"nsec|secret|privateKey|\bkey\b"#, options: [.regularExpression, .caseInsensitive]),
                             "\(path): \(line)")
            }
        }
        let export = try exportCode()
        for banned in ["SyncLog", "StorageLog", "Logger", "os_log", "NSLog", "print(", "debugPrint(", "dump("] {
            XCTAssertFalse(export.contains(banned), "the export flow logs nothing: \(banned)")
        }
    }

    /// S2/S4: the export flow persists nothing and makes no network call.
    func testTheExportFlowStoresAndSendsNothing() throws {
        let export = try exportCode()
        for banned in ["UserDefaults", "AppStorage", "SceneStorage", "ModelContext", "FileManager", ".write(to",
                       "URLSession", "SyncService", "RelayTransport", "RelayPublisher", "RelayFetcher", ".environment("] {
            XCTAssertFalse(export.contains(banned), banned)
        }
        XCTAssertFalse(try code(source("GratefulDay/Account/AccountModel.swift")).joined().contains("KeyExportSession"),
                       "the key never lives in AccountModel (S2+)")
    }

    /// D3: the only key write is the local-only, 60 s `setItems`, and the
    /// flow has no other way out (no `.string =`, selection, share sheet).
    func testTheOnlyPasteboardWriteIsLocalOnlyWithA60SecondExpiry() throws {
        for (path, text) in try appSources() {
            XCTAssertFalse(text.contains("UIPasteboard.general.string"), path)
            for line in code(text) where line.contains(".setItems(") {
                if path == "KeyExport.swift" {
                    XCTAssertTrue(line.contains("pasteboard.setItems([[UTType.utf8PlainText.identifier: nsec]], options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(60)])"), line)
                } else {
                    XCTAssertFalse(line.contains("nsec") || line.contains("secret"), "\(path): \(line)")
                }
            }
        }
        let export = try exportCode()
        XCTAssertEqual(export.components(separatedBy: ".setItems(").count - 1, 1, "exactly one write")
        for banned in [".items", "changeCount", "clearPasteboard", ".string =", ".string=", "textSelection", "ShareLink", "UIActivityViewController", "UIDocumentPicker", "fileExporter", "QRCode", "CIFilter"] {
            XCTAssertFalse(export.contains(banned), banned)
        }
    }

    /// D2/S1+: one gate, `.deviceOwnerAuthentication`, on a fresh context
    /// with no reuse; no pre-check and no biometrics-only fallback.
    func testTheOnlyGateIsDeviceOwnerAuthentication() throws {
        var evaluateCalls = 0
        for (path, text) in try appSources() {
            let lines = code(text).joined(separator: "\n")
            XCTAssertFalse(lines.contains("canEvaluatePolicy"), path)
            XCTAssertFalse(lines.contains("deviceOwnerAuthenticationWithBiometrics"), path)
            evaluateCalls += lines.components(separatedBy: "evaluatePolicy(").count - 1
        }
        XCTAssertEqual(evaluateCalls, 1)
        let auth = try code(source("GratefulDay/Account/KeyExport.swift")).joined(separator: "\n")
        XCTAssertTrue(auth.contains("evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)"))
        XCTAssertTrue(auth.contains("let context = LAContext()"))
        XCTAssertTrue(auth.contains("context.touchIDAuthenticationAllowableReuseDuration = 0"))
    }

    /// D4/S4+: the stored key is unchanged: no item access control, and the
    /// flow never writes or deletes Keychain items.
    func testTheStoredKeyIsUnchanged() throws {
        for (path, text) in try appSources() {
            XCTAssertFalse(text.contains("SecAccessControl"), path)
            XCTAssertFalse(text.contains("userPresence"), path)
        }
        let vault = try source("GratefulDay/Account/KeyVault.swift")
        XCTAssertTrue(vault.contains("synchronizable: false, accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly"))
        XCTAssertTrue(vault.contains("synchronizable: true, accessibility: kSecAttrAccessibleWhenUnlocked)"))
        let export = try exportCode()
        for banned in ["savePrimaryVerified", "saveBackup", "deletePrimary", "deleteBackup", "backupSecret", "listBackups",
                       "SecItem", "keychain."] {
            XCTAssertFalse(export.contains(banned), banned)
        }
    }

    /// S4+: the only new Info.plist key is NSFaceIDUsageDescription.
    func testTheOnlyAddedInfoPlistKeyIsFaceIDUsage() throws {
        let project = try source("GratefulDay.xcodeproj/project.pbxproj")
        let regex = try NSRegularExpression(pattern: #"INFOPLIST_KEY_(\w+)"#)
        let keys = Set(regex.matches(in: project, range: NSRange(project.startIndex..., in: project)).map {
            String(project[Range($0.range(at: 1), in: project)!])
        })
        XCTAssertEqual(keys, ["CFBundleDisplayName", "UIApplicationSceneManifest_Generation", "UILaunchScreen_Generation",
                              "UISupportedInterfaceOrientations", "NSFaceIDUsageDescription"])
        XCTAssertEqual(project.components(separatedBy: #"INFOPLIST_KEY_NSFaceIDUsageDescription = "Confirm it's you to show your journal key.";"#).count - 1, 2,
                       "Debug and Release")
    }

    /// S6: in AccountCopy, "nsec" appears only on the F5 import screen and Screen 1.
    func testNsecAppearsOnlyOnImportAndScreen1() throws {
        let lines = code(try source("GratefulDay/Account/AccountCopy.swift")).filter { $0.lowercased().contains("nsec") }
        XCTAssertEqual(lines.count, 2, lines.joined(separator: "\n"))
        XCTAssertTrue(lines.contains { $0.contains("static let importPrompt") })
        XCTAssertTrue(lines.contains { $0.contains("static let exportIntroBody1") })
    }
}
