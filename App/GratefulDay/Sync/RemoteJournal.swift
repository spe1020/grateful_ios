import Foundation
import NostrCore
import GratefulDayCore

/// What the relays hold for one day of the connected account (interop §1.4–1.7).
enum RemoteDay: Equatable {
    case entry(text: String, isPrivate: Bool, eventId: String, createdAt: Int, event: NostrEvent)
    /// A kind 5 covers the newest version (created_at ≤ deletion). `by` holds
    /// the ids of the kind 5 events at that deletion time, so the importer
    /// can tell this device's own deletion from another device's (P30 M1).
    case deleted(at: Int, by: Set<String> = [])
    /// The newest version exists but can't be decrypted or decoded: unknown,
    /// never empty, never written over.
    case blocked(eventId: String, createdAt: Int)
}

enum RemoteJournal {
    /// Per-day remote state from fetched events: only the owner's valid 36669s,
    /// newest per `d` (ties: lowest id), with the owner's kind 5s applied.
    ///
    /// D7 (Chief f98fa116): a kind 5 is positive evidence on its own. Relays
    /// that honour NIP-09 drop the 36669 it covers, so a day can be held as
    /// a tombstone with no 36669 beside it; that day is `.deleted` too. A
    /// missing 36669 by itself still means nothing (no entry for the day).
    /// - Rule 1: only the owner's own, valid kind 5s, through an `a` tag that
    ///   is exactly `36669:<owner>:<day>` (`EntryDeletion.tombstones`).
    /// - Rule 2: the tombstone's `created_at` is the deletion time; versions
    ///   after it survive here, and the importer's ordering and pending-edit
    ///   rules decide for local copies (`RemoteImporter`, §7 review).
    /// - Rule 3: a kind 5 with no `a` tag at all acts only on a day whose
    ///   local copy is based on exactly the event it names (`localBases`,
    ///   day → recorded remote event id), and only while no other version of
    ///   that day is on the relays.
    static func days(from events: [NostrEvent], owner pubkey: String, privateKey: Data,
                     localBases: [String: String] = [:]) -> [String: RemoteDay] {
        let entries = events.filter { DailyEntry.isValid($0, owner: pubkey) }
        let deletions = events.filter { $0.kind == 5 && $0.pubkey == pubkey && $0.isValid }
        let tombstones = EntryDeletion.tombstones(from: deletions, owner: pubkey)
        let latestPerDay = DailyEntry.latestPerDay(entries)
        let prefix = EntryDeletion.address(pubkey: pubkey, dateString: "")
        var out: [String: RemoteDay] = [:]

        /// The `.deleted` for an address tombstone: `by` is every kind 5 at
        /// that deletion time naming the address (the importer's own-outbox
        /// skip and D5's recorded id both need it).
        func deleted(_ d: String) -> RemoteDay? {
            let address = EntryDeletion.address(pubkey: pubkey, dateString: d)
            guard let at = tombstones[address] else { return nil }
            let ids = deletions.filter {
                $0.createdAt == at && $0.tags.contains { $0.count >= 2 && $0[0] == "a" && $0[1] == address }
            }.map(\.id)
            return .deleted(at: at, by: Set(ids))
        }

        for (d, latest) in latestPerDay {
            if EntryDeletion.isDeleted(latest, tombstones: tombstones) {
                out[d] = deleted(d)
                continue
            }
            if DailyEntry.isPrivate(latest) {
                guard let text = try? NIP44.decryptFromSelf(latest.content, privateKey: privateKey) else {
                    out[d] = .blocked(eventId: latest.id, createdAt: latest.createdAt)
                    continue
                }
                out[d] = .entry(text: EntryNotes.normalize(text), isPrivate: true, eventId: latest.id,
                                createdAt: latest.createdAt, event: latest)
            } else {
                out[d] = .entry(text: EntryNotes.normalize(latest.content), isPrivate: false, eventId: latest.id,
                                createdAt: latest.createdAt, event: latest)
            }
        }

        // Tombstone-only days (rule 4): the address names the day.
        for address in tombstones.keys {
            let d = String(address.dropFirst(prefix.count))
            if out[d] == nil, latestPerDay[d] == nil { out[d] = deleted(d) }
        }

        // Rule 3: `e`-only kind 5s, matched on the recorded event id only.
        guard !localBases.isEmpty else { return out }
        let dayByBase = Dictionary(localBases.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
        for k5 in deletions where !k5.tags.contains(where: { $0.count >= 2 && $0[0] == "a" }) {
            for tag in k5.tags where tag.count >= 2 && tag[0] == "e" {
                guard let d = dayByBase[tag[1]] else { continue }
                // Another version of the day is on the relays: this kind 5
                // names only the old one, so it says nothing about the day.
                if let latest = latestPerDay[d], latest.id != tag[1] { continue }
                if case .deleted(let at, _)? = out[d], at >= k5.createdAt { continue }
                out[d] = .deleted(at: k5.createdAt, by: [k5.id])
            }
        }
        return out
    }
}

/// Settings read for a future write (interop §2.4, Seth's MUST): anything
/// that isn't a decryptable JSON object is unknown; `version > 1` is
/// read-only; unknown keys are kept so a writer can round-trip them
/// (addendum).
enum RemoteSettings: Equatable {
    case none
    case known(AppSettings, raw: [String: JSONValue], readOnly: Bool)
    case unknown

    static func read(_ events: [NostrEvent], owner pubkey: String, privateKey: Data) -> RemoteSettings {
        let candidates = events.filter {
            $0.kind == AppSettings.kind && $0.pubkey == pubkey && $0.tagValue("d") == AppSettings.dTag && $0.isValid
        }
        guard let latest = candidates.max(by: { ($0.createdAt, $1.id) < ($1.createdAt, $0.id) }) else { return .none }
        guard let json = try? NIP44.decryptFromSelf(latest.content, privateKey: privateKey),
              let data = json.data(using: .utf8),
              let object = try? JSONDecoder().decode([String: JSONValue].self, from: data)
        else { return .unknown }
        let parsed = AppSettings.parse(json)
        return .known(parsed.settings, raw: object, readOnly: parsed.isReadOnly)
    }
}

/// A JSON value, for keeping unknown settings keys byte-faithfully enough to
/// write them back.
indirect enum JSONValue: Codable, Equatable {
    case string(String), number(Double), bool(Bool), null
    case array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}
