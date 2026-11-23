import SwiftUI
import SwiftData
import GratefulDayCore

/// Spec A: the disclosure before anything is published (MVP doc,
/// "Experience spec A"). Final copy; change only together with that doc.
enum DisclosureCopy {
    static let heading = "What's private in your journal"
    /// Shown only when something is waiting to be saved.
    static func countLine(_ n: Int) -> String {
        n == 1 ? "1 reflection will be backed up to your account." : "\(n) reflections will be backed up to your account."
    }
    static let encrypted = "Your words are encrypted, so they can only be read with your key."
    static let visible = "The dates and times you save or edit entries can be seen by others."
    static let continueButton = "Continue"
    static let notNow = "Not now"
    static let learnMore = "Learn more"
    /// §11 (flows doc): the Learn more page, final copy. Opened from the
    /// sheet and from Settings → Privacy; reading it changes nothing.
    static let learnMoreHeading = "What's private in your journal"
    static let learnMoreIntro = "The words you write are encrypted. The dates and times you save or edit an entry can be seen by others."
    struct Section: Hashable {
        let title: String
        let lines: [String]
        var bullets: [String] = []
        var after: [String] = []
    }
    static let learnMoreSections: [Section] = [
        Section(title: "Encrypted",
                lines: ["The words of your private reflections. They can only be read with your journal key."]),
        Section(title: "Can be seen by others",
                lines: ["Anyone who looks up your account can see:"],
                bullets: ["Which days you wrote on.",
                          "When you saved each reflection, and each time you edited it.",
                          "Roughly how long each reflection is."],
                after: ["They can't see what you wrote."]),
        Section(title: "Public reflections",
                lines: ["Anyone can read a reflection you make public. If you make it private later, earlier public versions may still be readable. Making it private protects what you save from now on."]),
        Section(title: "Your journal key",
                lines: ["Your journal key opens every private reflection saved to your account, including earlier versions. Anyone who gets your journal key, now or years from now, can read all of them. Keep it safe and keep a backup. If it's lost and there's no backup, your private reflections can't be opened again."]),
        Section(title: "Deleting",
                lines: ["Deleting a reflection asks for it to be removed from your account. Most places that store it will remove it, but some may keep a copy."]),
        Section(title: "Before you connect an account",
                lines: ["Before you connect an account, your reflections stay on this iPhone only. They aren't in iCloud or iPhone backups, so they're lost if the phone is."]),
    ]
}

/// Whether the person has accepted spec A for this account on this
/// iPhone, and what the sheet's count line counts.
@MainActor
struct PublishDisclosure {
    let context: ModelContext
    let owner: String

    /// Once per account on this device (spec A): a flag per account, kept
    /// in the journal store, so another account sees the sheet too.
    static func flagName(owner: String) -> String { JournalFlag.publishDisclosureAccepted + "|" + owner }

    func isAccepted() throws -> Bool {
        try JournalRepository(context: context, activeOwner: owner).flag(Self.flagName(owner: owner))
    }

    func accept(now: Date = .now) throws {
        try JournalRepository(context: context, activeOwner: owner).setFlag(Self.flagName(owner: owner), now: now)
    }

    /// Reflections of this account that would be saved now: written here
    /// and not yet on the account.
    func pendingCount() throws -> Int {
        let o: String? = owner, raw = SyncState.localOnly.rawValue
        let rows = try context.fetch(FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.ownerPubkey == o && $0.syncStateRaw == raw && $0.deletedAt == nil }))
        return rows.filter { !EntryNotes.split($0.notesText).isEmpty }.count
    }
}

/// One sheet, one screen. Continue allows publishing; Not now publishes
/// nothing and loses nothing.
struct PublishDisclosureSheet: View {
    let count: Int
    let onContinue: () -> Void
    let onNotNow: () -> Void
    @State private var showingLearnMore = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: GDSpacing.medium) {
                Text(DisclosureCopy.heading)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(GDColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("disclosure.heading")
                if count > 0 {
                    Text(DisclosureCopy.countLine(count))
                        .font(GDFont.body.weight(.semibold))
                        .foregroundStyle(GDColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("disclosure.count")
                }
                Text(DisclosureCopy.encrypted)
                    .font(GDFont.body)
                    .foregroundStyle(GDColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(DisclosureCopy.visible)
                    .font(GDFont.body)
                    .foregroundStyle(GDColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Button(DisclosureCopy.learnMore) { showingLearnMore = true }
                    .font(GDFont.sectionLabel)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("disclosure.learnMore")
                Spacer()
                Button(action: onContinue) {
                    Text(DisclosureCopy.continueButton).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("disclosure.continue")
                Button(action: onNotNow) {
                    Text(DisclosureCopy.notNow).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("disclosure.notNow")
            }
            .padding(GDSpacing.medium)
            .background(GDColor.background.ignoresSafeArea())
            .navigationDestination(isPresented: $showingLearnMore) { DisclosureLearnMoreView() }
        }
        .interactiveDismissDisabled()
    }
}

struct DisclosureLearnMoreView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GDSpacing.medium) {
                Text(DisclosureCopy.learnMoreHeading)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(GDColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                para(DisclosureCopy.learnMoreIntro)
                ForEach(DisclosureCopy.learnMoreSections, id: \.self) { section in
                    VStack(alignment: .leading, spacing: GDSpacing.small) {
                        Text(section.title)
                            .font(.headline)
                            .foregroundStyle(GDColor.foreground)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.lines, id: \.self) { para($0) }
                        ForEach(section.bullets, id: \.self) { line in
                            HStack(alignment: .firstTextBaseline, spacing: GDSpacing.small) {
                                Text("•").accessibilityHidden(true)
                                para(line)
                            }
                        }
                        ForEach(section.after, id: \.self) { para($0) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(GDSpacing.medium)
        }
        .background(GDColor.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("disclosure.learnMorePage")
    }

    private func para(_ text: String) -> some View {
        Text(text)
            .font(GDFont.body)
            .foregroundStyle(GDColor.foreground)
            .fixedSize(horizontal: false, vertical: true)
    }
}
