import Foundation
import BakeMath

// Display-ready views of formulas, weights and process plans, shared by the recipe page,
// Build and (later) the bake summary. Pure data, so it's tested here rather than in the UI.

// MARK: - Baker's percentage table

/// One line of the combined table: name, % of total flour, grams.
public struct FormulaRow: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        /// Something you weigh out.
        case ingredient
        /// Flour or water already inside the starter (for information; not weighed separately).
        case fromStarter
        /// A subtotal or the dough total.
        case total
    }

    public let id: String
    public let label: String
    /// Fraction of total flour (0.75 = 75%).
    public let percent: Double
    public let grams: Double
    public let kind: Kind
    /// Show to 0.1 g (salt, adjuncts).
    public let precise: Bool

    public var displayGrams: String {
        Format.number(WeightDisplay.rounded(grams, precise: precise)) + " g"
    }

    public var displayPercent: String { Format.percent(percent) }
}

public struct FormulaSection: Hashable, Sendable, Identifiable {
    public var id: String { title }
    public let title: String
    public let rows: [FormulaRow]
}

public enum FormulaTable {
    /// The baker's sheet: what you weigh, what the starter brings, and the totals.
    /// Percentages are of total flour, starter flour included (SPEC §3.1).
    public static func sections(_ f: Formula, _ r: BuildResult) -> [FormulaSection] {
        let F = r.totalFlour
        func pct(_ grams: Double) -> Double { F > 0 ? grams / F : 0 }
        let hasStarter = r.starter > 0
        var sections: [FormulaSection] = []

        var flour = r.flours.enumerated().map { index, w in
            FormulaRow(id: "flour-\(index)", label: w.name ?? (r.flours.count > 1 ? "Flour \(index + 1)" : "Flour"),
                       percent: pct(w.grams), grams: w.grams, kind: .ingredient, precise: false)
        }
        if hasStarter {
            flour.append(FormulaRow(id: "starter-flour", label: "Flour in starter", percent: pct(r.starterFlour),
                                    grams: r.starterFlour, kind: .fromStarter, precise: false))
        }
        flour.append(FormulaRow(id: "total-flour", label: "Total flour", percent: 1, grams: F, kind: .total, precise: false))
        sections.append(FormulaSection(title: "Flour", rows: flour))

        var water = [FormulaRow(id: "water", label: "Water", percent: pct(r.addedWater), grams: r.addedWater,
                                kind: .ingredient, precise: false)]
        if hasStarter {
            water.append(FormulaRow(id: "starter-water", label: "Water in starter", percent: pct(r.starterWater),
                                    grams: r.starterWater, kind: .fromStarter, precise: false))
            water.append(FormulaRow(id: "total-water", label: "Total water (hydration)", percent: r.hydration,
                                    grams: r.addedWater + r.starterWater, kind: .total, precise: false))
        }
        sections.append(FormulaSection(title: "Water", rows: water))

        var other: [FormulaRow] = []
        if hasStarter {
            other.append(FormulaRow(id: "starter", label: "Starter at \(Format.percent(f.starterHydration)) hydration",
                                    percent: f.starterPct, grams: r.starter, kind: .ingredient, precise: false))
        }
        other.append(FormulaRow(id: "salt", label: "Salt", percent: f.saltPct, grams: r.salt, kind: .ingredient, precise: true))
        sections.append(FormulaSection(title: hasStarter ? "Starter and salt" : "Salt", rows: other))

        if !f.adjuncts.isEmpty {
            let adjuncts = zip(f.adjuncts, r.adjuncts).map { a, w in
                FormulaRow(id: "adjunct-\(a.id)", label: a.stage == .build ? a.name : "\(a.name) (in \(a.stage.label))",
                           percent: a.pct, grams: w.grams, kind: .ingredient, precise: true)
            }
            sections.append(FormulaSection(title: "Adjuncts", rows: adjuncts))
        }

        sections.append(FormulaSection(title: "Dough", rows: [
            FormulaRow(id: "total-dough", label: "Total dough", percent: pct(r.totalMass), grams: r.totalMass,
                       kind: .total, precise: false)
        ]))
        return sections
    }
}

public extension AdjunctStage {
    var label: String {
        switch self {
        case .build: "the mix"
        case .bulk: "bulk"
        case .finalProof: "final proof"
        }
    }
}

// MARK: - Process plan

public struct DetailItem: Hashable, Sendable, Identifiable {
    public var id: String { label }
    public let label: String
    public let value: String
}

public struct DetailSection: Hashable, Sendable, Identifiable {
    public var id: String { title }
    public let title: String
    public let items: [DetailItem]
}

public enum ProcessSummary {
    /// The process in bake order. Empty fields and empty sections are left out.
    public static func sections(_ p: ProcessPlan, unit: TemperatureUnit) -> [DetailSection] {
        func timeAt(_ duration: TimeInterval?, _ tempC: Double?) -> String? {
            switch (duration, tempC) {
            case let (d?, t?): "\(Format.duration(d)) at \(unit.format(celsius: t))"
            case let (d?, nil): Format.duration(d)
            case let (nil, t?): unit.format(celsius: t)
            default: nil
            }
        }
        func items(_ pairs: [(String, String?)]) -> [DetailItem] {
            pairs.compactMap { label, value in value.map { DetailItem(label: label, value: $0) } }
        }

        let mix = items([
            ("First in", p.firstIn?.label),
            ("Autolyse", p.autolyse.map(Format.duration)),
            ("Starter added", p.autolyse != nil ? p.effectiveStarterTiming.label : nil),
            ("Mix method", p.mixMethod?.label),
            ("Mix time", p.mixDuration.map(Format.duration)),
        ])

        let sets: String? = switch (p.sets, p.setInterval) {
        case let (n?, i?): "\(n), every \(Format.duration(i))"
        case let (n?, nil): "\(n)"
        case let (nil, i?): "every \(Format.duration(i))"
        default: nil
        }
        let bulk = items([
            ("Folds", p.strengthMethod?.label),
            ("Sets", sets),
            ("Target rise", p.targetRise?.label),
            ("Expected time", p.bulkDuration.map(Format.duration)),
        ])

        let shape = items([("Final shape", p.finalShape?.label)])

        let proof = items([
            ("Final proof", p.proofRise.map { "\($0.label) rise" }),
            ("Proof time", timeAt(p.proofDuration, p.proofTempC)),
            ("Cold ferment", p.plansColdFerment ? (timeAt(p.coldDuration, p.coldTempC) ?? "yes") : nil),
        ])

        let bake = items([
            ("Scored", p.scored.map { $0 ? "yes" : "no" }),
            ("Preheat", p.preheatTempC.map { unit.format(celsius: $0) }),
            ("Vessel", p.vessel?.label),
            ("Steam", p.steam),
            ("Covered", timeAt(p.coveredDuration, p.coveredTempC)),
            ("Uncovered", timeAt(p.uncoveredDuration, p.uncoveredTempC)),
        ])

        return [("Mix", mix), ("Bulk ferment", bulk), ("Shape", shape), ("Proof", proof), ("Bake", bake)]
            .filter { !$0.1.isEmpty }
            .map { DetailSection(title: $0.0, items: $0.1) }
    }
}

// MARK: - Messages

public extension BuildError {
    /// A sentence for the Build screen and version editor.
    var message: String {
        switch self {
        case .noFlours: "Add at least one flour."
        case .tooManyFlours: "A recipe can have at most three flours."
        case .flourSharesMustSumToOne(let sum): "The flour blend adds up to \(Format.percent(sum)); it needs to be 100%."
        case .invalidPercentage(let field): "\(field.label) can't be negative."
        case .missingInputs: "Enter a total dough weight, a flour weight or a water weight."
        case .inputNotPositive(let input): "\(input.label) needs to be more than zero."
        case .addedFlourNotPositive: "The starter supplies all the flour, so there's none left to add. Lower the starter %."
        case .starterWaterExceedsHydration: "The starter alone holds more water than this hydration allows. Raise the hydration or lower the starter."
        case .totalTooSmall: "The total is too small for the flour or water entered."
        case .conflict: "These numbers disagree. Clear one of them."
        case .cannotScaleFrom: "That ingredient is zero in this recipe, so it can't set the size."
        case .unknownIngredient: "That ingredient isn't in this recipe."
        }
    }
}

public extension FormulaField {
    var label: String {
        switch self {
        case .hydration: "Hydration"
        case .salt: "Salt"
        case .starter: "Starter"
        case .starterHydration: "Starter hydration"
        case .flourShare: "A flour's share"
        case .adjunct: "An adjunct"
        }
    }
}

public extension BuildInput {
    var label: String {
        switch self {
        case .totalMass: "Total dough"
        case .addedFlour: "Flour"
        case .addedWater: "Water"
        case .hydration: "Hydration"
        }
    }
}

// MARK: - Starter in grams

/// Converts between starter % and grams of starter in a dough of a given weight, so the
/// version editor can take the starter either way. The recipe always stores the %.
public enum StarterAmount {
    /// Total flour in a dough of `doughMass`. Doesn't depend on the starter %.
    public static func totalFlour(_ f: Formula, doughMass: Double) -> Double {
        doughMass / (1 + f.hydration + f.saltPct + f.adjunctPct)
    }

    /// Grams of starter in a dough of `doughMass`.
    public static func grams(_ f: Formula, doughMass: Double) -> Double {
        f.starterPct * totalFlour(f, doughMass: doughMass)
    }

    /// The starter % that puts `grams` of starter in a dough of `doughMass`.
    public static func percent(grams: Double, _ f: Formula, doughMass: Double) -> Double {
        let flour = totalFlour(f, doughMass: doughMass)
        return flour > 0 ? grams / flour : 0
    }

    /// How much of `grams` of starter is flour and how much is water.
    public static func split(grams: Double, starterHydration: Double) -> (flour: Double, water: Double) {
        let flour = grams / (1 + starterHydration)
        return (flour, grams - flour)
    }

    /// "200 g starter = 100 g flour + 100 g water"
    public static func description(grams: Double, starterHydration: Double) -> String {
        let parts = split(grams: grams, starterHydration: starterHydration)
        func g(_ x: Double) -> String { Format.number(WeightDisplay.rounded(x)) + " g" }
        return "\(g(grams)) starter = \(g(parts.flour)) flour + \(g(parts.water)) water"
    }
}
