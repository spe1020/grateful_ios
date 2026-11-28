import SwiftUI
import GratefulDayCore

/// The bundled Daily Wisdom (shared with web, Phase 0 `WisdomLibrary`).
enum DailyWisdom {
    static let library: WisdomLibrary? = try? WisdomLibrary.bundled()

    /// The same item web shows for this local date.
    static func item(for day: JournalDay) -> WisdomItem? {
        library?.item(forDate: day.dateString)
    }

    /// Web `getWisdomPrompt`.
    static func prompt(_ item: WisdomItem) -> String {
        item.prompt ?? "Where might this idea meet your life today?"
    }

    /// Web `wisdomWording`.
    static func wording(_ item: WisdomItem) -> String {
        guard let p = item.provenance else { return "Source wording not yet verified" }
        let label = ["original": "Original wording", "translation": "Translation",
                     "adaptation": "Adapted by Grateful Day"][p.wording]
        return [label, p.credit].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Web: author · source · era.
    static func attribution(_ item: WisdomItem) -> String {
        [item.author, item.source, item.era].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Today's wisdom page of the Today card: passage, attribution, Grateful Day's reading, and the
/// question, with "Reflect on this". Text is shown as written, never edited.
struct WisdomCard: View {
    let item: WisdomItem
    let isPinned: Bool
    let onReflect: () -> Void
    @Environment(\.wisdomLabelLayout) private var reportLabelLayout

    var body: some View {
        VStack(alignment: .leading, spacing: GDSpacing.medium) {
            Text(item.text)
                .font(GDFont.wisdomPassage)
                .foregroundStyle(GDColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("wisdom.passage")
            VStack(alignment: .leading, spacing: 4) {
                Text(DailyWisdom.attribution(item))
                    .font(GDFont.sectionLabel)
                    .foregroundStyle(GDColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("wisdom.author")
                Text(DailyWisdom.wording(item))
                    .font(.caption)
                    .foregroundStyle(GDColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                // The source link gets its own full-size tap target.
                if let p = item.provenance, let url = URL(string: p.url) {
                    Link(destination: url) {
                        // Body colour, underlined: the accent tint fails
                        // contrast on the card background.
                        Text(p.location)
                            .font(.caption)
                            .underline()
                            .foregroundStyle(GDColor.foreground)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityHint("Opens the source in Safari")
                }
            }
            if let reading = item.interpretation {
                VStack(alignment: .leading, spacing: 4) {
                    Text("A reading by Grateful Day")
                        .font(.caption)
                        .foregroundStyle(GDColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(reading)
                        .font(GDFont.body)
                        .foregroundStyle(GDColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            Divider()
            VStack(alignment: .leading, spacing: GDSpacing.small) {
                // D9: without its own vertical fixedSize this label was the
                // one text the card could squeeze, cut to one line at the
                // largest text sizes on some days.
                Text("Carry it with you")
                    .font(GDFont.sectionLabel)
                    .foregroundStyle(GDColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGSize.self, of: { $0.size }) { reportLabelLayout?($0) }
                Text(DailyWisdom.prompt(item))
                    .font(GDFont.body.weight(.medium))
                    .foregroundStyle(GDColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("wisdom.question")
            if !isPinned {
                Button(action: onReflect) {
                    Text("Reflect on this")
                        .font(GDFont.sectionLabel.weight(.semibold))
                        .foregroundStyle(GDColor.foreground)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                    .accessibilityHint("Keeps the question above your writing. Nothing is added to your reflection.")
                    .accessibilityIdentifier("wisdom.reflect")
            }
        }
        // The Today card draws the padding-less page inside its own background.
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wisdom.card")
    }
}

extension EnvironmentValues {
    /// D9 test seam: reports the laid-out size of "Carry it with you", so a
    /// test can check every passage at large text sizes. Nil in the app,
    /// where it does nothing.
    @Entry var wisdomLabelLayout: (@MainActor @Sendable (CGSize) -> Void)? = nil
}

/// The question pinned above the editor by "Reflect on this". Context only:
/// it is never inserted into the reflection (criterion 2).
struct PinnedQuestion: View {
    let question: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: GDSpacing.small) {
            Text(question)
                .font(GDFont.body.weight(.medium))
                .foregroundStyle(GDColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("today.pinnedQuestion")
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Unpin question")
            .accessibilityIdentifier("today.unpin")
        }
    }
}
