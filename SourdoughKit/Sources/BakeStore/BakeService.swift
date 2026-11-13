#if canImport(SwiftData)
import Foundation
import SwiftData
import BakeMath
import BakeCore

public enum BakeServiceError: Error, Hashable, Sendable {
    /// Only one bake can be active at a time. SPEC §5.1.
    case anotherBakeActive
    case bakeNotActive
    /// Completing needs an overall score from 1 to 10.
    case evaluationIncomplete
    /// The bake varied from its version, so the user must choose where to save it. SPEC §5.3.
    case versionChoiceRequired
    case versionIsFrozen
    case missingPlan
}

public enum RecipeDeletion: Hashable, Sendable {
    case deleted
    /// The recipe has bakes, so it was archived instead. SPEC §5.4.
    case archived
}

/// The operations the screens call. Each one saves the context. SPEC §4–§5.
@MainActor
public struct BakeService {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Recipes and versions

    /// A new recipe with version 1.
    @discardableResult
    public func createRecipe(name: String, formula: Formula, process: ProcessPlan = ProcessPlan()) throws -> Recipe {
        let recipe = Recipe(name: name)
        context.insert(recipe)
        let version = RecipeVersion(number: 1, formula: formula, process: process)
        context.insert(version)
        version.recipe = recipe
        try context.save()
        return recipe
    }

    /// Edits a version in place. Only allowed before its first completed bake.
    public func update(_ version: RecipeVersion, formula: Formula, process: ProcessPlan) throws {
        guard !version.isFrozen else { throw BakeServiceError.versionIsFrozen }
        version.formula = formula
        version.process = process
        try context.save()
    }

    /// "New version from this": the next version of the same recipe, starting as a copy.
    @discardableResult
    public func newVersion(from source: RecipeVersion, changeNote: String = "") throws -> RecipeVersion {
        let version = RecipeVersion(
            number: source.recipe?.nextVersionNumber ?? source.number + 1,
            formula: source.formula,
            process: source.process,
            changeNote: changeNote
        )
        context.insert(version)
        version.recipe = source.recipe
        version.derivedFrom = source
        try context.save()
        return version
    }

    /// Deletes a recipe with no bakes; archives one that has bakes.
    public func delete(_ recipe: Recipe) throws -> RecipeDeletion {
        if recipe.hasBakes {
            recipe.isArchived = true
            try context.save()
            return .archived
        }
        context.delete(recipe)
        try context.save()
        return .deleted
    }

    // MARK: Bakes

    public func activeBake() throws -> Bake? {
        var descriptor = FetchDescriptor<Bake>(predicate: Bake.isActive)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Starts a bake from a solved plan (see `BakePlan.build`). Fails if another bake is active.
    @discardableResult
    public func startBake(from version: RecipeVersion, plan: BakePlan, at date: Date = Date()) throws -> Bake {
        guard try activeBake() == nil else { throw BakeServiceError.anotherBakeActive }
        let bake = Bake(plan: plan, startedAt: date)
        context.insert(bake)
        bake.version = version
        try context.save()
        return bake
    }

    /// Moves to the next step. At `proof`, `coldFerment` overrides the plan's default.
    public func advance(_ bake: Bake, coldFerment: Bool? = nil) throws {
        guard bake.status == .active else { throw BakeServiceError.bakeNotActive }
        let cold = coldFerment ?? bake.plan?.process.plansColdFerment ?? false
        if let next = bake.currentStep.next(coldFerment: cold) {
            bake.currentStep = next
            try context.save()
        }
    }

    /// Keeps the bake and what was logged, marked abandoned. It never freezes its version.
    public func abandon(_ bake: Bake, at date: Date = Date()) throws {
        guard bake.status == .active else { throw BakeServiceError.bakeNotActive }
        bake.status = .abandoned
        bake.endedAt = date
        try context.save()
    }

    /// Completes a bake. If it varied from its version, `choice` is required: a new version
    /// (or recipe) is made from the bake's plan and the bake moves to it. SPEC §5.3.
    ///
    /// - Returns: the new version, if one was made.
    @discardableResult
    public func complete(
        _ bake: Bake,
        choice: CompletionChoice? = nil,
        changeNote: String? = nil,
        unit: TemperatureUnit = .default,
        at date: Date = Date()
    ) throws -> RecipeVersion? {
        guard bake.status == .active else { throw BakeServiceError.bakeNotActive }
        guard bake.logs.evaluation?.canComplete == true else { throw BakeServiceError.evaluationIncomplete }
        guard let plan = bake.plan else { throw BakeServiceError.missingPlan }

        var created: RecipeVersion?
        if bake.variesFromVersion {
            guard let choice else { throw BakeServiceError.versionChoiceRequired }
            let source = bake.version
            let note = changeNote ?? source.map {
                PlanDiff.changeNote(
                    PlanDiff.changes(from: ($0.formula, $0.process), to: (plan.formula, plan.process)),
                    unit: unit
                )
            } ?? ""

            let version: RecipeVersion
            switch choice {
            case .newVersion:
                version = RecipeVersion(
                    number: source?.recipe?.nextVersionNumber ?? 1,
                    formula: plan.formula, process: plan.process, changeNote: note
                )
                context.insert(version)
                version.recipe = source?.recipe
            case .newRecipe(let name):
                let recipe = Recipe(name: name)
                context.insert(recipe)
                version = RecipeVersion(number: 1, formula: plan.formula, process: plan.process, changeNote: note)
                context.insert(version)
                version.recipe = recipe
            }
            version.derivedFrom = source
            bake.version = version
            created = version
        }

        bake.status = .completed
        bake.endedAt = date
        try context.save()
        return created
    }
}
#endif
