import SwiftData

// Versioned schemas for the journal store (Chief P12, Audit M3b I1), so
// M5's changes to JournalEntry get an explicit migration path. Every stage
// so far only adds entities, which SwiftData migrates in place.

/// M2: the first shipped store.
enum JournalSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [JournalEntry.self] }
}

/// M3b: adds milestone acknowledgements.
enum JournalSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [JournalEntry.self, AcknowledgedMilestone.self] }
}

/// M4: adds one-time journal flags.
enum JournalSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] { [JournalEntry.self, AcknowledgedMilestone.self, JournalFlag.self] }
}

enum JournalMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [JournalSchemaV1.self, JournalSchemaV2.self, JournalSchemaV3.self] }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: JournalSchemaV1.self, toVersion: JournalSchemaV2.self),
            .lightweight(fromVersion: JournalSchemaV2.self, toVersion: JournalSchemaV3.self),
        ]
    }
}
