#if canImport(SwiftData)
import Foundation
import SwiftData
import BakeMath
import BakeCore

// SwiftData models. SPEC §2.
//
// CloudKit-ready from day one (SPEC §2.1):
// - every stored property has a default or is optional,
// - no unique constraints (identity is the `id` UUID),
// - every relationship is optional and has an inverse.
//
// Formulas, plans and logs are Codable values stored as JSON `Data` and exposed through
// computed properties. Enums are stored as their raw `String` so they can be used in predicates.

@Model
public final class Recipe {
    public var id: UUID = UUID()
    public var name: String = ""
    public var notes: String = ""
    public var createdAt: Date = Date()
    public var isArchived: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \RecipeVersion.recipe)
    public var versions: [RecipeVersion]? = []

    public init(name: String, notes: String = "") {
        self.id = UUID()
        self.name = name
        self.notes = notes
        self.createdAt = Date()
    }

    public var sortedVersions: [RecipeVersion] {
        (versions ?? []).sorted { $0.number < $1.number }
    }

    public var latestVersion: RecipeVersion? { sortedVersions.last }

    /// Version numbers are never reused.
    public var nextVersionNumber: Int {
        ((versions ?? []).map(\.number).max() ?? 0) + 1
    }

    /// True if any version has bakes (completed, active or abandoned).
    public var hasBakes: Bool {
        (versions ?? []).contains { !($0.bakes ?? []).isEmpty }
    }
}

@Model
public final class RecipeVersion {
    public var id: UUID = UUID()
    public var number: Int = 1
    public var createdAt: Date = Date()
    /// What changed from the version it was derived from.
    public var changeNote: String = ""
    var formulaData: Data = Data()
    var processData: Data = Data()

    public var recipe: Recipe?

    /// The version this one was made from, possibly in another recipe ("vary").
    public var derivedFrom: RecipeVersion?
    @Relationship(deleteRule: .nullify, inverse: \RecipeVersion.derivedFrom)
    public var derivatives: [RecipeVersion]? = []

    @Relationship(deleteRule: .nullify, inverse: \Bake.version)
    public var bakes: [Bake]? = []

    public init(number: Int, formula: Formula, process: ProcessPlan = ProcessPlan(), changeNote: String = "") {
        self.id = UUID()
        self.number = number
        self.createdAt = Date()
        self.changeNote = changeNote
        self.formulaData = StoredJSON.encode(formula)
        self.processData = StoredJSON.encode(process)
    }

    public var formula: Formula {
        get { StoredJSON.decode(Formula.self, from: formulaData) ?? .newRecipeDefault() }
        set { formulaData = StoredJSON.encode(newValue) }
    }

    public var process: ProcessPlan {
        get { StoredJSON.decode(ProcessPlan.self, from: processData) ?? ProcessPlan() }
        set { processData = StoredJSON.encode(newValue) }
    }

    /// Read-only once any bake of this version is completed. SPEC §5.3.
    public var isFrozen: Bool {
        VersionRules.isFrozen((bakes ?? []).map(\.status))
    }

    public var completedBakes: [Bake] {
        (bakes ?? []).filter { $0.status == .completed }.sorted { $0.startedAt < $1.startedAt }
    }
}

@Model
public final class Bake {
    public var id: UUID = UUID()
    var statusRaw: String = BakeStatus.active.rawValue
    var currentStepRaw: String = BakeStep.mix.rawValue
    public var startedAt: Date = Date()
    public var endedAt: Date?
    var planData: Data = Data()
    var logsData: Data = Data()

    /// The version this bake belongs to. Moves to the new version if the bake varied. SPEC §5.3.
    public var version: RecipeVersion?

    /// Bakes are created when the Build step is confirmed, so they start at `mix`.
    public init(plan: BakePlan, startedAt: Date = Date()) {
        self.id = UUID()
        self.startedAt = startedAt
        self.planData = StoredJSON.encode(plan)
        self.logsData = StoredJSON.encode(BakeLogs())
    }

    public var status: BakeStatus {
        get { BakeStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    public var currentStep: BakeStep {
        get { BakeStep(rawValue: currentStepRaw) ?? .mix }
        set { currentStepRaw = newValue.rawValue }
    }

    /// The snapshot taken at Build. Never changes afterwards; nil only if the stored data is unreadable.
    public var plan: BakePlan? {
        get { StoredJSON.decode(BakePlan.self, from: planData) }
        set { planData = newValue.map { StoredJSON.encode($0) } ?? Data() }
    }

    /// Every step's actuals.
    public var logs: BakeLogs {
        get { StoredJSON.decode(BakeLogs.self, from: logsData) ?? BakeLogs() }
        set { logsData = StoredJSON.encode(newValue) }
    }

    /// Matches the active bake, for `@Query(filter: Bake.isActive)`.
    public static var isActive: Predicate<Bake> {
        let active = BakeStatus.active.rawValue
        return #Predicate<Bake> { $0.statusRaw == active }
    }

    /// True if the plan differs from the version it started from (a deliberate change). SPEC §5.2.
    public var variesFromVersion: Bool {
        guard let plan, let version else { return false }
        return VersionRules.variesFromVersion(formula: version.formula, process: version.process, plan: plan)
    }
}
#endif
