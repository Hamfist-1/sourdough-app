#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
import BakeMath
import BakeCore
@testable import BakeStore

/// SwiftData tests. They run on Apple platforms only (Xcode, or `swift test` on a Mac).
@MainActor
@Suite("BakeService (SPEC §4–§5)")
struct BakeServiceTests {
    let container: ModelContainer
    let service: BakeService
    let formula = Formula(hydration: 0.72, saltPct: 0.02, starterPct: 0.20)

    init() throws {
        container = try BakeStoreContainer.make(inMemory: true)
        service = BakeService(context: container.mainContext)
    }

    private func version() throws -> RecipeVersion {
        let recipe = try service.createRecipe(name: "Country loaf", formula: formula)
        return try #require(recipe.latestVersion)
    }

    private func plan(hydration: Double? = nil) throws -> BakePlan {
        try BakePlan.build(formula: formula, process: ProcessPlan(),
                           inputs: BuildInputs(totalMass: 1000, hydration: hydration), loafCount: 2)
    }

    private func finishEvaluation(_ bake: Bake) {
        var logs = bake.logs
        var evaluation = Evaluation()
        evaluation.overall = 8
        logs.evaluation = evaluation
        bake.logs = logs
    }

    @Test func storedValuesRoundTrip() throws {
        let v = try version()
        #expect(v.number == 1)
        #expect(v.formula == formula)
        let bake = try service.startBake(from: v, plan: try plan())
        #expect(bake.plan?.targetMass == 1000)
        #expect(bake.status == .active)
        #expect(bake.currentStep == .mix)
    }

    @Test func onlyOneActiveBake() throws {
        let v = try version()
        let first = try service.startBake(from: v, plan: try plan())
        #expect(throws: BakeServiceError.anotherBakeActive) {
            try service.startBake(from: v, plan: try plan())
        }
        try service.abandon(first)
        #expect(first.status == .abandoned)
        #expect(!v.isFrozen)
        _ = try service.startBake(from: v, plan: try plan())
    }

    @Test func advanceFollowsColdFermentChoice() throws {
        let bake = try service.startBake(from: try version(), plan: try plan())
        for _ in 0..<3 { try service.advance(bake) }
        #expect(bake.currentStep == .proof)
        try service.advance(bake, coldFerment: true)
        #expect(bake.currentStep == .cold)
    }

    @Test func completingWithoutVariationFreezesTheVersion() throws {
        let v = try version()
        let bake = try service.startBake(from: v, plan: try plan())
        #expect(throws: BakeServiceError.evaluationIncomplete) { try service.complete(bake) }
        finishEvaluation(bake)
        let created = try service.complete(bake)
        #expect(created == nil)
        #expect(bake.status == .completed)
        #expect(v.isFrozen)
        #expect(throws: BakeServiceError.versionIsFrozen) {
            try service.update(v, formula: formula, process: ProcessPlan())
        }
    }

    @Test func variationMakesANewVersionAndMovesTheBake() throws {
        let v1 = try version()
        let bake = try service.startBake(from: v1, plan: try plan(hydration: 0.75))
        #expect(bake.variesFromVersion)
        finishEvaluation(bake)
        #expect(throws: BakeServiceError.versionChoiceRequired) { try service.complete(bake) }

        let v2 = try #require(try service.complete(bake, choice: .newVersion))
        #expect(v2.number == 2)
        #expect(v2.recipe?.id == v1.recipe?.id)
        #expect(v2.derivedFrom?.id == v1.id)
        #expect(v2.formula.hydration == 0.75)
        #expect(v2.changeNote == "Hydration 72% → 75%")
        #expect(bake.version?.id == v2.id)
        #expect(v2.isFrozen)
        #expect(!v1.isFrozen)
    }

    @Test func variationCanStartANewRecipe() throws {
        let v1 = try version()
        let bake = try service.startBake(from: v1, plan: try plan(hydration: 0.80))
        finishEvaluation(bake)
        let created = try #require(try service.complete(bake, choice: .newRecipe(name: "Wet country loaf")))
        #expect(created.number == 1)
        #expect(created.recipe?.name == "Wet country loaf")
        #expect(created.derivedFrom?.id == v1.id)
    }

    @Test func recipesWithBakesAreArchivedNotDeleted() throws {
        let v = try version()
        let recipe = try #require(v.recipe)
        _ = try service.startBake(from: v, plan: try plan())
        #expect(try service.delete(recipe) == .archived)
        #expect(recipe.isArchived)

        let empty = try service.createRecipe(name: "Unbaked", formula: formula)
        #expect(try service.delete(empty) == .deleted)
    }

    @Test func newVersionFromAFrozenOne() throws {
        let v1 = try version()
        let v2 = try service.newVersion(from: v1, changeNote: "Try more whole wheat")
        #expect(v2.number == 2)
        #expect(v2.derivedFrom?.id == v1.id)
        #expect(v2.formula == v1.formula)
    }

    @Test func previewContainerLoads() throws {
        let container = BakeStoreContainer.preview()
        let recipes = try container.mainContext.fetch(FetchDescriptor<Recipe>())
        #expect(recipes.count == 1)
        #expect(recipes.first?.latestVersion?.isFrozen == true)
    }
}
#endif
