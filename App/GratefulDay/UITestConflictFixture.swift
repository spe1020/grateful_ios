#if DEBUG
import SwiftUI
import SwiftData
import NostrCore
import GratefulDayCore

/// A conflict screen for the UI tests (D2). Compiled only into Debug builds
/// and read only from the process's launch arguments, like `UITestRelays`:
/// a shipped (Release) build contains none of this.
///
/// `-uiTestConflictFixture <bothChanged|deletedHere|deletedFromAccount>`
/// covers the app with the real `ConflictReviewView` for one day of that
/// kind. The day is seeded through the real importer path (a pending local
/// row, then signed relay events through `RemoteImporter`), into an
/// in-memory store under a throwaway key that never reaches the Keychain.
/// The journal on the simulator, the account and the relays are untouched.
/// After Done the fixture lists what was applied: the day's notes, whether
/// it's deleted, its sync state, Set aside and the open conflicts left.
enum UITestConflictFixture {
    static let argument = "-uiTestConflictFixture"
    static let dateString = "2026-11-20"
    static let accountText = "Fixture account text"
    static let iPhoneText = "Fixture iPhone text"

    static func kind(arguments: [String]) -> ConflictReview.Kind? {
        guard let i = arguments.firstIndex(of: argument), arguments.indices.contains(i + 1) else { return nil }
        switch arguments[i + 1] {
        case "bothChanged": return .bothChanged
        case "deletedHere": return .deletedHere
        case "deletedFromAccount": return .deletedFromAccount
        default: return nil
        }
    }

    struct Seeded {
        let container: ModelContainer
        let owner: String
    }

    @MainActor
    static func seed(_ kind: ConflictReview.Kind) throws -> Seeded {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: JournalStore.schema, configurations: config)
        let context = container.mainContext
        let secret = try NostrKeys.generatePrivateKey()
        guard let owner = KeyVault.pubkeyHex(for: secret) else { throw CocoaError(.featureUnsupported) }
        let zone = TimeZone.current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let day = DailyEntry.Day(containing: cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!,
                                 timeZone: zone)
        let now = Date.now
        func remote(_ text: String, at: Int) throws -> NostrEvent {
            try DailyEntry.privateTemplate(day: day, notes: [text], privateKey: secret).signed(privateKey: secret, createdAt: at)
        }
        let row = JournalEntry(dateString: day.dateString, dayOfYear: day.dayOfYear, publishedAt: day.publishedAt,
                               timeZoneID: zone.identifier, notesText: kind == .deletedHere ? "" : iPhoneText,
                               now: now, ownerPubkey: owner)
        row.isPrivate = true
        var events: [NostrEvent]
        switch kind {
        case .bothChanged:
            // A pending local edit, then the account's version arrives.
            events = [try remote(accountText, at: 500)]
        case .deletedHere:
            // Deleted here, then edited in the account.
            let base = try remote("v1", at: 100)
            row.remoteEventID = base.id; row.remoteCreatedAt = 100; row.deletedAt = now
            events = [base, try remote(accountText, at: 200)]
        case .deletedFromAccount:
            // Written here, then deleted from the account.
            let base = try remote("v1", at: 100)
            row.remoteEventID = base.id; row.remoteCreatedAt = 100
            events = [base, try EntryDeletion.template(pubkey: owner, dateString: day.dateString, eventId: base.id)
                .signed(privateKey: secret, createdAt: 900)]
        }
        context.insert(row)
        try context.save()
        _ = try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: events, owner: owner, privateKey: secret), zone: zone)
        return Seeded(container: container, owner: owner)
    }
}

extension View {
    /// Covers the app with the fixture when its launch argument is present.
    func uiTestConflictFixture(arguments: [String]) -> some View {
        fullScreenCover(isPresented: .constant(UITestConflictFixture.kind(arguments: arguments) != nil)) {
            if let kind = UITestConflictFixture.kind(arguments: arguments) {
                UITestConflictFixtureView(kind: kind)
            }
        }
    }
}

private struct UITestConflictFixtureView: View {
    let kind: ConflictReview.Kind
    @State private var seeded: UITestConflictFixture.Seeded?
    @State private var failed = false
    @State private var closed = false
    /// No runner and refusing relays: Done's Try now reaches nothing.
    @State private var sync = SyncService(transport: UITestRelays.RefusingTransport())

    var body: some View {
        NavigationStack {
            if let seeded {
                let review = ConflictReview(context: seeded.container.mainContext, owner: seeded.owner)
                if closed {
                    UITestConflictFixtureResult(review: review,
                                                repository: JournalRepository(context: seeded.container.mainContext,
                                                                              activeOwner: seeded.owner))
                } else {
                    ConflictReviewView(review: review) { closed = true }
                }
            } else if failed {
                Text("Fixture failed").accessibilityIdentifier("fixture.failed")
            }
        }
        .environment(sync)
        .onAppear {
            guard seeded == nil else { return }
            do { seeded = try UITestConflictFixture.seed(kind) } catch { failed = true }
        }
    }
}

/// What Done applied, read back from the store the screen wrote to.
private struct UITestConflictFixtureResult: View {
    let review: ConflictReview
    let repository: JournalRepository

    var body: some View {
        let row = try? repository.entry(for: UITestConflictFixture.dateString)
        let setAside = ((try? repository.setAsideVersions()) ?? []).filter { $0.dateString == UITestConflictFixture.dateString }
        List {
            Section("Day") {
                ForEach(Array(EntryNotes.split(row?.notesText ?? "").enumerated()), id: \.offset) { _, note in
                    Text(note).accessibilityIdentifier("fixture.dayNote")
                }
                Text(row?.deletedAt == nil ? "not deleted" : "deleted").accessibilityIdentifier("fixture.deleted")
                Text(row?.syncState.rawValue ?? "none").accessibilityIdentifier("fixture.syncState")
            }
            Section("Set aside") {
                ForEach(setAside, id: \.id) { item in
                    Text(item.notesText).accessibilityIdentifier("fixture.setAside")
                    Text(ConflictCopy.setAsideReason(item.reason)).accessibilityIdentifier("fixture.setAsideReason")
                }
            }
            Section("Open") {
                Text("\((try? review.load().items.count) ?? -1)").accessibilityIdentifier("fixture.openConflicts")
            }
        }
        .navigationTitle("Fixture result")
    }
}
#endif
