import Foundation
import BakeMath

/// A recipe version's process settings. Every field is optional; they pre-fill the step screens.
/// SPEC §2.4.
///
/// All optional so stored JSON keeps decoding as fields are added later.
public struct ProcessPlan: Codable, Hashable, Sendable {
    // Mix
    @Lenient public var firstIn: FirstIn? = nil
    /// nil means the default, `withFirstMix`. Only asked when there is an autolyse.
    @Lenient public var starterTiming: StarterTiming? = nil
    /// Autolyse length in seconds. nil = no autolyse.
    public var autolyse: TimeInterval?
    @Lenient public var mixMethod: MixMethod? = nil
    public var mixDuration: TimeInterval?

    // Bulk
    @Lenient public var strengthMethod: StrengthMethod? = nil
    public var sets: Int?
    public var setInterval: TimeInterval?
    @Lenient public var targetRise: Rise? = nil
    public var bulkDuration: TimeInterval?

    // Shape
    @Lenient public var finalShape: FinalShape? = nil

    // Proof
    /// Target volume increase after shaping.
    @Lenient public var proofRise: ProofRise? = nil
    /// Expected proof time (optional; drives the proof timer).
    public var proofDuration: TimeInterval?
    public var proofTempC: Double?
    public var coldFerment: Bool?
    public var coldDuration: TimeInterval?
    public var coldTempC: Double?

    // Bake
    public var preheatTempC: Double?
    @Lenient public var vessel: Vessel? = nil
    public var steam: String?
    public var coveredTempC: Double?
    public var coveredDuration: TimeInterval?
    public var uncoveredTempC: Double?
    public var uncoveredDuration: TimeInterval?
    public var scored: Bool?

    public init() {}

    public var effectiveStarterTiming: StarterTiming { starterTiming ?? .withFirstMix }
    public var plansColdFerment: Bool { coldFerment ?? false }
}

/// What one bake set out to do, frozen when the Build step is confirmed. SPEC §2.5.
public struct BakePlan: Codable, Hashable, Sendable {
    /// The version's formula, with any changes made for this bake.
    public var formula: Formula
    /// The version's process plan, with any changes made for this bake.
    public var process: ProcessPlan
    public var targetMass: Double
    public var loafCount: Int
    /// The solved weights, including which inputs they were solved from (`weights.source`).
    public var weights: BuildResult

    /// - Parameter targetMass: the total the user typed, if any; otherwise the solved total.
    public init(formula: Formula, process: ProcessPlan, targetMass: Double? = nil, loafCount: Int, weights: BuildResult) {
        self.formula = formula
        self.process = process
        self.targetMass = targetMass ?? weights.totalMass
        self.loafCount = loafCount
        self.weights = weights
    }
}

public extension Formula {
    /// Starting point for a new recipe: 75% hydration, 2% salt, 20% starter at 100%.
    static func newRecipeDefault() -> Formula {
        Formula(hydration: 0.75, saltPct: 0.02, starterPct: 0.20, starterHydration: 1.0)
    }
}
