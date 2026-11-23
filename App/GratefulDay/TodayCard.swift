import SwiftUI
import GratefulDayCore

/// Today card copy (Prep, PLANS/GRATEFUL_DAY_IOS_TODAY_CARD_SPEC_2026_11_23.md).
enum TodayCardCopy {
    /// The card's own title. None for now (spec Q1): each page carries its
    /// own label. One string, so Seth's choice is a one-line change.
    static let title: String? = nil
    static let wisdomLabel = "Daily Wisdom"
    static let affirmationLabel = "Daily Affirmation"
    /// VoiceOver: the page control.
    static let pagesLabel = "Card page"
    static func pageValue(_ label: String, position: Int, count: Int) -> String {
        "\(label), \(position) of \(count)"
    }
    static func showPage(_ label: String) -> String { "Show \(label)" }
}

/// The bundled Daily Affirmations (shared with web, `AffirmationLibrary`).
enum DailyAffirmation {
    static let library: AffirmationLibrary? = try? AffirmationLibrary.bundled()

    /// The same line web shows for this local date.
    static func text(for day: JournalDay) -> String? {
        library?.affirmation(forDate: day.dateString)
    }
}

/// One page of the Today card. The pager takes a list of these, so a later
/// page (Teaching) is one more entry.
struct TodayCardPage: Identifiable {
    let id: String
    let label: String
    let content: AnyView
}

/// Which page Today shows. Device-local, never synced: each day opens on the
/// first page; within a day the last page viewed is kept, across relaunches.
enum TodayCardSelection {
    static let defaultsKey = "today.card.page"

    /// `stored` is "YYYY-MM-DD|pageId".
    static func page(stored: String?, today: String, pageIds: [String]) -> String? {
        guard let first = pageIds.first else { return nil }
        guard let stored, let bar = stored.firstIndex(of: "|"),
              stored[..<bar] == today else { return first }
        let id = String(stored[stored.index(after: bar)...])
        return pageIds.contains(id) ? id : first
    }

    static func stored(today: String, pageId: String) -> String { "\(today)|\(pageId)" }

    /// One page on from `index` (swipe, VoiceOver adjust). Never wraps.
    static func step(from index: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index + delta, 0), count - 1)
    }
}

/// One card that shows one page at a time. Swipe (no wrap-around) or tap a
/// dot to change page; VoiceOver uses the adjustable page control or its
/// actions instead of swiping. Every page is laid out at once and the card
/// takes the tallest one's height, so nothing below it moves on a page change.
struct TodayCard: View {
    let pages: [TodayCardPage]
    @Binding var selection: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: GDSpacing.small) {
            if let title = TodayCardCopy.title {
                Text(title)
                    .font(GDFont.sectionLabel)
                    .foregroundStyle(GDColor.foreground)
                    .accessibilityAddTraits(.isHeader)
            }
            ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(pages) { page in
                        VStack(alignment: .leading, spacing: GDSpacing.small) {
                            Text(page.label)
                                .font(GDFont.sectionLabel)
                                .foregroundStyle(GDColor.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("todayCard.label.\(page.id)")
                            page.content
                        }
                        .padding(.horizontal, GDSpacing.medium)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .containerRelativeFrame(.horizontal)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("todayCard.page.\(page.id)")
                        // Only the page on screen is read and reachable.
                        .accessibilityHidden(page.id != current)
                        .id(page.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selection)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("todayCard.pager")
            // `scrollPosition` doesn't apply its starting value on first
            // layout: without this a relaunch shows Wisdom while the kept
            // page (and VoiceOver) is Affirmation.
            .onAppear { if let current { proxy.scrollTo(current, anchor: .leading) } }
            }

            if pages.count > 1 {
                pageDots
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, GDSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: GDRadius.card, style: .continuous)
                .fill(GDColor.secondary)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("todayCard")
    }

    private var current: String? { selection ?? pages.first?.id }
    private var currentIndex: Int { pages.firstIndex { $0.id == current } ?? 0 }

    private func go(to index: Int) {
        guard pages.indices.contains(index) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { selection = pages[index].id }
    }

    private var pageDots: some View {
        HStack(spacing: 0) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                Button { go(to: index) } label: {
                    Circle()
                        .fill(GDColor.foreground.opacity(index == currentIndex ? 1 : 0.3))
                        .frame(width: 8, height: 8)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        // One adjustable element for VoiceOver: swipe up/down or the actions
        // change page, so a horizontal swipe is never needed.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TodayCardCopy.pagesLabel)
        .accessibilityValue(TodayCardCopy.pageValue(pages[currentIndex].label,
                                                    position: currentIndex + 1, count: pages.count))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: go(to: TodayCardSelection.step(from: currentIndex, by: 1, count: pages.count))
            case .decrement: go(to: TodayCardSelection.step(from: currentIndex, by: -1, count: pages.count))
            @unknown default: break
            }
        }
        .accessibilityActions {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                if index != currentIndex {
                    Button(TodayCardCopy.showPage(page.label)) { go(to: index) }
                }
            }
        }
        .accessibilityIdentifier("todayCard.dots")
    }
}

/// Today's affirmation, shown as written, with no action.
struct AffirmationPage: View {
    let text: String

    var body: some View {
        Text(text)
            .font(GDFont.wisdomPassage)
            .foregroundStyle(GDColor.foreground)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("affirmation.text")
    }
}
