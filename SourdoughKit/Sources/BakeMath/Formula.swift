import Foundation

/// A recipe version's formula in baker's percentages.
///
/// Every percentage is a decimal fraction of **total flour** (0.72 = 72%), where total
/// flour includes the flour inside the starter. See docs/SPEC.md §2.3 and §3.1.
public struct Formula: Codable, Hashable, Sendable {
    /// Total water ÷ total flour, the starter's water included.
    public var hydration: Double
    public var saltPct: Double
    /// Starter mass ÷ total flour.
    public var starterPct: Double
    /// Starter water ÷ starter flour (1.0 = 100%, 0.55 = a 55% biga).
    public var starterHydration: Double
    public var starterFlourType: String?
    /// The blend of the *added* flour. Shares sum to 1.0.
    public var flours: [FlourComponent]
    public var adjuncts: [AdjunctComponent]

    public init(
        hydration: Double,
        saltPct: Double,
        starterPct: Double,
        starterHydration: Double = 1.0,
        starterFlourType: String? = nil,
        flours: [FlourComponent] = [FlourComponent(share: 1)],
        adjuncts: [AdjunctComponent] = []
    ) {
        self.hydration = hydration
        self.saltPct = saltPct
        self.starterPct = starterPct
        self.starterHydration = starterHydration
        self.starterFlourType = starterFlourType
        self.flours = flours
        self.adjuncts = adjuncts
    }

    /// φ: the fraction of the starter that is flour. 100% hydration → 0.5.
    public var starterFlourFraction: Double { 1 / (1 + starterHydration) }

    /// 1 − φ: the fraction of the starter that is water.
    public var starterWaterFraction: Double { starterHydration / (1 + starterHydration) }

    /// A formula has at least one flour and at most three.
    public static let flourCountLimit = 1...3

    /// A: the sum of all adjunct percentages, whatever stage they're added in.
    public var adjunctPct: Double { adjuncts.reduce(0) { $0 + $1.pct } }
}

/// One flour in the added-flour blend.
public struct FlourComponent: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// White AP, whole wheat… Optional.
    public var type: String?
    /// Fraction of the added flour (0…1).
    public var share: Double

    public init(id: UUID = UUID(), type: String? = nil, share: Double) {
        self.id = id
        self.type = type
        self.share = share
    }
}

/// When an adjunct goes into the dough. All stages count toward the build math.
public enum AdjunctStage: String, Codable, Sendable, CaseIterable {
    case build, bulk, finalProof
}

/// An adjunct (seeds, cheese, inclusions…) as a percentage of total flour.
public struct AdjunctComponent: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var pct: Double
    public var stage: AdjunctStage

    public init(id: UUID = UUID(), name: String, pct: Double, stage: AdjunctStage = .build) {
        self.id = id
        self.name = name
        self.pct = pct
        self.stage = stage
    }
}
