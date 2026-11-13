/// The fixed choices used across recipes and logs. See docs/SPEC.md §2.4 and §2.6.
///
/// Every choice has a `label` for display and for change notes (`PlanLabeled`).
/// Choices with an "other" case carry the user's own text.

/// Anything with a short human label, used by `PlanDiff` to describe changes.
public protocol PlanLabeled {
    var label: String { get }
}

public enum BakeStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case active, completed, abandoned
}

/// The steps of a bake, in order. Autolyse is part of `mix`. SPEC §4.
public enum BakeStep: String, Codable, Hashable, Sendable, CaseIterable, Comparable {
    case build, mix, bulk, shape, proof, cold, bake, evaluate

    /// The step after this one. `coldFerment` decides whether `proof` leads to `cold` or straight to `bake`.
    public func next(coldFerment: Bool) -> BakeStep? {
        switch self {
        case .build: .mix
        case .mix: .bulk
        case .bulk: .shape
        case .shape: .proof
        case .proof: coldFerment ? .cold : .bake
        case .cold: .bake
        case .bake: .evaluate
        case .evaluate: nil
        }
    }

    public static func < (a: BakeStep, b: BakeStep) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// Rise judged by eye, in 25% steps. SPEC §2.6.
public enum Rise: String, Codable, Hashable, Sendable, CaseIterable, PlanLabeled {
    case pct25, pct50, pct75, pct100, pct125, pct150, notMeasured

    public var percent: Int? {
        switch self {
        case .pct25: 25
        case .pct50: 50
        case .pct75: 75
        case .pct100: 100
        case .pct125: 125
        case .pct150: 150
        case .notMeasured: nil
        }
    }

    public var label: String { percent.map { "\($0)%" } ?? "not measured" }
}

public enum FirstIn: Codable, Hashable, Sendable, PlanLabeled {
    case flourWater, flourWaterSalt
    case other(String)

    public var label: String {
        switch self {
        case .flourWater: "flour + water"
        case .flourWaterSalt: "flour + water + salt"
        case .other(let text): text
        }
    }
}

/// When the starter goes in. Default: with the first mix, before autolyse.
public enum StarterTiming: String, Codable, Hashable, Sendable, CaseIterable, PlanLabeled {
    case withFirstMix, afterAutolyse

    public var label: String {
        switch self {
        case .withFirstMix: "with the first mix"
        case .afterAutolyse: "after autolyse"
        }
    }
}

public enum MixMethod: Codable, Hashable, Sendable, PlanLabeled {
    case hand, slapAndFold, mixer
    case other(String)

    public var label: String {
        switch self {
        case .hand: "by hand"
        case .slapAndFold: "slap and fold"
        case .mixer: "mixer"
        case .other(let text): text
        }
    }
}

public enum StrengthMethod: String, Codable, Hashable, Sendable, CaseIterable, PlanLabeled {
    case slapAndFold, stretchAndFold, coilFold, none

    public var label: String {
        switch self {
        case .slapAndFold: "slap and fold"
        case .stretchAndFold: "stretch and fold"
        case .coilFold: "coil fold"
        case .none: "none"
        }
    }
}

public enum FinalShape: Codable, Hashable, Sendable, PlanLabeled {
    case boule, batard, banneton, loafPan
    case other(String)

    public var label: String {
        switch self {
        case .boule: "boule"
        case .batard: "batard"
        case .banneton: "banneton"
        case .loafPan: "loaf pan"
        case .other(let text): text
        }
    }
}

public enum Vessel: Codable, Hashable, Sendable, PlanLabeled {
    case dutchOven, stone, steel, tray
    case other(String)

    public var label: String {
        switch self {
        case .dutchOven: "Dutch oven"
        case .stone: "stone"
        case .steel: "steel"
        case .tray: "tray"
        case .other(let text): text
        }
    }
}

public enum ColdLocation: Codable, Hashable, Sendable, PlanLabeled {
    case fridge
    case other(String)

    public var label: String {
        switch self {
        case .fridge: "fridge"
        case .other(let text): text
        }
    }
}
