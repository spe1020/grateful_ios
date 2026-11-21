import Foundation
import NostrCore

/// Kind 36669 daily gratitude entry: the wire format the web app writes
/// (interop spec r3 §1, web `DayDetailDialog.tsx` buildEntryEvent @ a33f42c).
public enum DailyEntry {
    public static let kind = 36669
    public static let encryptedTag = ["encrypted", "nip44"]
    public static let encryptedAlt = "Encrypted gratitude journal entry"
    /// NIP-44 v2's plaintext cap; applied to public entries too so toggling
    /// privacy can't make an entry unpublishable (spec §1.2).
    public static let maxContentBytes = 65_535

    public enum BuildError: Error, Equatable {
        case empty
        case tooLong(bytes: Int)
    }

    /// The calendar identity of a day in the device's time zone (spec §1.8).
    public struct Day: Equatable, Sendable {
        /// `d` tag, `YYYY-MM-DD` local date.
        public let dateString: String
        /// Local day of year, 1–366.
        public let dayOfYear: Int
        /// Unix seconds of local midnight (the start of that local day).
        public let publishedAt: Int
        /// en-US "Weekday, Month D" as used in the public alt tag.
        public let displayDate: String

        /// The local day containing `instant`, in `timeZone`.
        public init(containing instant: Date, timeZone: TimeZone = .current) {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone
            let parts = cal.dateComponents([.year, .month, .day], from: instant)
            let start = cal.startOfDay(for: instant)
            self.dateString = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
            self.dayOfYear = cal.ordinality(of: .day, in: .year, for: instant)!
            self.publishedAt = Int(start.timeIntervalSince1970.rounded(.down))
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.calendar = cal
            f.timeZone = timeZone
            f.dateFormat = "EEEE, MMMM d"
            self.displayDate = f.string(from: start)
        }
    }

    /// Build the unsigned 36669 for a day. `content` must already be the
    /// canonical notes text (or ciphertext, when `ciphertext` is provided).
    /// Private entries: pass the NIP-44 payload of the canonical text.
    public static func template(day: Day, notes: [String], encryptedContent: String? = nil) throws -> UnsignedEvent {
        let text = EntryNotes.join(notes)
        guard !text.isEmpty else { throw BuildError.empty }
        let bytes = text.utf8.count
        guard bytes <= maxContentBytes else { throw BuildError.tooLong(bytes: bytes) }
        let base = [["d", day.dateString], ["published_at", String(day.publishedAt)], ["day", String(day.dayOfYear)]]
        if let encryptedContent {
            return UnsignedEvent(kind: kind, tags: base + [encryptedTag, ["alt", encryptedAlt]], content: encryptedContent)
        }
        return UnsignedEvent(
            kind: kind,
            tags: base + [["alt", "Daily reflection entry for \(day.displayDate) (Day \(day.dayOfYear))"]],
            content: text
        )
    }

    /// Build a private entry, encrypting the canonical text to self. Fails
    /// closed: an encryption error throws; there is no plaintext fallback.
    public static func privateTemplate(day: Day, notes: [String], privateKey: Data) throws -> UnsignedEvent {
        let text = EntryNotes.join(notes)
        guard !text.isEmpty else { throw BuildError.empty }
        guard text.utf8.count <= maxContentBytes else { throw BuildError.tooLong(bytes: text.utf8.count) }
        let payload = try NIP44.encryptToSelf(text, privateKey: privateKey)
        return try template(day: day, notes: notes, encryptedContent: payload)
    }

    /// Private iff tagged `["encrypted","nip44"]` (spec §1.3). Never inferred from content.
    public static func isPrivate(_ event: NostrEvent) -> Bool {
        event.tags.contains { $0.count >= 2 && $0[0] == "encrypted" && $0[1] == "nip44" }
    }

    /// Spec §1.4: accept only the user's own, correctly signed, well-formed entries.
    public static func isValid(_ event: NostrEvent, owner pubkey: String) -> Bool {
        guard event.kind == kind, event.pubkey == pubkey,
              let d = event.tagValue("d"), isValidDateString(d),
              let day = event.tagValue("day").flatMap(Int.init), (1...366).contains(day),
              let published = event.tagValue("published_at").flatMap(Int.init), published > 0
        else { return false }
        return event.isValid
    }

    /// `YYYY-MM-DD` that is a real Gregorian date.
    public static func isValidDateString(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
        let p = value.split(separator: "-").compactMap { Int($0) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let date = cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return false }
        let back = cal.dateComponents([.year, .month, .day], from: date)
        return back.year == p[0] && back.month == p[1] && back.day == p[2]
    }

    /// Spec §1.5: newest `created_at` per `d` wins; ties go to the lexically
    /// lowest id (NIP-01). Web keeps the first seen on ties — a known difference.
    public static func latestPerDay(_ events: [NostrEvent]) -> [String: NostrEvent] {
        var out: [String: NostrEvent] = [:]
        for e in events {
            guard let d = e.tagValue("d") else { continue }
            if let cur = out[d] {
                if e.createdAt > cur.createdAt || (e.createdAt == cur.createdAt && e.id < cur.id) { out[d] = e }
            } else {
                out[d] = e
            }
        }
        return out
    }

    /// Spec §1.5: never publish an older `created_at` than the version merged against.
    public static func publishCreatedAt(now: Int, remoteCreatedAt: Int?) -> Int {
        max(now, (remoteCreatedAt ?? Int.min) &+ 1)
    }
}
