import Foundation
import Testing
import BakeMath
@testable import BakeCore

private let formula = Formula(hydration: 0.72, saltPct: 0.02, starterPct: 0.20)

@Suite("Bake steps (SPEC §4)")
struct Steps {
    @Test func orderWithoutColdFerment() {
        var step: BakeStep? = .build
        var path: [BakeStep] = []
        while let current = step { path.append(current); step = current.next(coldFerment: false) }
        #expect(path == [.build, .mix, .bulk, .shape, .proof, .bake, .evaluate])
    }

    @Test func coldFermentAddsAStep() {
        #expect(BakeStep.proof.next(coldFerment: true) == .cold)
        #expect(BakeStep.cold.next(coldFerment: true) == .bake)
        #expect(BakeStep.evaluate.next(coldFerment: true) == nil)
        #expect(BakeStep.mix < BakeStep.bake)
    }
}

@Suite("Plans and variation (SPEC §5.2)")
struct Variation {
    @Test func samePlanIsNotAVariation() throws {
        let plan = try BakePlan.build(formula: formula, process: ProcessPlan(), inputs: BuildInputs(totalMass: 1000), loafCount: 2)
        #expect(plan.targetMass == 1000)
        #expect(!VersionRules.variesFromVersion(formula: formula, process: ProcessPlan(), plan: plan))
    }

    @Test func differentHydrationAtBuildIsAVariation() throws {
        let plan = try BakePlan.build(formula: formula, process: ProcessPlan(),
                                      inputs: BuildInputs(totalMass: 1000, hydration: 0.75), loafCount: 2)
        #expect(plan.formula.hydration == 0.75)
        #expect(VersionRules.variesFromVersion(formula: formula, process: ProcessPlan(), plan: plan))
    }

    @Test func consistentWeightsAreNotAVariation() throws {
        let reference = try BuildSolver.solve(formula, BuildInputs(totalMass: 1000))
        let plan = try BakePlan.build(formula: formula, process: ProcessPlan(),
                                      inputs: BuildInputs(addedFlour: reference.addedFlour, addedWater: reference.addedWater),
                                      loafCount: 1)
        #expect(plan.formula.hydration == formula.hydration)
    }

    @Test func plannedProcessChangeIsAVariation() throws {
        var plan = try BakePlan.build(formula: formula, process: ProcessPlan(), inputs: BuildInputs(totalMass: 1000), loafCount: 1)
        plan.process.starterTiming = .afterAutolyse
        #expect(VersionRules.variesFromVersion(formula: formula, process: ProcessPlan(), plan: plan))
    }

    @Test func loafCountMustBePositive() {
        #expect(throws: BakePlanError.loafCountMustBePositive) {
            try BakePlan.build(formula: formula, process: ProcessPlan(), inputs: BuildInputs(totalMass: 1000), loafCount: 0)
        }
    }

    @Test func frozenOnlyAfterACompletedBake() {
        #expect(!VersionRules.isFrozen([]))
        #expect(!VersionRules.isFrozen([.abandoned, .active]))
        #expect(VersionRules.isFrozen([.abandoned, .completed]))
    }
}

@Suite("Change notes (SPEC §5.3)")
struct ChangeNotes {
    @Test func describesFormulaAndProcessChanges() {
        var newFormula = formula
        newFormula.hydration = 0.75
        var oldProcess = ProcessPlan()
        oldProcess.autolyse = 30 * 60
        oldProcess.proofTempC = 24
        var newProcess = oldProcess
        newProcess.autolyse = 60 * 60
        newProcess.starterTiming = .afterAutolyse
        newProcess.proofTempC = 26

        let changes = PlanDiff.changes(from: (formula, oldProcess), to: (newFormula, newProcess))
        let note = PlanDiff.changeNote(changes, unit: .fahrenheit)
        #expect(note == "Hydration 72% → 75%; Starter timing none → after autolyse; Autolyse 30 min → 1 h; Proof temp 75°F → 79°F")
        #expect(PlanDiff.changeNote(changes, unit: .celsius).hasSuffix("Proof temp 24°C → 26°C"))
    }

    @Test func describesFlourBlendAndAdjuncts() {
        var b = formula
        b.flours = [FlourComponent(type: "Bread", share: 0.8), FlourComponent(type: "Rye", share: 0.2)]
        b.adjuncts = [AdjunctComponent(name: "Seeds", pct: 0.08, stage: .bulk)]
        let note = PlanDiff.changeNote(PlanDiff.changes(from: (formula, ProcessPlan()), to: (b, ProcessPlan())), unit: .fahrenheit)
        #expect(note == "Flour flour 100% → Bread 80%, Rye 20%; Adjuncts none → Seeds 8% (bulk)")
    }

    @Test func noChangesNoNote() {
        #expect(PlanDiff.changes(from: (formula, ProcessPlan()), to: (formula, ProcessPlan())).isEmpty)
    }

    @Test func humanizesLabels() {
        #expect(PlanDiff.humanize("proofTempC") == "Proof temp")
        #expect(PlanDiff.humanize("setInterval") == "Set interval")
        #expect(PlanDiff.humanize("autolyse") == "Autolyse")
    }
}

@Suite("Logs (SPEC §2.6)")
struct Logs {
    @Test func durationsComeFromTimestamps() {
        var bulk = BulkLog()
        #expect(bulk.duration == nil)
        let start = Date(timeIntervalSince1970: 0)
        bulk.start = start
        bulk.end = start.addingTimeInterval(5 * 3600)
        #expect(bulk.duration == TimeInterval(5 * 3600))
        bulk.end = start.addingTimeInterval(-1)
        #expect(bulk.duration == nil)
    }

    @Test func equalLoaves() {
        let shape = ShapeLog.equalLoaves(totalWeight: 1500, count: 3, shape: .batard)
        #expect(shape.loaves?.count == 3)
        #expect(shape.loaves?.allSatisfy { $0.weight == 500 && $0.finalShape == .batard } == true)
        #expect(ShapeLog.equalLoaves(totalWeight: 1500, count: 0).loaves?.isEmpty == true)
    }

    @Test func evaluationRules() {
        var e = Evaluation()
        #expect(!e.canComplete)
        e.overall = 7
        #expect(e.canComplete)
        e.custom = ["Blisters": 11]
        #expect(!e.scoresAreValid)
        e.custom = ["Blisters": 9]
        #expect(e.scoresAreValid)
    }

    @Test func riseLabels() {
        #expect(Rise.pct75.label == "75%")
        #expect(Rise.notMeasured.percent == nil)
        #expect(Rise.allCases.compactMap(\.percent) == [25, 50, 75, 100, 125, 150])
    }
}

@Suite("Storage round trips")
struct Storage {
    @Test func planSurvivesJSON() throws {
        var process = ProcessPlan()
        process.firstIn = .other("water + starter")
        process.vessel = .dutchOven
        process.targetRise = .pct50
        let plan = try BakePlan.build(formula: formula, process: process,
                                      inputs: BuildInputs(totalMass: 1200, hydration: 0.74), loafCount: 2)
        let data = StoredJSON.encode(plan)
        #expect(StoredJSON.decode(BakePlan.self, from: data) == plan)
    }

    @Test func logsSurviveJSON() {
        var logs = BakeLogs()
        var mix = MixLog()
        mix.mixMethod = .other("stand mixer, dough hook")
        mix.addedNow = ["salt"]
        logs.mix = mix
        logs.shape = .equalLoaves(totalWeight: 1000, count: 2, shape: .other("couronne"))
        logs.additions = [AdjunctAddition(name: "Olives", grams: 80, stage: .bulk, at: Date(timeIntervalSince1970: 100))]
        #expect(StoredJSON.decode(BakeLogs.self, from: StoredJSON.encode(logs)) == logs)
    }

    @Test func emptyOrBadDataDecodesToNil() {
        #expect(StoredJSON.decode(BakeLogs.self, from: Data()) == nil)
        #expect(StoredJSON.decode(BakeLogs.self, from: Data("nope".utf8)) == nil)
    }

    @Test func olderDataWithFewerFieldsStillDecodes() {
        #expect(StoredJSON.decode(ProcessPlan.self, from: Data("{}".utf8)) == ProcessPlan())
        #expect(StoredJSON.decode(BakeLogs.self, from: Data(#"{"mix":{}}"#.utf8))?.mix == MixLog())
    }
}

@Suite("Units, formatting and timers")
struct Support {
    @Test func temperatures() {
        #expect(TemperatureUnit.default == .fahrenheit)
        #expect(TemperatureUnit.fahrenheit.format(celsius: 24) == "75°F")
        #expect(TemperatureUnit.celsius.format(celsius: 24) == "24°C")
        #expect(abs(TemperatureUnit.fahrenheit.toCelsius(212) - 100) < 1e-9)
    }

    @Test func formatting() {
        #expect(Format.percent(0.725) == "72.5%")
        #expect(Format.percent(0.72) == "72%")
        #expect(Format.duration(45 * 60) == "45 min")
        #expect(Format.duration(90 * 60) == "1 h 30 min")
        #expect(Format.duration(12 * 3600) == "12 h")
    }

    @Test func timers() {
        let id = UUID()
        #expect(TimerSchedule.notificationID(bakeID: id, timer: .fold, index: 2) == "bake-\(id.uuidString)-fold-2")
        #expect(TimerSchedule.notificationID(bakeID: id, timer: .proof).hasPrefix(TimerSchedule.notificationPrefix(bakeID: id)))
        let start = Date(timeIntervalSince1970: 0)
        #expect(TimerSchedule.remaining(start: start, duration: 600, now: start.addingTimeInterval(200)) == 400)
        #expect(TimerSchedule.remaining(start: start, duration: 600, now: start.addingTimeInterval(900)) == 0)
        #expect(TimerSchedule.foldTimes(bulkStart: start, sets: 3, interval: 1800)
                == [1800, 3600, 5400].map { start.addingTimeInterval($0) })
        #expect(BakeTimer.covered.step == .bake)
    }
}
