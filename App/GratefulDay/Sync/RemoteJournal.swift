import Foundation
import NostrCore
import GratefulDayCore

/// What the relays hold for one day of the connected account (interop §1.4–1.7).
enum RemoteDay: Equatable {
    case entry(text: String, isPrivate: Bool, eventId: String, createdAt: Int, event: NostrEvent)
    /// A kind 5 covers the newest version (created_at ≤ deletion).
    case deleted(at: Int)
    /// The newest version exists but can't be decrypted or decoded: unknown,
    /// never empty, never written over.
    case blocked(eventId: String, createdAt: Int)
}

enum RemoteJournal {
    /// Per-day remote state from fetched events: only the owner's valid 36669s,
    /// newest per `d` (ties: lowest id), with the owner's kind 5s applied.
    static func days(from events: [NostrEvent], owner pubkey: String, privateKey: Data) -> [String: RemoteDay] {
        let entries = events.filter { DailyEntry.isValid($0, owner: pubkey) }
        let tombstones = EntryDeletion.tombstones(from: events, owner: pubkey)
        var out: [String: RemoteDay] = [:]
        for (d, latest) in DailyEntry.latestPerDay(entries) {
            if EntryDeletion.isDeleted(latest, tombstones: tombstones) {
                out[d] = .deleted(at: tombstones[EntryDeletion.address(pubkey: pubkey, dateString: d)] ?? latest.createdAt)
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
