#if canImport(SwiftData)
import Foundation
import SwiftData
import BakeMath
import BakeCore

/// Schema version 1. When models change, add `SchemaV2` and a migration stage below.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    public static var models: [any PersistentModel.Type] { [Recipe.self, RecipeVersion.self, Bake.self] }
}

public enum BakeMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

public enum BakeStoreContainer {
    /// The app's container.
    ///
    /// iCloud sync is off until there is a paid developer account (DECISIONS.md). To turn it on,
    /// add the iCloud capability with a CloudKit container in Xcode and pass `.automatic` here.
    public static func make(
        inMemory: Bool = false,
        cloudKit: ModelConfiguration.CloudKitDatabase = .none
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: cloudKit
        )
        return try ModelContainer(for: schema, migrationPlan: BakeMigrationPlan.self, configurations: [configuration])
    }

    /// An in-memory container with a sample recipe and bake, for SwiftUI previews.
    @MainActor
    public static func preview() -> ModelContainer {
        do {
            let container = try make(inMemory: true)
            try SampleData.insert(into: container.mainContext)
            return container
        } catch {
            fatalError("Preview container failed: \(error)")
        }
    }
}

/// Sample data matching the whiteboard's summary example.
@MainActor
public enum SampleData {
    public static func insert(into context: ModelContext) throws {
        let service = BakeService(context: context)

        var process = ProcessPlan()
        process.firstIn = .flourWater
        process.autolyse = 45 * 60
        process.strengthMethod = .stretchAndFold
        process.sets = 4
        process.setInterval = 30 * 60
        process.targetRise = .pct50
        process.finalShape = .batard
        process.coldFerment = true
        process.coldDuration = 12 * 3600
        process.preheatTempC = 245
        process.vessel = .dutchOven
        process.coveredDuration = 20 * 60
        process.uncoveredDuration = 25 * 60

        let formula = Formula(
            hydration: 0.72, saltPct: 0.02, starterPct: 0.20, starterHydration: 1.0,
            flours: [FlourComponent(type: "Bread flour", share: 0.9), FlourComponent(type: "Whole wheat", share: 0.1)]
        )
        let recipe = try service.createRecipe(name: "Country loaf", formula: formula, process: process)
        guard let version = recipe.latestVersion else { return }

        let start = Date().addingTimeInterval(-2 * 86_400)
        let plan = try BakePlan.build(formula: formula, process: process, inputs: BuildInputs(totalMass: 1200), loafCount: 2)
        let bake = try service.startBake(from: version, plan: plan, at: start)

        var logs = BakeLogs()
        var bulk = BulkLog()
        bulk.start = start.addingTimeInterval(3600)
        bulk.end = bulk.start?.addingTimeInterval(5 * 3600 + 600)
        bulk.roomTempC = 24
        bulk.doughTempStartC = 26
        bulk.actualRise = .pct50
        logs.bulk = bulk
        var evaluation = Evaluation()
        evaluation.crumb = 8
        evaluation.ovenSpring = 6
        evaluation.overall = 7
        evaluation.nextTime = "Try 10 min less bulk for more spring."
        logs.evaluation = evaluation
        bake.logs = logs
        bake.currentStep = .evaluate

        try service.complete(bake, at: start.addingTimeInterval(20 * 3600))
    }
}
#endif
