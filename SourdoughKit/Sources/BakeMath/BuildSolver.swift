import Foundation

// MARK: - Inputs

/// What the user typed on the Build screen. Any field may be empty.
///
/// `addedFlour` and `addedWater` are what goes on the scale, excluding the starter's
/// own flour and water. See docs/SPEC.md §3.2.
public struct BuildInputs: Hashable, Sendable {
    public var totalMass: Double?
    public var addedFlour: Double?
    public var addedWater: Double?
    /// Overrides the formula's hydration for this bake.
    public var hydration: Double?

    public init(totalMass: Double? = nil, addedFlour: Double? = nil, addedWater: Double? = nil, hydration: Double? = nil) {
        self.totalMass = totalMass
        self.addedFlour = addedFlour
        self.addedWater = addedWater
        self.hydration = hydration
    }

    /// The inputs that were given, in a fixed order.
    var given: [(BuildInput, Double)] {
        var result: [(BuildInput, Double)] = []
        if let totalMass { result.append((.totalMass, totalMass)) }
        if let addedFlour { result.append((.addedFlour, addedFlour)) }
        if let addedWater { result.append((.addedWater, addedWater)) }
        if let hydration { result.append((.hydration, hydration)) }
        return result
    }
}

public enum BuildInput: String, Codable, Hashable, Sendable, CaseIterable {
    case totalMass, addedFlour, addedWater, hydration
}

/// A single weight the user can edit after a build to rescale everything else.
public enum Ingredient: Codable, Hashable, Sendable {
    case totalMass, addedFlour, addedWater, salt, starter
    case flour(UUID)
    case adjunct(UUID)
}

// MARK: - Results

public struct IngredientWeight: Codable, Hashable, Sendable {
    public let id: UUID
    public let name: String?
    public let grams: Double
}

public enum BuildSource: Codable, Hashable, Sendable {
    /// Solved from what the user typed.
    case inputs(Set<BuildInput>)
    /// Rescaled from one edited weight.
    case rescaled(Ingredient)
}

public enum BuildWarning: Codable, Hashable, Sendable {
    case hydrationOutsideTypicalRange(Double)
}

/// Every weight for one build, in grams (unrounded). See docs/SPEC.md §3.1.
public struct BuildResult: Codable, Hashable, Sendable {
    public let totalFlour: Double
    public let hydration: Double
    public let addedFlour: Double
    public let addedWater: Double
    public let salt: Double
    public let starter: Double
    public let starterFlour: Double
    public let starterWater: Double
    /// Each added flour, by blend share.
    public let flours: [IngredientWeight]
    public let adjuncts: [IngredientWeight]
    public let totalMass: Double
    public let source: BuildSource
    /// True when the solved hydration differs from the formula's, which makes the bake a variation.
    public let hydrationDiffersFromFormula: Bool
    public let warnings: [BuildWarning]

    /// Default per-loaf weight: total ÷ loaves, each equal.
    public func massPerLoaf(_ loaves: Int) -> Double {
        loaves > 0 ? totalMass / Double(loaves) : 0
    }
}

// MARK: - Errors

public enum FormulaField: Hashable, Sendable {
    case hydration, salt, starter, starterHydration, flourShare, adjunct
}

public enum BuildError: Error, Hashable, Sendable {
    /// The formula has no flour.
    case noFlours
    /// More than three flours (Formula.flourCountLimit).
    case tooManyFlours
    /// The flour blend doesn't add up to 100%. Carries the actual sum.
    case flourSharesMustSumToOne(Double)
    /// A percentage in the formula is negative or not a number.
    case invalidPercentage(FormulaField)
    /// No weight was given (total, flour or water), so nothing can be scaled.
    case missingInputs
    /// A typed value is zero, negative or not a number.
    case inputNotPositive(BuildInput)
    /// The starter supplies all of the flour, leaving nothing to add.
    case addedFlourNotPositive
    /// The starter alone holds more water than the target hydration allows.
    case starterWaterExceedsHydration
    /// The total is too small for the flour or water given.
    case totalTooSmall
    /// More inputs were given than needed, and they disagree.
    case conflict(Set<BuildInput>)
    /// That ingredient is zero in this formula, so it can't drive a rescale.
    case cannotScaleFrom(Ingredient)
    /// The ingredient id isn't in this formula.
    case unknownIngredient(Ingredient)
}

// MARK: - Solver

/// The Build scaling engine. Pure functions, no state. See docs/SPEC.md §3.
public enum BuildSolver {
    /// Over-determined inputs agree if every weight is within this many grams…
    public static let weightTolerance = 1.0
    /// …and hydration is within half a percentage point.
    public static let hydrationTolerance = 0.005
    /// Hydrations outside this range produce a warning, not an error.
    public static let typicalHydration: ClosedRange<Double> = 0.4...1.2

    private static let epsilon = 1e-9

    /// Solves a build from any sufficient set of inputs.
    ///
    /// - One weight alone uses the formula's hydration.
    /// - Two inputs are solved directly.
    /// - Three or four are solved from every pair and must agree.
    public static func solve(_ formula: Formula, _ inputs: BuildInputs) throws(BuildError) -> BuildResult {
        try validate(formula)

        let given = inputs.given
        for (input, value) in given where !(value.isFinite && value > 0) {
            throw .inputNotPositive(input)
        }
        guard given.contains(where: { $0.0 != .hydration }) else { throw .missingInputs }

        var values = Dictionary(uniqueKeysWithValues: given)
        if given.count == 1 {
            guard formula.hydration.isFinite, formula.hydration >= 0 else { throw .invalidPercentage(.hydration) }
            values[.hydration] = formula.hydration
        }

        let order = BuildInput.allCases.filter { values[$0] != nil }
        var pairs: [(BuildInput, BuildInput)] = []
        for i in order.indices {
            for j in order.indices where j > i { pairs.append((order[i], order[j])) }
        }

        var results: [BuildResult] = []
        let source = BuildSource.inputs(Set(given.map(\.0)))
        for (a, b) in pairs {
            let (totalFlour, hydration) = try solvePair(a, b, values, formula)
            results.append(try weights(formula, totalFlour: totalFlour, hydration: hydration, source: source))
        }

        let first = results[0]
        for other in results.dropFirst() where !agree(first, other) {
            throw .conflict(Set(given.map(\.0)))
        }
        return first
    }

    /// Rescales a build after the user edits one weight.
    ///
    /// - Parameter hydration: the hydration in effect for this build (from the previous result).
    public static func rescale(
        _ formula: Formula,
        hydration: Double,
        setting ingredient: Ingredient,
        to grams: Double
    ) throws(BuildError) -> BuildResult {
        try validate(formula)
        guard hydration.isFinite, hydration >= 0 else { throw .invalidPercentage(.hydration) }
        guard grams.isFinite, grams > 0 else { throw .cannotScaleFrom(ingredient) }

        let pct = try percentage(of: ingredient, formula, hydration: hydration)
        guard pct > epsilon else { throw .cannotScaleFrom(ingredient) }
        return try weights(formula, totalFlour: grams / pct, hydration: hydration, source: .rescaled(ingredient))
    }

    // MARK: Internals

    /// Checks a formula on its own, before any inputs. Used by the version editor too.
    public static func validate(_ formula: Formula) throws(BuildError) {
        guard !formula.flours.isEmpty else { throw .noFlours }
        guard formula.flours.count <= Formula.flourCountLimit.upperBound else { throw .tooManyFlours }
        func ok(_ x: Double) -> Bool { x.isFinite && x >= 0 }
        guard ok(formula.saltPct) else { throw .invalidPercentage(.salt) }
        guard ok(formula.starterPct) else { throw .invalidPercentage(.starter) }
        guard ok(formula.starterHydration) else { throw .invalidPercentage(.starterHydration) }
        guard formula.flours.allSatisfy({ ok($0.share) }) else { throw .invalidPercentage(.flourShare) }
        guard formula.adjuncts.allSatisfy({ ok($0.pct) }) else { throw .invalidPercentage(.adjunct) }
        let sum = formula.flours.reduce(0) { $0 + $1.share }
        guard abs(sum - 1) <= 0.001 else { throw .flourSharesMustSumToOne(sum) }
    }

    /// Returns (total flour F, hydration h) for one pair of inputs. SPEC §3.2.
    static func solvePair(
        _ a: BuildInput, _ b: BuildInput,
        _ v: [BuildInput: Double],
        _ f: Formula
    ) throws(BuildError) -> (Double, Double) {
        let p = f.starterPct
        let starterFlourPerF = p * f.starterFlourFraction   // pφ
        let starterWaterPerF = p * f.starterWaterFraction   // p(1−φ)
        let fixed = 1 + f.saltPct + f.adjunctPct            // 1 + s + A
        let addedFlourPerF = 1 - starterFlourPerF           // 1 − pφ

        func addedFlourToF(_ fa: Double) throws(BuildError) -> Double {
            guard addedFlourPerF > epsilon else { throw .addedFlourNotPositive }
            return fa / addedFlourPerF
        }

        switch (a, b) {
        case (.totalMass, .hydration):
            return (v[.totalMass]! / (fixed + v[.hydration]!), v[.hydration]!)

        case (.totalMass, .addedFlour):
            let F = try addedFlourToF(v[.addedFlour]!)
            let h = v[.totalMass]! / F - fixed
            guard h >= 0 else { throw .totalTooSmall }
            return (F, h)

        case (.totalMass, .addedWater):
            let remaining = v[.totalMass]! - v[.addedWater]!
            guard remaining > 0 else { throw .totalTooSmall }
            let F = remaining / (fixed + starterWaterPerF)
            return (F, v[.addedWater]! / F + starterWaterPerF)

        case (.addedFlour, .hydration):
            return (try addedFlourToF(v[.addedFlour]!), v[.hydration]!)

        case (.addedWater, .hydration):
            let h = v[.hydration]!
            guard h - starterWaterPerF > epsilon else { throw .starterWaterExceedsHydration }
            return (v[.addedWater]! / (h - starterWaterPerF), h)

        case (.addedFlour, .addedWater):
            let F = try addedFlourToF(v[.addedFlour]!)
            return (F, v[.addedWater]! / F + starterWaterPerF)

        default:
            // Pairs are always built in BuildInput.allCases order, so this can't happen.
            preconditionFailure("Unordered input pair \(a), \(b)")
        }
    }

    /// Every weight from total flour and hydration. SPEC §3.1.
    static func weights(_ f: Formula, totalFlour F: Double, hydration h: Double, source: BuildSource) throws(BuildError) -> BuildResult {
        guard F.isFinite, F > 0 else { throw .totalTooSmall }

        let starter = f.starterPct * F
        let starterFlour = starter * f.starterFlourFraction
        let starterWater = starter * f.starterWaterFraction
        let addedFlour = F - starterFlour
        let addedWater = h * F - starterWater
        guard addedFlour > epsilon else { throw .addedFlourNotPositive }
        guard addedWater >= -epsilon else { throw .starterWaterExceedsHydration }

        let salt = f.saltPct * F
        let flours = f.flours.map { IngredientWeight(id: $0.id, name: $0.type, grams: $0.share * addedFlour) }
        let adjuncts = f.adjuncts.map { IngredientWeight(id: $0.id, name: $0.name, grams: $0.pct * F) }
        let adjunctTotal = adjuncts.reduce(0) { $0 + $1.grams }
        let total = addedFlour + max(addedWater, 0) + salt + starter + adjunctTotal

        var warnings: [BuildWarning] = []
        if !typicalHydration.contains(h) { warnings.append(.hydrationOutsideTypicalRange(h)) }

        return BuildResult(
            totalFlour: F,
            hydration: h,
            addedFlour: addedFlour,
            addedWater: max(addedWater, 0),
            salt: salt,
            starter: starter,
            starterFlour: starterFlour,
            starterWater: starterWater,
            flours: flours,
            adjuncts: adjuncts,
            totalMass: total,
            source: source,
            hydrationDiffersFromFormula: abs(h - f.hydration) > 0.0005,
            warnings: warnings
        )
    }

    /// The ingredient's grams per gram of total flour.
    static func percentage(of ingredient: Ingredient, _ f: Formula, hydration h: Double) throws(BuildError) -> Double {
        let addedFlourPerF = 1 - f.starterPct * f.starterFlourFraction
        switch ingredient {
        case .totalMass:
            return 1 + h + f.saltPct + f.adjunctPct
        case .addedFlour:
            return addedFlourPerF
        case .addedWater:
            return h - f.starterPct * f.starterWaterFraction
        case .salt:
            return f.saltPct
        case .starter:
            return f.starterPct
        case .flour(let id):
            guard let flour = f.flours.first(where: { $0.id == id }) else { throw .unknownIngredient(ingredient) }
            return flour.share * addedFlourPerF
        case .adjunct(let id):
            guard let adjunct = f.adjuncts.first(where: { $0.id == id }) else { throw .unknownIngredient(ingredient) }
            return adjunct.pct
        }
    }

    static func agree(_ x: BuildResult, _ y: BuildResult) -> Bool {
        let pairs = [
            (x.totalFlour, y.totalFlour), (x.addedFlour, y.addedFlour), (x.addedWater, y.addedWater),
            (x.salt, y.salt), (x.starter, y.starter), (x.totalMass, y.totalMass),
        ]
        return pairs.allSatisfy { abs($0 - $1) <= weightTolerance }
            && abs(x.hydration - y.hydration) <= hydrationTolerance
    }
}
