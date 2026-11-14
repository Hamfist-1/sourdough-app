import Foundation
import Testing
@testable import BakeMath

/// Within 0.01 g (or 0.0001 for hydration): the spec's reference values are given to 2 decimals.
private func close(_ a: Double, _ b: Double, _ tolerance: Double = 0.01) -> Bool {
    abs(a - b) <= tolerance
}

/// Recipe used by reference cases A, C and F: 75%, 2% salt, 20% starter at 100%.
private let countryLoaf = Formula(hydration: 0.75, saltPct: 0.02, starterPct: 0.20, starterHydration: 1.0)

// MARK: - SPEC §3.5 reference cases

@Suite("SPEC §3.5 reference cases")
struct ReferenceCases {
    @Test("A. Total + hydration")
    func totalAndHydration() throws {
        let r = try BuildSolver.solve(countryLoaf, BuildInputs(totalMass: 1000, hydration: 0.75))
        #expect(close(r.totalFlour, 564.97))
        #expect(close(r.starter, 112.99))
        #expect(close(r.starterFlour, 56.50))
        #expect(close(r.starterWater, 56.50))
        #expect(close(r.addedFlour, 508.47))
        #expect(close(r.addedWater, 367.23))
        #expect(close(r.salt, 11.30))
        #expect(close(r.totalMass, 1000))
        #expect(!r.hydrationDiffersFromFormula)
    }

    @Test("B. Whiteboard example, no starter")
    func whiteboardExample() throws {
        let f = Formula(hydration: 0.63, saltPct: 0.02, starterPct: 0)
        let r = try BuildSolver.solve(f, BuildInputs(totalMass: 1200))
        #expect(close(r.totalFlour, 727.27))
        #expect(close(r.addedWater, 458.18))
        #expect(close(r.salt, 14.55))
        #expect(r.starter == 0)
    }

    @Test("C. Added flour + added water")
    func addedFlourAndWater() throws {
        let r = try BuildSolver.solve(countryLoaf, BuildInputs(addedFlour: 500, addedWater: 375))
        #expect(close(r.totalFlour, 555.56))
        #expect(close(r.hydration, 0.775, 0.0001))
        #expect(close(r.starter, 111.11))
        #expect(close(r.salt, 11.11))
        #expect(close(r.totalMass, 997.22))
        #expect(r.hydrationDiffersFromFormula)
    }

    @Test("D. Stiff biga at 55% hydration")
    func stiffBiga() throws {
        let f = Formula(hydration: 0.70, saltPct: 0.02, starterPct: 0.20, starterHydration: 0.55)
        let r = try BuildSolver.solve(f, BuildInputs(addedFlour: 500))
        #expect(close(f.starterFlourFraction, 0.6452, 0.0001))
        #expect(close(r.totalFlour, 574.07))
        #expect(close(r.starter, 114.81))
        #expect(close(r.starterFlour, 74.07))
        #expect(close(r.starterWater, 40.74))
        #expect(close(r.addedWater, 361.11))
        #expect(close(r.addedFlour, 500))
    }

    @Test("E. Impossible: starter holds more water than the hydration allows")
    func impossibleStarter() {
        let f = Formula(hydration: 0.40, saltPct: 0.02, starterPct: 1.0, starterHydration: 1.0)
        #expect(throws: BuildError.starterWaterExceedsHydration) {
            try BuildSolver.solve(f, BuildInputs(totalMass: 1000))
        }
    }

    @Test("F. Single-weight rescale from salt")
    func rescaleFromSalt() throws {
        let r = try BuildSolver.rescale(countryLoaf, hydration: 0.75, setting: .salt, to: 12)
        #expect(close(r.totalFlour, 600))
        #expect(close(r.salt, 12))
        #expect(close(r.addedFlour, 540))
        #expect(close(r.addedWater, 390))
        #expect(close(r.starter, 120))
        #expect(close(r.totalMass, 1062))
        #expect(r.source == .rescaled(.salt))
    }
}

// MARK: - Every way in gives the same dough

@Suite("Input pairs")
struct InputPairs {
    /// A formula with a flour blend, a stiff starter and an adjunct, to exercise every term.
    static let rye = UUID(), seeds = UUID()
    static let formula = Formula(
        hydration: 0.78, saltPct: 0.021, starterPct: 0.15, starterHydration: 0.6,
        flours: [FlourComponent(type: "Bread", share: 0.8), FlourComponent(id: rye, type: "Rye", share: 0.2)],
        adjuncts: [AdjunctComponent(id: seeds, name: "Seeds", pct: 0.08, stage: .bulk)]
    )

    @Test("Each pair reproduces the same build")
    func pairsAgree() throws {
        let reference = try BuildSolver.solve(Self.formula, BuildInputs(totalMass: 1500, hydration: 0.78))
        let variants: [BuildInputs] = [
            BuildInputs(totalMass: reference.totalMass, addedFlour: reference.addedFlour),
            BuildInputs(totalMass: reference.totalMass, addedWater: reference.addedWater),
            BuildInputs(addedFlour: reference.addedFlour, hydration: 0.78),
            BuildInputs(addedWater: reference.addedWater, hydration: 0.78),
            BuildInputs(addedFlour: reference.addedFlour, addedWater: reference.addedWater),
            BuildInputs(addedFlour: reference.addedFlour),
            BuildInputs(addedWater: reference.addedWater),
        ]
        for inputs in variants {
            let r = try BuildSolver.solve(Self.formula, inputs)
            #expect(close(r.totalFlour, reference.totalFlour, 1e-6))
            #expect(close(r.hydration, reference.hydration, 1e-9))
            #expect(close(r.totalMass, reference.totalMass, 1e-6))
        }
    }

    @Test("Totals add up and the blend splits the added flour")
    func blendAndAdjuncts() throws {
        let r = try BuildSolver.solve(Self.formula, BuildInputs(totalMass: 1500))
        let parts = r.addedFlour + r.addedWater + r.salt + r.starter + r.adjuncts.reduce(0) { $0 + $1.grams }
        #expect(close(parts, 1500, 1e-6))
        #expect(close(r.starterFlour + r.addedFlour, r.totalFlour, 1e-9))
        #expect(close((r.starterWater + r.addedWater) / r.totalFlour, 0.78, 1e-9))
        #expect(close(r.flours[0].grams, r.addedFlour * 0.8, 1e-9))
        #expect(close(r.flours[1].grams, r.addedFlour * 0.2, 1e-9))
        #expect(close(r.adjuncts[0].grams, r.totalFlour * 0.08, 1e-9))
        #expect(close(r.massPerLoaf(2), 750, 1e-6))
    }

    @Test("Rescaling from any ingredient keeps the proportions")
    func rescaleEveryIngredient() throws {
        let base = try BuildSolver.solve(Self.formula, BuildInputs(totalMass: 1000))
        let ingredients: [(Ingredient, Double)] = [
            (.totalMass, base.totalMass), (.addedFlour, base.addedFlour), (.addedWater, base.addedWater),
            (.salt, base.salt), (.starter, base.starter),
            (.flour(Self.rye), base.flours[1].grams), (.adjunct(Self.seeds), base.adjuncts[0].grams),
        ]
        for (ingredient, grams) in ingredients {
            let doubled = try BuildSolver.rescale(Self.formula, hydration: base.hydration, setting: ingredient, to: grams * 2)
            #expect(close(doubled.totalMass, base.totalMass * 2, 1e-6), "rescale from \(ingredient)")
        }
    }
}

// MARK: - Over-determined inputs

@Suite("Over-determined inputs")
struct OverDetermined {
    @Test("Three consistent inputs are accepted")
    func consistent() throws {
        let r = try BuildSolver.solve(countryLoaf, BuildInputs(totalMass: 1000, addedFlour: 508.5, hydration: 0.75))
        #expect(close(r.totalMass, 1000))
        #expect(r.source == .inputs([.totalMass, .addedFlour, .hydration]))
    }

    @Test("Three inputs that disagree are a conflict")
    func conflicting() {
        #expect(throws: BuildError.conflict([.totalMass, .addedFlour, .hydration])) {
            try BuildSolver.solve(countryLoaf, BuildInputs(totalMass: 1000, addedFlour: 600, hydration: 0.75))
        }
    }
}

// MARK: - Validation

@Suite("Validation")
struct Validation {
    @Test("Hydration alone is not enough")
    func onlyHydration() {
        #expect(throws: BuildError.missingInputs) {
            try BuildSolver.solve(countryLoaf, BuildInputs(hydration: 0.75))
        }
        #expect(throws: BuildError.missingInputs) {
            try BuildSolver.solve(countryLoaf, BuildInputs())
        }
    }

    @Test("Inputs must be positive")
    func nonPositive() {
        #expect(throws: BuildError.inputNotPositive(.totalMass)) {
            try BuildSolver.solve(countryLoaf, BuildInputs(totalMass: 0))
        }
        #expect(throws: BuildError.inputNotPositive(.addedWater)) {
            try BuildSolver.solve(countryLoaf, BuildInputs(addedWater: -5))
        }
    }

    @Test("Flour blend must add to 100%")
    func blendSum() {
        let f = Formula(hydration: 0.7, saltPct: 0.02, starterPct: 0.2,
                        flours: [FlourComponent(share: 0.7), FlourComponent(share: 0.2)])
        do {
            _ = try BuildSolver.solve(f, BuildInputs(totalMass: 1000))
            Issue.record("Expected flourSharesMustSumToOne")
        } catch {
            guard case .flourSharesMustSumToOne(let sum) = error else {
                Issue.record("Wrong error: \(error)")
                return
            }
            #expect(close(sum, 0.9, 1e-9))
        }
        let four = Formula(hydration: 0.7, saltPct: 0.02, starterPct: 0.2,
                           flours: Array(repeating: 0.25, count: 4).map { FlourComponent(share: $0) })
        #expect(throws: BuildError.tooManyFlours) {
            try BuildSolver.solve(four, BuildInputs(totalMass: 1000))
        }
        let three = Formula(hydration: 0.7, saltPct: 0.02, starterPct: 0.2,
                            flours: [0.5, 0.3, 0.2].map { FlourComponent(share: $0) })
        _ = try? BuildSolver.solve(three, BuildInputs(totalMass: 1000))
        #expect((try? BuildSolver.solve(three, BuildInputs(totalMass: 1000))) != nil)
        let none = Formula(hydration: 0.7, saltPct: 0.02, starterPct: 0.2, flours: [])
        #expect(throws: BuildError.noFlours) {
            try BuildSolver.solve(none, BuildInputs(totalMass: 1000))
        }
    }

    @Test("Negative percentages are rejected")
    func negativePercent() {
        let f = Formula(hydration: 0.7, saltPct: -0.01, starterPct: 0.2)
        #expect(throws: BuildError.invalidPercentage(.salt)) {
            try BuildSolver.solve(f, BuildInputs(totalMass: 1000))
        }
    }

    @Test("Starter that is all the flour leaves nothing to add")
    func starterIsAllFlour() {
        let f = Formula(hydration: 1.0, saltPct: 0.02, starterPct: 2.0, starterHydration: 1.0)
        #expect(throws: BuildError.addedFlourNotPositive) {
            try BuildSolver.solve(f, BuildInputs(totalMass: 1000))
        }
        #expect(throws: BuildError.addedFlourNotPositive) {
            try BuildSolver.solve(f, BuildInputs(addedFlour: 500))
        }
    }

    @Test("Water + hydration with too much starter water")
    func waterAndHydrationImpossible() {
        #expect(throws: BuildError.starterWaterExceedsHydration) {
            try BuildSolver.solve(countryLoaf, BuildInputs(addedWater: 300, hydration: 0.05))
        }
    }

    @Test("Total too small for the flour or water given")
    func totalTooSmall() {
        #expect(throws: BuildError.totalTooSmall) {
            try BuildSolver.solve(countryLoaf, BuildInputs(totalMass: 400, addedWater: 500))
        }
        #expect(throws: BuildError.totalTooSmall) {
            try BuildSolver.solve(countryLoaf, BuildInputs(totalMass: 400, addedFlour: 500))
        }
    }

    @Test("Can't rescale from an ingredient that is zero or missing")
    func badRescale() {
        let noStarter = Formula(hydration: 0.7, saltPct: 0.02, starterPct: 0)
        #expect(throws: BuildError.cannotScaleFrom(.starter)) {
            try BuildSolver.rescale(noStarter, hydration: 0.7, setting: .starter, to: 100)
        }
        let missing = UUID()
        #expect(throws: BuildError.unknownIngredient(.adjunct(missing))) {
            try BuildSolver.rescale(noStarter, hydration: 0.7, setting: .adjunct(missing), to: 50)
        }
    }

    @Test("Unusual hydration warns but still builds")
    func hydrationWarning() throws {
        let r = try BuildSolver.solve(countryLoaf, BuildInputs(totalMass: 1000, hydration: 1.3))
        #expect(r.warnings == [.hydrationOutsideTypicalRange(1.3)])
        #expect(r.hydrationDiffersFromFormula)
    }
}

// MARK: - Display rounding

@Suite("Weight display (SPEC §3.4)")
struct Display {
    @Test func rounding() {
        #expect(WeightDisplay.rounded(508.47) == 508)
        #expect(WeightDisplay.rounded(11.30) == 11.3)
        #expect(WeightDisplay.rounded(25.26, precise: true) == 25.3)
        #expect(WeightDisplay.rounded(19.96) == 20.0)
    }
}
