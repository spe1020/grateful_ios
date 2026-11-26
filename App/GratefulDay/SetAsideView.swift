import SwiftUI
import UIKit

/// Set aside (P22): earlier versions of reflections that a version saved
/// elsewhere replaced. Read-only in the MVP: date, reason, the full earlier
/// text and [Copy]. No restore, since past days are read-only, and nothing
/// here is ever purged. M6's conflict screen builds on this later.
struct SetAsideView: View {
    @Environment(JournalStore.self) private var store
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    /// When set, only these items are shown (opened from a Today or day line).
    var only: Set<UUID>? = nil

    var body: some View {
        let items = store.container.map { JournalRepository(context: $0.mainContext, activeOwner: account.activeOwner) }
            .flatMap { try? $0.setAsideVersions() } ?? []
        List {
            ForEach(items.filter { only == nil || only!.contains($0.id) }, id: \.id) { item in
                VStack(alignment: .leading, spacing: GDSpacing.small) {
                    Text(SyncCopy.monthDay(item.dateString))
                        .font(.headline)
                        .foregroundStyle(GDColor.foreground)
                        .accessibilityAddTraits(.isHeader)
                    Text(ConflictCopy.setAsideReason(item.reason))
                        .font(GDFont.sectionLabel)
                        .foregroundStyle(GDColor.mutedForeground)
                    Text(item.notesText)
                        .font(GDFont.body)
                        .foregroundStyle(GDColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Button(SyncCopy.copy) {
                        // Local only: never offered to other devices.
                        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: item.notesText]],
                                                      options: [.localOnly: true])
                    }
                    .accessibilityIdentifier("setAside.copy")
                }
                .padding(.vertical, GDSpacing.small)
                .accessibilityIdentifier("setAside.item")
            }
        }
        .navigationTitle(SyncCopy.setAsideTitle)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }
}

/// The quiet Today line for replaced reflections (P22). One element for
/// VoiceOver, with a Dismiss action. Tapping opens Set aside filtered to
/// these items and also dismisses the line; dismissing never deletes.
struct ReplacedVersionsLine: View {
    let versions: [EarlierVersion]
    let onOpen: (Set<UUID>) -> Void
    let onDismiss: ([UUID]) -> Void

    var body: some View {
        let ids = versions.map(\.id)
        let text = SyncCopy.replaced(dates: versions.map(\.dateString))
        HStack(alignment: .top, spacing: GDSpacing.small) {
            Button {
                onDismiss(ids)
                onOpen(Set(ids))
            } label: {
                Text(text)
                    .font(GDFont.sectionLabel)
                    .foregroundStyle(GDColor.foreground)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { onDismiss(ids) } label: {
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
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onDismiss(ids); onOpen(Set(ids)) }
        .accessibilityAction(named: SyncCopy.dismiss) { onDismiss(ids) }
        .accessibilityIdentifier("today.replaced")
    }
}

struct SetAsideFilter: Identifiable {
    let id = UUID()
    let ids: Set<UUID>
}

/// "An earlier version of this reflection is in Set aside." on a day's own
/// view (P22). Tap opens that item.
struct EarlierVersionLine: View {
    let onOpen: () -> Void
    var body: some View {
        Button(action: onOpen) {
            Text(SyncCopy.earlierVersionKept)
                .font(GDFont.sectionLabel)
                .foregroundStyle(GDColor.foreground)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
