import SwiftData

/// Migration plan for the garage store. Add a stage here with each new schema version.
public enum GarageMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [GarageSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
