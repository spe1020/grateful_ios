import Foundation
import LocalAuthentication
import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import NostrCore

// Show journal key (export the nsec): the logic behind Screens 1–3.
// Design: `PLANS/GRATEFUL_DAY_IOS_KEY_EXPORT_AND_SAVE_SYNC_PRODUCT_2026_11_22.md`
// r3 Part 1 (§1.3–1.7, S1–S7, the r2 tightenings, D2–D4) and Prep's final
// copy. Security sign-off: `RESEARCH/GRATEFUL_DAY_IOS_KEY_EXPORT_R3_SECURITY_SIGNOFF_2026_11_23.md`.
//
// Never log, store or send the key from here: no SyncLog, StorageLog,
// Logger, print, UserDefaults, AppStorage, SceneStorage or network (S2, S4).
// This flow only reads the stored key; it never changes how it's stored (D4).

enum KeyExport {
    /// §1.3: the row is offered only while connected, which means the key
    /// was read on this iPhone and matches the journal. Signed out, guest,
    /// key missing, mismatch, unknown, locked and unreadable all hide it.
    static func isOffered(for state: AccountModel.State) -> Bool {
        if case .connected = state { return true }
        return false
    }

    /// The key in groups of 4 characters, for display (§1.4 Screen 3).
    static func groups(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for c in text {
            current.append(c)
            if current.count == 4 { out.append(current); current = "" }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// The row of dots shown while the key is hidden. Not derived from the key.
    static let hiddenGroups = Array(repeating: "••••", count: 16)
}

// MARK: - Injected dependencies

/// What the flow may read from the Keychain: the primary item only, never a
/// backup item (S1+). `KeyVault` already does this; nothing here writes.
protocol PrimaryKeyReading {
    func readPrimary() -> KeyVault.PrimaryRead
}

extension KeyVault: PrimaryKeyReading {}

enum DeviceAuthOutcome: Equatable {
    case success
    /// `LAError.passcodeNotSet` (D2): the key is never read.
    case passcodeNotSet
    /// Cancelled or failed, for any other reason: back to Screen 1 quietly.
    case cancelledOrFailed
}

/// The app-level gate (S5, D4). It isn't cryptographic protection: anyone
/// with the unlocked phone and its passcode can pass it.
@MainActor
protocol DeviceOwnerAuthenticating {
    func authenticate(reason: String) async -> DeviceAuthOutcome
}

/// D2/S1+: a fresh `LAContext` per attempt with no reuse window, and
/// `.deviceOwnerAuthentication` (biometrics with passcode fallback) as the
/// only gate. No pre-check that could skip it, and no biometrics-only policy.
struct SystemDeviceOwnerAuthenticator: DeviceOwnerAuthenticating {
    func authenticate(reason: String) async -> DeviceAuthOutcome {
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 0
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, error in
                if ok {
                    continuation.resume(returning: .success)
                } else if (error as? LAError)?.code == .passcodeNotSet {
                    continuation.resume(returning: .passcodeNotSet)
                } else {
                    continuation.resume(returning: .cancelledOrFailed)
                }
            }
        }
    }
}

/// The one pasteboard operation the flow uses: the D3 write. The flow never
/// reads or clears the pasteboard (Seth, E1 option 1: the 60 s expiry is the
/// only clearing). `UIPasteboard` conforms; tests inject a recording fake.
@MainActor
protocol ExportPasteboard: AnyObject {
    func setItems(_ items: [[String: Any]], options: [UIPasteboard.OptionsKey: Any])
}

extension UIPasteboard: ExportPasteboard {}

// MARK: - Session

/// One visit to the export flow. Owned as screen-local `@State` by Screen 1,
/// never by `AccountModel` or the environment (S2+). It holds the key only
/// while Screen 3 shows it, and drops it whenever the key hides.
@MainActor
@Observable
final class KeyExportSession {
    enum Gate: Equatable {
        case idle, authenticating
        /// D2: no device passcode. The D2 copy is shown; nothing is read.
        case noPasscode
    }

    enum Phase: Equatable {
        /// Nothing read. Screen 3 renders nothing from the key.
        case locked
        /// Read, and its pubkey matches the active account (S1+).
        case ready
        /// The key read doesn't belong to the active account: F6 copy, nothing else.
        case mismatch
        /// No key on this iPhone: F6 "key missing" copy, nothing else.
        case keyMissing
        /// Locked or unreadable: nothing is shown.
        case unavailable
    }

    /// The active account's pubkey when the flow was opened.
    let owner: String
    private(set) var gate: Gate = .idle
    /// Drives the push of Screen 3. Hiding sets it back, popping to Screen 1.
    var isRevealing = false
    private(set) var phase: Phase = .locked
    /// [Show] was tapped. The key is displayed only if this holds and the
    /// screen isn't captured (`displayedGroups`).
    private(set) var isShown = false
    /// Screen recording or mirroring: the key shows dots and [Show] is off.
    var isCaptured = false {
        didSet { if isCaptured { isShown = false } }
    }
    private(set) var copiedNotice = false
    private(set) var screenshotNotice = false

    private let reader: PrimaryKeyReading
    private let authenticator: DeviceOwnerAuthenticating
    private let pasteboard: ExportPasteboard
    /// How long Screen 3 stays before it hides itself (§1.4: 2 minutes).
    let timeout: Duration
    private let announce: (String) -> Void

    /// Set by a successful authentication, used up by the one read it allows.
    private var authorized = false
    /// The bech32 key, only between a read and the next hide (S2).
    private var nsec: String?
    private var timeoutTask: Task<Void, Never>?

    init(owner: String,
         reader: PrimaryKeyReading,
         authenticator: DeviceOwnerAuthenticating = SystemDeviceOwnerAuthenticator(),
         pasteboard: ExportPasteboard = UIPasteboard.general,
         timeout: Duration = .seconds(120),
         announce: @escaping (String) -> Void = { UIAccessibility.post(notification: .announcement, argument: $0) }) {
        self.owner = owner
        self.reader = reader
        self.authenticator = authenticator
        self.pasteboard = pasteboard
        self.timeout = timeout
        self.announce = announce
    }

    /// The groups to render, or nil when the key must not be on screen.
    var displayedGroups: [String]? {
        guard isShown, !isCaptured, phase == .ready, let nsec else { return nil }
        return KeyExport.groups(nsec)
    }

    // MARK: Screen 1 → 2

    /// [Show journal key]: device authentication (Screen 2). Only a success
    /// opens Screen 3; nothing is read here (S1).
    func authenticate() async {
        guard gate != .authenticating, !isRevealing else { return }
        gate = .authenticating
        let outcome = await authenticator.authenticate(reason: AccountCopy.exportAuthReason)
        switch outcome {
        case .success:
            gate = .idle
            authorized = true
            isRevealing = true
        case .passcodeNotSet:
            gate = .noPasscode
        case .cancelledOrFailed:
            gate = .idle
        }
    }

    // MARK: Screen 3

    /// Screen 3 appeared: read the key, once per authentication (S1), and
    /// check it belongs to the active account before anything renders (S1+).
    func load() {
        guard authorized, phase == .locked else { return }
        authorized = false
        startTimeout()
        switch reader.readPrimary() {
        case .key(let secret, _):
            guard KeyVault.pubkeyHex(for: secret) == owner,
                  let encoded = try? NostrKeys.nsec(secret),
                  let decoded = try? NostrKeys.decodeNsec(encoded),
                  KeyVault.pubkeyHex(for: decoded) == owner
            else { phase = .mismatch; return }
            nsec = encoded
            phase = .ready
        case .notFound:
            phase = .keyMissing
        case .locked, .failed:
            phase = .unavailable
        }
    }

    /// [Show] / [Hide]. Off while the screen is captured.
    func toggleShown() {
        guard phase == .ready, !isCaptured else { return }
        isShown.toggle()
    }

    /// [Copy journal key]. Works with the key hidden, and while captured.
    /// D3: this is the only pasteboard write: local only (no Universal
    /// Clipboard), expiring after 60 s.
    func copy() {
        guard phase == .ready, let nsec else { return }
        pasteboard.setItems([[UTType.utf8PlainText.identifier: nsec]], options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(60)])
        copiedNotice = true
        announce(AccountCopy.exportCopied)
    }

    /// `userDidTakeScreenshotNotification`: a notice, only if the key was on screen.
    func screenshotTaken() {
        if displayedGroups != nil { screenshotNotice = true }
    }

    /// Any phase other than `.active`, including `.inactive` (the app
    /// switcher), hides the key and pops back to Screen 1.
    func scenePhaseChanged(_ phase: ScenePhase) {
        if phase != .active { hide() }
    }

    /// Hide the key, drop it, and pop back to Screen 1. Seeing it again needs
    /// a new authentication. Called on leaving Screen 3, Done, leaving the
    /// foreground and the 2-minute timeout. It never touches the pasteboard:
    /// a copied key stays until its 60 s expiry (E1, option 1).
    func hide() {
        timeoutTask?.cancel()
        timeoutTask = nil
        nsec = nil
        isShown = false
        authorized = false
        phase = .locked
        gate = .idle
        copiedNotice = false
        screenshotNotice = false
        isRevealing = false
    }

    private func startTimeout() {
        timeoutTask?.cancel()
        let timeout = timeout
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }
}
