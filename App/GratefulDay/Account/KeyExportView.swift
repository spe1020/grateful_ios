import SwiftUI
import UIKit

// Show journal key, Screens 1 and 3 (Screen 2 is the system prompt). The
// logic and every security rule are in `KeyExportSession` (KeyExport.swift).

// MARK: - Screen 1: Before you continue

struct KeyExportIntroView: View {
    /// Screen-local: the key never reaches `AccountModel` or the environment (S2+).
    @State private var session: KeyExportSession
    let onClose: () -> Void

    init(owner: String, reader: PrimaryKeyReading,
         authenticator: DeviceOwnerAuthenticating = SystemDeviceOwnerAuthenticator(),
         onClose: @escaping () -> Void) {
        _session = State(initialValue: KeyExportSession(owner: owner, reader: reader, authenticator: authenticator))
        self.onClose = onClose
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GDSpacing.medium) {
                Text(AccountCopy.exportIntroHeading)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(AccountCopy.exportIntroBody1)
                Text(AccountCopy.exportIntroBody2)
                VStack(alignment: .leading, spacing: GDSpacing.small) {
                    ForEach(AccountCopy.exportBullets, id: \.self) { bullet in
                        HStack(alignment: .firstTextBaseline, spacing: GDSpacing.small) {
                            Text(verbatim: "•").accessibilityHidden(true)
                            Text(bullet)
                        }
                    }
                }
                if session.gate == .noPasscode {
                    Text(AccountCopy.exportNoPasscode)
                        .accessibilityIdentifier("export.noPasscode")
                }
                Button {
                    Task { await session.authenticate() }
                } label: {
                    Text(AccountCopy.exportShow).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.gate == .authenticating)
                .accessibilityIdentifier("export.show")
                Button {
                    onClose()
                } label: {
                    Text(AccountCopy.cancel).frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("export.cancel")
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(GDSpacing.medium)
        }
        .navigationTitle(AccountCopy.exportTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: Bindable(session).isRevealing) {
            KeyExportRevealView(session: session) {
                session.hide()
                onClose()
            }
        }
    }
}

// MARK: - Screen 3: Your journal key

struct KeyExportRevealView: View {
    let session: KeyExportSession
    let onDone: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn

    var body: some View {
        List {
            switch session.phase {
            case .ready:
                Section {
                    LabeledContent(AccountCopy.exportAccount, value: AccountView.shortNpub(session.owner))
                        .accessibilityIdentifier("export.account")
                } header: {
                    // Said once, at the top of the screen (§1.5).
                    if voiceOverOn { Text(AccountCopy.exportVoiceOverHint) }
                }
                Section {
                    KeyGroupsView(groups: session.displayedGroups)
                    Button(session.isShown && !session.isCaptured ? AccountCopy.exportConceal : AccountCopy.exportReveal) {
                        session.toggleShown()
                    }
                    .frame(minHeight: 44)
                    .disabled(session.isCaptured)
                    .accessibilityIdentifier("export.toggle")
                    if session.isCaptured {
                        Text(AccountCopy.exportCaptured).accessibilityIdentifier("export.captured")
                    }
                    Button(AccountCopy.exportCopy) { session.copy() }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("export.copy")
                    if session.copiedNotice {
                        Text(AccountCopy.exportCopied).accessibilityIdentifier("export.copied")
                    }
                    if session.screenshotNotice {
                        Text(AccountCopy.exportScreenshot).accessibilityIdentifier("export.screenshot")
                    }
                }
            case .mismatch:
                Section { Text(AccountCopy.mismatch) }
            case .keyMissing:
                Section { Text(AccountCopy.keyMissing) }
            case .locked, .unavailable:
                EmptyView()
            }
            Section {
                Button(AccountCopy.exportDone) { onDone() }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("export.done")
            }
        }
        .privacySensitive()
        .navigationTitle(AccountCopy.exportTitle)
        .navigationBarTitleDisplayMode(.inline)
        // App-switcher snapshot: a plain cover while the app isn't active.
        .overlay {
            if scenePhase != .active {
                Color(uiColor: .systemBackground).ignoresSafeArea()
            }
        }
        .onAppear {
            session.isCaptured = Self.screenIsCaptured()
            session.load()
        }
        .onDisappear { session.hide() }
        .onChange(of: scenePhase) { _, phase in
            session.scenePhaseChanged(phase)
            if phase == .active { session.isCaptured = Self.screenIsCaptured() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            session.isCaptured = Self.screenIsCaptured()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            session.screenshotTaken()
        }
    }

    /// Screen recording, mirroring or AirPlay on any of the app's scenes.
    static func screenIsCaptured() -> Bool {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.contains {
            $0.traitCollection.sceneCaptureState == .active || $0.screen.isCaptured
        }
    }
}

/// The key, or dots. Monospaced groups of 4 that wrap at every text size and
/// can't be selected. VoiceOver reads a shown key group by group, spelled
/// out, only when focused; hidden, it's one element, "Journal key, hidden".
private struct KeyGroupsView: View {
    let groups: [String]?

    var body: some View {
        if let groups {
            WrappingRow(spacing: GDSpacing.small) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    Text(verbatim: group)
                        .font(.body.monospaced())
                        .speechSpellsOutCharacters()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("export.key")
            .privacySensitive()
        } else {
            WrappingRow(spacing: GDSpacing.small) {
                ForEach(Array(KeyExport.hiddenGroups.enumerated()), id: \.offset) { _, dots in
                    Text(verbatim: dots).font(.body.monospaced())
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AccountCopy.exportHiddenLabel)
            .accessibilityIdentifier("export.keyHidden")
        }
    }
}

/// Lays children out left to right, wrapping onto new lines; never scrolls sideways.
private struct WrappingRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += lineHeight + spacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + spacing
                x = bounds.minX
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
