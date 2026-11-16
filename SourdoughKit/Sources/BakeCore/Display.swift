import Foundation
import BakeMath

// Display-ready views of formulas, weights and process plans, shared by the recipe page,
// Build and (later) the bake summary. Pure data, so it's tested here rather than in the UI.

// MARK: - Baker's percentage sheet

/// One line of the sheet: name, % of total flour, grams (already rounded for display).
public struct FormulaRow: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        /// Total flour or total water.
        case total
        /// A part of the total above it (each flour, flour in starter, water, water in starter).
        case component
        /// Salt and adjuncts.
        case ingredient
    }

    public let id: String
    public let label: String
    /// Fraction of total flour (0.75 = 75%).
    public let percent: Double
    /// Rounded for display; components add up exactly to their total.
    public let grams: Double
    public let kind: Kind
    /// Something you put on the scale for the build: each flour and the water you add (or the
    /// total itself when it has no parts shown). Shown in bold.
    public let isWeighed: Bool

    public init(id: String, label: String, percent: Double, grams: Double, kind: Kind, isWeighed: Bool = false) {
        self.id = id
        self.label = label
        self.percent = percent
        self.grams = grams
        self.kind = kind
        self.isWeighed = isWeighed
    }

    public var displayGrams: String { Format.number(grams) + " g" }
    public var displayPercent: String { Format.percent(percent) }
}

/// The starter, shown up top as an assumption rather than as another ingredient line.
public struct StarterLine: Hashable, Sendable {
    public let grams: Double
    public let percent: Double
    public let hydration: Double

    /// "20% · 100% hydration"
    public var summary: String { "\(Format.percent(percent)) · \(Format.percent(hydration)) hydration" }
    public var displayGrams: String { Format.number(grams) + " g" }
}

/// The baker's sheet for one batch. SPEC §6.
///
/// Leads with the total dough and the starter, then total flour and total water, each
/// followed by its parts (the flour in the starter, then the flours you add; the water in the
/// starter, then the water you add), then salt and adjuncts. Percentages are of total flour,
/// starter flour included (SPEC §3.1). Parts are rounded so they add up exactly to their total,
/// and the starter's flour and water add up exactly to the starter.
public struct FormulaSheet: Hashable, Sendable {
    public let totalDough: Double
    public let starter: StarterLine?
    public let rows: [FormulaRow]

    public var displayTotalDough: String { Format.number(totalDough) + " g" }

    public static func make(_ f: Formula, _ r: BuildResult) -> FormulaSheet {
        let F = r.totalFlour
        func pct(_ grams: Double) -> Double { F > 0 ? grams / F : 0 }
        let hasStarter = r.starter > 0

        // Starter first, so its parts add up to it.
        let starter = r.starter.rounded()
        let starterFlour = hasStarter ? min(r.starterFlour.rounded(), starter) : 0
        let starterWater = hasStarter ? starter - starterFlour : 0

        var rows: [FormulaRow] = []

        // Flour
        let totalFlour = F.rounded()
        let flourParts = Rounding.apportion(r.flours.map(\.grams), to: totalFlour - starterFlour)
        let showFlourParts = r.flours.count + (hasStarter ? 1 : 0) > 1
        rows.append(FormulaRow(id: "total-flour", label: "Total flour", percent: 1, grams: totalFlour, kind: .total,
                               isWeighed: !showFlourParts))
        if showFlourParts {
            if hasStarter {
                rows.append(FormulaRow(id: "starter-flour", label: "Flour in starter", percent: pct(r.starterFlour),
                                       grams: starterFlour, kind: .component))
            }
            for (index, (weight, grams)) in zip(r.flours, flourParts).enumerated() {
                rows.append(FormulaRow(
                    id: "flour-\(index)",
                    label: weight.name ?? (r.flours.count > 1 ? "Flour \(index + 1)" : "Flour"),
                    percent: pct(weight.grams), grams: grams, kind: .component, isWeighed: true
                ))
            }
        }

        // Water
        let totalWater = (r.addedWater + r.starterWater).rounded()
        rows.append(FormulaRow(id: "total-water", label: "Total water (hydration)", percent: r.hydration,
                               grams: totalWater, kind: .total, isWeighed: !hasStarter))
        if hasStarter {
            rows.append(FormulaRow(id: "starter-water", label: "Water in starter", percent: pct(r.starterWater),
                                   grams: starterWater, kind: .component))
            rows.append(FormulaRow(id: "water", label: "Water", percent: pct(r.addedWater),
                                   grams: totalWater - starterWater, kind: .component, isWeighed: true))
        }

        // Salt and adjuncts
        rows.append(FormulaRow(id: "salt", label: "Salt", percent: f.saltPct,
                               grams: WeightDisplay.rounded(r.salt, precise: true), kind: .ingredient))
        for (adjunct, weight) in zip(f.adjuncts, r.adjuncts) {
            rows.append(FormulaRow(
                id: "adjunct-\(adjunct.id)",
                label: adjunct.stage == .build ? adjunct.name : "\(adjunct.name) (in \(adjunct.stage.label))",
                percent: adjunct.pct, grams: WeightDisplay.rounded(weight.grams, precise: true), kind: .ingredient
            ))
        }

        return FormulaSheet(
            totalDough: r.totalMass.rounded(),
            starter: hasStarter ? StarterLine(grams: starter, percent: f.starterPct, hydration: f.starterHydration) : nil,
            rows: rows
        )
    }
}

public enum Rounding {
    /// Rounds `values` to whole grams so they add up exactly to `total` (largest remainder).
    public static func apportion(_ values: [Double], to total: Double) -> [Double] {
        guard !values.isEmpty else { return [] }
        let floors = values.map { $0.rounded(.down) }
        var result = floors
        var remaining = Int((total - floors.reduce(0, +)).rounded())
        let byFraction = values.indices.sorted { values[$0] - floors[$0] > values[$1] - floors[$1] }
        var i = 0
        while remaining > 0 {
            result[byFraction[i % byFraction.count]] += 1
            remaining -= 1
            i += 1
        }
        i = 0
        while remaining < 0 {
            let index = byFraction[byFraction.count - 1 - (i % byFraction.count)]
            if result[index] > 0 { result[index] -= 1; remaining += 1 }
            i += 1
            if i > 10 * byFraction.count { break }
        }
        return result
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

// MARK: - Starter split

public enum StarterAmount {
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
