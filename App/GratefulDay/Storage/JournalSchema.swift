import Foundation
import SwiftData

// Versioned schemas for the journal store (Chief P12, Audit M3b I1).
//
// Each older version holds a FROZEN nested copy of its models, exactly as
// that version shipped (Audit, PR #11): if older versions pointed at the
// live classes, changing the live model would change their checksums too,
// and a store written by an older build would match no version and fail to
// open. Never edit a frozen copy. Add a new version instead.
//
// The live models are JournalSchemaV7's; `JournalEntry`, `AcknowledgedMilestone`
// and `JournalFlag` are typealiases to them.

typealias JournalEntry = JournalSchemaV7.JournalEntry
typealias AcknowledgedMilestone = JournalSchemaV7.AcknowledgedMilestone
typealias JournalFlag = JournalSchemaV7.JournalFlag
typealias AccountMarker = JournalSchemaV7.AccountMarker
typealias EarlierVersion = JournalSchemaV7.EarlierVersion
typealias OutboxEvent = JournalSchemaV7.OutboxEvent

/// M2: the first shipped store.
enum JournalSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [JournalEntry.self] }

    @Model final class JournalEntry {
        @Attribute(.unique) var dateString: String
        var dayOfYear: Int
        var publishedAt: Int
        var timeZoneID: String
        var notesText: String
        var isPrivate: Bool = true
        var createdAt: Date
        var updatedAt: Date
        var syncStateRaw: String = "localOnly"
        var deletedAt: Date?
        var remoteEventID: String?
        var remoteCreatedAt: Int?
        init(dateString: String, dayOfYear: Int, publishedAt: Int, timeZoneID: String, notesText: String, now: Date) {
            self.dateString = dateString; self.dayOfYear = dayOfYear; self.publishedAt = publishedAt
            self.timeZoneID = timeZoneID; self.notesText = notesText; self.createdAt = now; self.updatedAt = now
        }
    }
}

/// M3b: adds milestone acknowledgements.
enum JournalSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [JournalEntry.self, AcknowledgedMilestone.self] }

    @Model final class JournalEntry {
        @Attribute(.unique) var dateString: String
        var dayOfYear: Int
        var publishedAt: Int
        var timeZoneID: String
        var notesText: String
        var isPrivate: Bool = true
        var createdAt: Date
        var updatedAt: Date
        var syncStateRaw: String = "localOnly"
        var deletedAt: Date?
        var remoteEventID: String?
        var remoteCreatedAt: Int?
        init(dateString: String, dayOfYear: Int, publishedAt: Int, timeZoneID: String, notesText: String, now: Date) {
            self.dateString = dateString; self.dayOfYear = dayOfYear; self.publishedAt = publishedAt
            self.timeZoneID = timeZoneID; self.notesText = notesText; self.createdAt = now; self.updatedAt = now
        }
    }

    @Model final class AcknowledgedMilestone {
        @Attribute(.unique) var total: Int
        var acknowledgedAt: Date
        init(total: Int, acknowledgedAt: Date) { self.total = total; self.acknowledgedAt = acknowledgedAt }
    }
}

/// M4: adds one-time journal flags.
enum JournalSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] { [JournalEntry.self, AcknowledgedMilestone.self, JournalFlag.self] }

    @Model final class JournalEntry {
        @Attribute(.unique) var dateString: String
        var dayOfYear: Int
        var publishedAt: Int
        var timeZoneID: String
        var notesText: String
        var isPrivate: Bool = true
        var createdAt: Date
        var updatedAt: Date
        var syncStateRaw: String = "localOnly"
        var deletedAt: Date?
        var remoteEventID: String?
        var remoteCreatedAt: Int?
        init(dateString: String, dayOfYear: Int, publishedAt: Int, timeZoneID: String, notesText: String, now: Date) {
            self.dateString = dateString; self.dayOfYear = dayOfYear; self.publishedAt = publishedAt
            self.timeZoneID = timeZoneID; self.notesText = notesText; self.createdAt = now; self.updatedAt = now
        }
    }

    @Model final class AcknowledgedMilestone {
        @Attribute(.unique) var total: Int
        var acknowledgedAt: Date
        init(total: Int, acknowledgedAt: Date) { self.total = total; self.acknowledgedAt = acknowledgedAt }
    }

    @Model final class JournalFlag {
        @Attribute(.unique) var name: String
        var setAt: Date
        init(name: String, setAt: Date) { self.name = name; self.setAt = setAt }
    }
}

enum JournalMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [JournalSchemaV1.self, JournalSchemaV2.self, JournalSchemaV3.self, JournalSchemaV4.self, JournalSchemaV5.self, JournalSchemaV6.self, JournalSchemaV7.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: JournalSchemaV1.self, toVersion: JournalSchemaV2.self),
            .lightweight(fromVersion: JournalSchemaV2.self, toVersion: JournalSchemaV3.self),
            // M5a: entries become unique per (owner, date). Every row that
            // existed before accounts is a guest row (design r3.1, P17).
            .custom(fromVersion: JournalSchemaV3.self, toVersion: JournalSchemaV4.self, willMigrate: nil, didMigrate: { context in
                let entries = try context.fetch(FetchDescriptor<JournalSchemaV4.JournalEntry>())
                for entry in entries where entry.entryKey == nil {
                    entry.entryKey = JournalSchemaV4.JournalEntry.key(owner: nil, dateString: entry.dateString)
                }
                try context.save()
            }),
            // M5b-1: adds the EarlierVersion archive only.
            .lightweight(fromVersion: JournalSchemaV4.self, toVersion: JournalSchemaV5.self),
            // M5b-2: adds the outbox only.
            .lightweight(fromVersion: JournalSchemaV5.self, toVersion: JournalSchemaV6.self),
            // M6: two local fields on EarlierVersion; old rows read as private.
            .lightweight(fromVersion: JournalSchemaV6.self, toVersion: JournalSchemaV7.self),
        ]
    }
}
