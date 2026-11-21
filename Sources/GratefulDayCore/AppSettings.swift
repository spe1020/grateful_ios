import Foundation
import NostrCore

/// Kind 30078 encrypted settings (spec §2; web `src/lib/appSettings.ts`).
public struct AppSettings: Equatable, Sendable {
    public var privacyDefault: Bool?
    public var celebratedMilestones: [Int]
    public var lastSeenNotifications: Int?

    public init(privacyDefault: Bool? = nil, celebratedMilestones: [Int] = [], lastSeenNotifications: Int? = nil) {
        self.privacyDefault = privacyDefault
        self.celebratedMilestones = Array(Set(celebratedMilestones)).sorted()
        self.lastSeenNotifications = lastSeenNotifications
    }

    public static let kind = 30078
    public static let dTag = "gratefulday:settings"
    public static let alt = "Encrypted gratefulday settings"
    public static let version = 1

    /// Web `reconcile`: privacy last-write-wins (remote if set), milestones union, lastSeen max.
    public static func reconcile(local: AppSettings, remote: AppSettings?) -> AppSettings {
        let lastSeen = max(local.lastSeenNotifications ?? 0, remote?.lastSeenNotifications ?? 0)
        return AppSettings(
            privacyDefault: remote?.privacyDefault ?? local.privacyDefault,
            celebratedMilestones: local.celebratedMilestones + (remote?.celebratedMilestones ?? []),
            lastSeenNotifications: lastSeen == 0 ? nil : lastSeen
        )
    }

    /// Exactly what web's `serializeSettings` writes (`JSON.stringify`, absent keys omitted).
    public func serialized() -> String {
        var parts = ["\"version\":\(Self.version)"]
        if let privacyDefault { parts.append("\"privacyDefault\":\(privacyDefault)") }
        parts.append("\"celebratedMilestones\":[\(celebratedMilestones.map(String.init).joined(separator: ","))]")
        if let lastSeenNotifications { parts.append("\"lastSeenNotifications\":\(lastSeenNotifications)") }
        return "{" + parts.joined(separator: ",") + "}"
    }

    /// Parse result: tolerant like web's `parseSettings`, plus the `version`
    /// so iOS can refuse to write a format it doesn't understand (spec §2.4).
    public struct Parsed: Equatable, Sendable {
        public let settings: AppSettings
        public let version: Int?
        /// `version > 1`: read, but never write.
        public var isReadOnly: Bool { (version ?? 1) > AppSettings.version }
    }

    public static func parse(_ json: String) -> Parsed {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return Parsed(settings: AppSettings(), version: nil) }
        let privacy = (obj["privacyDefault"] as? NSNumber).flatMap { isBool($0) ? $0.boolValue : nil }
        let milestones = (obj["celebratedMilestones"] as? [Any])?.compactMap { v -> Int? in
            guard let n = v as? NSNumber, !isBool(n) else { return nil }
            return n.intValue
        } ?? []
        let lastSeen = (obj["lastSeenNotifications"] as? NSNumber).flatMap { isBool($0) ? nil : $0.intValue }
        let version = (obj["version"] as? NSNumber).flatMap { isBool($0) ? nil : $0.intValue }
        return Parsed(settings: AppSettings(privacyDefault: privacy, celebratedMilestones: milestones, lastSeenNotifications: lastSeen), version: version)
    }

    private static func isBool(_ n: NSNumber) -> Bool { CFGetTypeID(n) == CFBooleanGetTypeID() }

    /// Unsigned 30078 for these settings, encrypted to self.
    public func template(privateKey: Data) throws -> UnsignedEvent {
        let payload = try NIP44.encryptToSelf(serialized(), privateKey: privateKey)
        return UnsignedEvent(kind: Self.kind, tags: [["d", Self.dTag], DailyEntry.encryptedTag, ["alt", Self.alt]], content: payload)
    }

    public enum ReadError: Error, Equatable { case undecryptable }

    /// Decrypt and parse a settings event. Unlike web, a failed decrypt is an
    /// error ("unknown"), never "no settings" (spec §2.4).
    ///
    /// REQUIRED before iOS gets any settings write path (interop spec §2.4):
    /// decrypted text that is not a valid JSON object must also be "unknown"
    /// and block the write. `parse` stays tolerant to match web today, so it
    /// still returns empty settings for that case; a writer must not use that
    /// result as a base to publish over.
    public static func read(_ event: NostrEvent, privateKey: Data) throws -> Parsed {
        guard let json = try? NIP44.decryptFromSelf(event.content, privateKey: privateKey) else { throw ReadError.undecryptable }
        return parse(json)
    }
}
