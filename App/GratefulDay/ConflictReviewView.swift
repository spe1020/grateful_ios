import SwiftUI
import GratefulDayCore

/// M6: the conflict screen (Prep's final copy, "M6 conflict screen").
/// Opened only from the Today line or a day's line, never on its own.
struct ConflictReviewView: View {
    let review: ConflictReview
    /// Called after Done, Keep both for all, or Not now.
    let onClose: () -> Void
    @State private var days = ConflictReview.Days()
    @State private var choices: [String: ConflictReview.Choice] = [:]
    @State private var failed = false

    var body: some View {
        List {
            if !days.items.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: GDSpacing.small) {
                        Text(ConflictCopy.heading(dates: days.items.map(\.dateString), afterSaving: days.allAfterSaving,
                                                  allKind: days.allKind))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(GDColor.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("conflict.heading")
                        Text(ConflictCopy.subheading)
                            .font(GDFont.sectionLabel)
                            .foregroundStyle(GDColor.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                        if days.showsKeepBothForAll {
                            Button(ConflictCopy.keepBothForAll) { keepBothForAll() }
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("conflict.keepBothForAll")
                        }
                    }
                }
                ForEach(days.items) { item in
                    Section {
                        ConflictRow(item: item, choice: Binding(
                            get: { choices[item.dateString] ?? item.defaultChoice },
                            set: { choices[item.dateString] = $0 }))
                    }
                }
            }
            if !days.blocked.isEmpty {
                Section {
                    ForEach(days.blocked) { day in
                        BlockedConflictRow(day: day)
                    }
                } header: {
                    Text(ConflictCopy.cantCompareHeading)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("conflict.cantCompare")
                }
            }
            if failed {
                Text(JournalUnavailableView.failedText(removalIncomplete: false))
                    .font(GDFont.sectionLabel)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(ConflictCopy.notNow) { onClose() }.accessibilityIdentifier("conflict.notNow")
            }
            if !days.items.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ConflictCopy.done) { done() }.accessibilityIdentifier("conflict.done")
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        do { days = try review.load(); failed = false } catch { failed = true }
    }

    private func done() {
        let all = Dictionary(uniqueKeysWithValues: days.items.map { ($0.dateString, choices[$0.dateString] ?? $0.defaultChoice) })
        do { try review.apply(all); onClose() } catch { failed = true }
    }

    private func keepBothForAll() {
        do {
            let kept = try review.keepBothForAll()
            try review.saveKeptBothNotice(kept)
            // §7–§9: rows Keep both for all doesn't touch keep the screen open.
            load()
            if days.items.isEmpty { onClose() }
        } catch { failed = true }
    }
}

/// One day: both texts, each labelled, the account's first, and the choice.
private struct ConflictRow: View {
    let item: ConflictReview.Item
    @Binding var choice: ConflictReview.Choice

    var body: some View {
        VStack(alignment: .leading, spacing: GDSpacing.medium) {
            if let day = TodayEditorModel.parse(item.dateString, timeZone: .current) {
                Text(TodayView.title(for: day.day))
                    .font(.headline)
                    .foregroundStyle(GDColor.foreground)
                    .accessibilityAddTraits(.isHeader)
            }
            LabelledText(label: ConflictCopy.yourAccount,
                         text: item.kind == .deletedFromAccount ? ConflictCopy.deletedFromAccount : item.accountText,
                         identifier: "conflict.account")
            LabelledText(label: ConflictCopy.thisIPhone,
                         text: item.kind == .deletedHere ? ConflictCopy.deletedHere : item.iPhoneText,
                         identifier: "conflict.iPhone")
            Picker(Self.title(item.defaultChoice), selection: $choice) {
                ForEach(item.choices, id: \.self) { c in
                    Text(Self.title(c)).tag(c)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .accessibilityIdentifier("conflict.choice")
            Text(line)
                .font(GDFont.sectionLabel)
                .foregroundStyle(GDColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("conflict.choiceLine")
            if choice == .keepBoth, item.keepBothTooLong {
                Text(ConflictCopy.keepBothTooLong)
                    .font(GDFont.sectionLabel)
                    .foregroundStyle(GDColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("conflict.tooLong")
            }
            if choice == .keepBoth, item.keepBothBecomesPrivate {
                Text(ConflictCopy.privateWins)
                    .font(GDFont.sectionLabel)
                    .foregroundStyle(GDColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("conflict.privateWins")
            }
        }
        .padding(.vertical, GDSpacing.small)
    }

    static func title(_ choice: ConflictReview.Choice) -> String {
        switch choice {
        case .keepBoth: return ConflictCopy.keepBoth
        case .keepThisIPhone: return ConflictCopy.keepThisIPhone
        case .keepAccount: return ConflictCopy.keepAccount
        case .letItStayDeleted: return ConflictCopy.letItStayDeleted
        case .deleteEverywhere: return ConflictCopy.deleteEverywhere
        }
    }

    private var line: String {
        switch (item.kind, choice) {
        case (.deletedFromAccount, .keepThisIPhone): return ConflictCopy.keepThisIPhoneRestoresLine
        case (.deletedHere, .keepAccount): return ConflictCopy.keepAccountRestoresLine
        case (_, .keepBoth): return ConflictCopy.keepBothLine
        case (_, .keepThisIPhone): return ConflictCopy.keepThisIPhoneLine
        case (_, .keepAccount): return ConflictCopy.keepAccountLine
        case (_, .letItStayDeleted): return ConflictCopy.letItStayDeletedLine
        case (_, .deleteEverywhere): return ConflictCopy.deleteEverywhereLine
        }
    }
}

/// §5: no buttons, nothing published.
private struct BlockedConflictRow: View {
    let day: ConflictReview.Blocked

    var body: some View {
        VStack(alignment: .leading, spacing: GDSpacing.medium) {
            if let parsed = TodayEditorModel.parse(day.dateString, timeZone: .current) {
                Text(TodayView.title(for: parsed.day))
                    .font(.headline)
                    .foregroundStyle(GDColor.foreground)
                    .accessibilityAddTraits(.isHeader)
            }
            LabelledText(label: ConflictCopy.yourAccount, text: ConflictCopy.cantOpenAccount, identifier: "conflict.blockedAccount")
            LabelledText(label: ConflictCopy.thisIPhone, text: day.iPhoneText, identifier: "conflict.blockedIPhone")
            Text(ConflictCopy.cantCompareLine)
                .font(GDFont.sectionLabel)
                .foregroundStyle(GDColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, GDSpacing.small)
    }
}

/// A label above a text, read together by VoiceOver ("Your account: …").
/// Long texts show their first lines and Show all; nothing is cut from
/// what's kept.
private struct LabelledText: View {
    let label: String
    let text: String
    let identifier: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: GDSpacing.small) {
            Text(label)
                .font(GDFont.sectionLabel.weight(.semibold))
                .foregroundStyle(GDColor.mutedForeground)
            Text(text)
                .font(GDFont.body)
                .foregroundStyle(GDColor.foreground)
                .lineLimit(expanded ? nil : 6)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !expanded, text.count > 280 || text.split(separator: "\n").count > 6 {
                Button(ConflictCopy.showAll) { expanded = true }
                    .font(GDFont.sectionLabel)
                    .frame(minHeight: 44)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(text)")
        .accessibilityIdentifier(identifier)
    }
}

/// Today line while any choice is open (Prep, "Coming back later"). One
/// element for VoiceOver with a Dismiss action. Dismissing changes nothing.
struct ConflictComeBackLine: View {
    let dates: [String]
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        QuietLine(text: ConflictCopy.comeBack(dates: dates), onOpen: onOpen, onDismiss: onDismiss)
            .accessibilityIdentifier("today.conflictComeBack")
    }
}

/// Today line after Keep both for all, until dismissed.
struct KeptBothLine: View {
    let kept: ConflictReview.KeptBoth
    let onDismiss: () -> Void

    var body: some View {
        QuietLine(text: ConflictCopy.keptBoth(dates: kept.dates, madePrivate: kept.madePrivate), onOpen: nil, onDismiss: onDismiss)
            .accessibilityIdentifier("today.keptBoth")
    }
}

/// A quiet line with an optional tap and a dismiss (×).
struct QuietLine: View {
    let text: String
    let onOpen: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: GDSpacing.small) {
            Button { onOpen?() } label: {
                Text(text)
                    .font(GDFont.sectionLabel)
                    .foregroundStyle(GDColor.foreground)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onOpen == nil)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(GDColor.mutedForeground)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(onOpen == nil ? [] : .isButton)
        .accessibilityAction { onOpen?() }
        .accessibilityAction(named: SyncCopy.dismiss, onDismiss)
    }
}
