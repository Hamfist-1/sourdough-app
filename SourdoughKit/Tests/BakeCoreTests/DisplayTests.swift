import Foundation
import Testing
import BakeMath
@testable import BakeCore

@Suite("Formula table")
struct FormulaTableTests {
    @Test("Reference case A as a baker's sheet")
    func caseA() throws {
        let f = Formula(hydration: 0.75, saltPct: 0.02, starterPct: 0.20)
        let r = try BuildSolver.solve(f, BuildInputs(totalMass: 1000))
        let sections = FormulaTable.sections(f, r)
        #expect(sections.map(\.title) == ["Flour", "Water", "Starter and salt", "Dough"])

        let rows = Dictionary(uniqueKeysWithValues: sections.flatMap(\.rows).map { ($0.id, $0) })
        #expect(rows["flour-0"]?.label == "Flour")
        #expect(rows["flour-0"]?.displayGrams == "508 g")
        #expect(rows["flour-0"]?.displayPercent == "90%")
        #expect(rows["starter-flour"]?.kind == .fromStarter)
        #expect(rows["starter-flour"]?.displayPercent == "10%")
        #expect(rows["total-flour"]?.displayGrams == "565 g")
        #expect(rows["water"]?.displayGrams == "367 g")
        #expect(rows["total-water"]?.displayPercent == "75%")
        #expect(rows["total-water"]?.displayGrams == "424 g")
        #expect(rows["starter"]?.label == "Starter at 100% hydration")
        #expect(rows["starter"]?.displayGrams == "113 g")
        #expect(rows["salt"]?.displayGrams == "11.3 g")
        #expect(rows["total-dough"]?.displayGrams == "1000 g")
        #expect(rows["total-dough"]?.displayPercent == "177%")
    }

    @Test("Three flours, adjuncts and no starter")
    func blendAndAdjuncts() throws {
        let f = Formula(
            hydration: 0.7, saltPct: 0.02, starterPct: 0,
            flours: [FlourComponent(type: "Bread", share: 0.7), FlourComponent(type: "Whole wheat", share: 0.2),
                     FlourComponent(type: "Rye", share: 0.1)],
            adjuncts: [AdjunctComponent(name: "Walnuts", pct: 0.15, stage: .bulk)]
        )
        let r = try BuildSolver.solve(f, BuildInputs(addedFlour: 500))
        let sections = FormulaTable.sections(f, r)
        #expect(sections.map(\.title) == ["Flour", "Water", "Salt", "Adjuncts", "Dough"])
        #expect(sections[0].rows.map(\.label) == ["Bread", "Whole wheat", "Rye", "Total flour"])
        #expect(sections[0].rows.map(\.displayGrams) == ["350 g", "100 g", "50 g", "500 g"])
        #expect(sections[1].rows.count == 1)
        #expect(sections[3].rows.first?.label == "Walnuts (in bulk)")
        #expect(sections[3].rows.first?.displayGrams == "75 g")
    }
}

@Suite("Process summary")
struct ProcessSummaryTests {
    @Test func emptyPlanHasNoSections() {
        #expect(ProcessSummary.sections(ProcessPlan(), unit: .fahrenheit).isEmpty)
    }

    @Test func combinesAndOrders() {
        var p = ProcessPlan()
        p.autolyse = 45 * 60
        p.sets = 4
        p.setInterval = 30 * 60
        p.coldFerment = true
        p.coldDuration = 12 * 3600
        p.coldTempC = 4
        p.coveredDuration = 20 * 60
        p.coveredTempC = 250
        let sections = ProcessSummary.sections(p, unit: .fahrenheit)
        #expect(sections.map(\.title) == ["Mix", "Bulk ferment", "Proof", "Bake"])
        #expect(sections[0].items.map(\.value) == ["45 min", "with the first mix"])
        #expect(sections[1].items.first?.value == "4, every 30 min")
        #expect(sections[2].items.first?.value == "12 h at 39°F")
        #expect(sections[3].items.first?.value == "20 min at 482°F")
    }
}

@Suite("Choices with other")
struct OtherChoiceTests {
    @Test func otherText() {
        #expect(Vessel.other("cloche").otherText == "cloche")
        #expect(Vessel.dutchOven.otherText == nil)
        #expect(Vessel.other("cloche").isOther)
        #expect(!FinalShape.standardChoices.contains { $0.isOther })
    }

    @Test func messages() {
        #expect(BuildError.tooManyFlours.message == "A recipe can have at most three flours.")
        #expect(BuildError.flourSharesMustSumToOne(0.9).message.contains("90%"))
    }
}

@Suite("Starter in grams")
struct StarterAmountTests {
    @Test("Your example: 200 g at 100% is 100 g flour + 100 g water")
    func split() {
        let parts = StarterAmount.split(grams: 200, starterHydration: 1.0)
        #expect(parts.flour == 100 && parts.water == 100)
        #expect(StarterAmount.description(grams: 200, starterHydration: 1.0) == "200 g starter = 100 g flour + 100 g water")
        #expect(StarterAmount.description(grams: 155, starterHydration: 0.55) == "155 g starter = 100 g flour + 55 g water")
    }

    @Test("Grams and % convert both ways and agree with the solver")
    func roundTrip() throws {
        var f = Formula(hydration: 0.75, saltPct: 0.02, starterPct: 0.20)
        #expect(abs(StarterAmount.grams(f, doughMass: 1000) - 112.99) < 0.01)

        f.starterPct = StarterAmount.percent(grams: 200, f, doughMass: 1000)
        let r = try BuildSolver.solve(f, BuildInputs(totalMass: 1000))
        #expect(abs(r.starter - 200) < 1e-9)
        #expect(abs(r.starterFlour - 100) < 1e-9)
        #expect(abs(r.totalMass - 1000) < 1e-9)
    }
}
