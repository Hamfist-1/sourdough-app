import Foundation
import Testing
import BakeMath
@testable import BakeCore

@Suite("Formula sheet")
struct FormulaSheetTests {
    @Test("Reference case A: totals first, parts add up exactly")
    func caseA() throws {
        let f = Formula(hydration: 0.75, saltPct: 0.02, starterPct: 0.20)
        let r = try BuildSolver.solve(f, BuildInputs(totalMass: 1000))
        let sheet = FormulaSheet.make(f, r)
        #expect(sheet.displayTotalDough == "1000 g")
        #expect(sheet.starter?.displayGrams == "113 g")
        #expect(sheet.starter?.summary == "20% · 100% hydration")

        #expect(sheet.rows.map(\.label) == ["Total flour", "Flour in starter", "Flour",
                                             "Total water (hydration)", "Water in starter", "Water", "Salt"])
        #expect(sheet.rows.map(\.kind) == [.total, .component, .component, .total, .component, .component, .ingredient])
        #expect(sheet.rows.map(\.displayPercent) == ["100%", "10%", "90%", "75%", "10%", "65%", "2%"])
        let g = sheet.rows.map(\.grams)
        #expect(g[0] == 565 && g[1] + g[2] == 565)
        #expect(g[3] == 424 && g[4] + g[5] == 424)
        #expect(g[1] + g[4] == 113)
        #expect(sheet.rows.last?.displayGrams == "11.3 g")
    }

    @Test("Three flours, adjuncts, no starter")
    func blendAndAdjuncts() throws {
        let f = Formula(
            hydration: 0.7, saltPct: 0.02, starterPct: 0,
            flours: [FlourComponent(type: "Bread", share: 0.7), FlourComponent(type: "Whole wheat", share: 0.2),
                     FlourComponent(type: "Rye", share: 0.1)],
            adjuncts: [AdjunctComponent(name: "Walnuts", pct: 0.15, stage: .bulk)]
        )
        let sheet = FormulaSheet.make(f, try BuildSolver.solve(f, BuildInputs(addedFlour: 500)))
        #expect(sheet.starter == nil)
        #expect(sheet.rows.map(\.label) == ["Total flour", "Bread", "Whole wheat", "Rye",
                                             "Total water (hydration)", "Salt", "Walnuts (in bulk)"])
        #expect(sheet.rows.prefix(4).map(\.displayGrams) == ["500 g", "350 g", "100 g", "50 g"])
        #expect(sheet.rows.last?.displayGrams == "75 g")
    }

    @Test("One flour and no starter shows just the totals")
    func singleFlourNoStarter() throws {
        let f = Formula(hydration: 0.7, saltPct: 0.02, starterPct: 0)
        let sheet = FormulaSheet.make(f, try BuildSolver.solve(f, BuildInputs(totalMass: 1000)))
        #expect(sheet.rows.map(\.label) == ["Total flour", "Total water (hydration)", "Salt"])
    }

    @Test("Apportioning keeps the sum exact")
    func apportion() {
        #expect(Rounding.apportion([508.47, 56.5], to: 565) .reduce(0, +) == 565)
        #expect(Rounding.apportion([33.4, 33.3, 33.3], to: 100) == [34, 33, 33])
        #expect(Rounding.apportion([10.9, 10.9], to: 21) .reduce(0, +) == 21)
        #expect(Rounding.apportion([], to: 0).isEmpty)
    }
}

@Suite("Recipe weights")
struct RecipeWeightsTests {
    @Test("Weights to percentages: 500 flour + 360 water + 11 salt + 100 starter at 100%")
    func weightsToPercent() throws {
        let w = RecipeWeights(formula: Formula(hydration: 0.7, saltPct: 0.02, starterPct: 0.1), totalMass: 1)
        var weights = w
        weights.flours[0].grams = 500
        weights.water = 360
        weights.salt = 11
        weights.starter = 100
        weights.starterHydration = 1.0
        let f = try #require(weights.formula())
        #expect(weights.totalMass == 971)
        #expect(abs(f.hydration - 410.0 / 550) < 1e-12)
        #expect(abs(f.saltPct - 0.02) < 1e-12)
        #expect(abs(f.starterPct - 100.0 / 550) < 1e-12)

        // And back: the same formula at 971 g gives the same weights.
        let back = RecipeWeights(formula: f, totalMass: 971)
        #expect(abs(back.flours[0].grams - 500) < 1e-9)
        #expect(abs(back.water - 360) < 1e-9)
        #expect(abs(back.starter - 100) < 1e-9)
    }

    @Test("Percentages to weights and back are the same recipe")
    func roundTrip() throws {
        let f = Formula(hydration: 0.78, saltPct: 0.021, starterPct: 0.15, starterHydration: 0.6,
                        flours: [FlourComponent(type: "Bread", share: 0.8), FlourComponent(type: "Rye", share: 0.2)],
                        adjuncts: [AdjunctComponent(name: "Seeds", pct: 0.08, stage: .bulk)])
        let w = RecipeWeights(formula: f, totalMass: 1800)
        #expect(abs(w.totalMass - 1800) < 1e-9)
        let back = try #require(w.formula())
        #expect(abs(back.hydration - f.hydration) < 1e-12)
        #expect(abs(back.starterPct - f.starterPct) < 1e-12)
        #expect(abs(back.flours[1].share - 0.2) < 1e-12)
        #expect(back.flours.map(\.id) == f.flours.map(\.id))
        #expect(abs(back.adjuncts[0].pct - 0.08) < 1e-12)
    }

    @Test("No flour or a negative weight isn't a recipe yet")
    func invalid() {
        var w = RecipeWeights(formula: Formula(hydration: 0.7, saltPct: 0.02, starterPct: 0.1), totalMass: 1000)
        w.flours[0].grams = 0
        #expect(w.formula() == nil)
        w.flours[0].grams = 500
        w.salt = -1
        #expect(w.formula() == nil)
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
        p.proofRise = .pct75
        p.scored = true
        p.proofDuration = 2 * 3600
        let sections = ProcessSummary.sections(p, unit: .fahrenheit)
        #expect(sections.map(\.title) == ["Mix", "Bulk ferment", "Proof", "Bake"])
        #expect(sections[0].items.map(\.value) == ["45 min", "with the first mix"])
        #expect(sections[1].items.first?.value == "4, every 30 min")
        #expect(sections[2].items.map(\.value) == ["75% rise", "2 h", "12 h at 39°F"])
        #expect(Rise.targets.map(\.label) == ["25%", "50%", "75%", "100%", "125%", "150%"])
        #expect(sections[3].items.map(\.label) == ["Scored", "Covered"])
        #expect(sections[3].items.map(\.value) == ["yes", "20 min at 482°F"])
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

@Suite("Starter split")
struct StarterSplitTests {
    @Test("200 g at 100% is 100 g flour + 100 g water")
    func split() {
        let parts = StarterAmount.split(grams: 200, starterHydration: 1.0)
        #expect(parts.flour == 100 && parts.water == 100)
        #expect(StarterAmount.description(grams: 155, starterHydration: 0.55) == "155 g starter = 100 g flour + 55 g water")
    }
}
