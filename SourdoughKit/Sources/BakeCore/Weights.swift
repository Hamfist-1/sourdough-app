import Foundation
import BakeMath

/// A recipe written as weights: what goes on the scale. The editor's "Weights" mode edits this,
/// and the percentages are worked out from it. SPEC §2.3.
///
/// The starter's flour and water are backed out of its weight using its hydration, so total flour
/// is the flour you add plus the flour in the starter, the same way the percentages are defined.
public struct RecipeWeights: Hashable, Sendable {
    public struct Flour: Hashable, Sendable, Identifiable {
        public var id: UUID
        public var type: String?
        public var grams: Double
    }

    public struct Adjunct: Hashable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public var grams: Double
        public var stage: AdjunctStage
    }

    public var flours: [Flour]
    public var water: Double
    public var salt: Double
    public var starter: Double
    /// Starter water ÷ starter flour. Stays a percentage in both modes.
    public var starterHydration: Double
    public var starterFlourType: String?
    public var adjuncts: [Adjunct]

    /// The weights of `formula` scaled to `totalMass`.
    public init(formula f: Formula, totalMass: Double) {
        let r = try? BuildSolver.solve(f, BuildInputs(totalMass: totalMass))
        flours = f.flours.enumerated().map { index, flour in
            Flour(id: flour.id, type: flour.type, grams: r?.flours[index].grams ?? 0)
        }
        water = r?.addedWater ?? 0
        salt = r?.salt ?? 0
        starter = r?.starter ?? 0
        starterHydration = f.starterHydration
        starterFlourType = f.starterFlourType
        adjuncts = f.adjuncts.enumerated().map { index, adjunct in
            Adjunct(id: adjunct.id, name: adjunct.name, grams: r?.adjuncts[index].grams ?? 0, stage: adjunct.stage)
        }
    }

    /// The sum of everything you weigh.
    public var totalMass: Double {
        flours.reduce(0) { $0 + $1.grams } + water + salt + starter + adjuncts.reduce(0) { $0 + $1.grams }
    }

    /// The percentages these weights make, or nil while they can't make a dough yet
    /// (no flour, or a negative weight).
    public func formula() -> Formula? {
        let addedFlour = flours.reduce(0) { $0 + $1.grams }
        let all = flours.map(\.grams) + [water, salt, starter, starterHydration] + adjuncts.map(\.grams)
        guard addedFlour > 0, all.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }

        let (starterFlour, starterWater) = StarterAmount.split(grams: starter, starterHydration: starterHydration)
        let totalFlour = addedFlour + starterFlour
        return Formula(
            hydration: (water + starterWater) / totalFlour,
            saltPct: salt / totalFlour,
            starterPct: starter / totalFlour,
            starterHydration: starterHydration,
            starterFlourType: starterFlourType,
            flours: flours.map { FlourComponent(id: $0.id, type: $0.type, share: $0.grams / addedFlour) },
            adjuncts: adjuncts.map { AdjunctComponent(id: $0.id, name: $0.name, pct: $0.grams / totalFlour, stage: $0.stage) }
        )
    }
}
