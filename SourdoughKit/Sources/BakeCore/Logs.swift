import Foundation
import BakeMath

/// What actually happened at each step. A nil field means "as planned". SPEC §2.6.
///
/// All fields are optional so stored JSON keeps decoding as fields are added later.

/// A log with a start and end. Durations are always computed, never stored.
public protocol TimedLog {
    var start: Date? { get }
    var end: Date? { get }
}

public extension TimedLog {
    var duration: TimeInterval? {
        guard let start, let end, end >= start else { return nil }
        return end.timeIntervalSince(start)
    }
}

public struct TempReading: Codable, Hashable, Sendable {
    public var at: Date
    public var tempC: Double

    public init(at: Date, tempC: Double) {
        self.at = at
        self.tempC = tempC
    }
}

public struct MixLog: Codable, Hashable, Sendable {
    @Lenient public var firstIn: FirstIn? = nil
    @Lenient public var starterTiming: StarterTiming? = nil
    public var autolyseStart: Date?
    public var autolyseEnd: Date?
    public var autolyseContents: String?
    @Lenient public var mixMethod: MixMethod? = nil
    public var mixDuration: TimeInterval?
    /// What went in after autolyse (salt, starter, other).
    public var addedNow: [String]?
    public var doughTempC: Double?

    public init() {}

    public var autolyseDuration: TimeInterval? {
        guard let autolyseStart, let autolyseEnd, autolyseEnd >= autolyseStart else { return nil }
        return autolyseEnd.timeIntervalSince(autolyseStart)
    }
}

public struct BulkLog: Codable, Hashable, Sendable, TimedLog {
    public var start: Date?
    public var end: Date?
    @Lenient public var strengthMethod: StrengthMethod? = nil
    public var sets: Int?
    public var setInterval: TimeInterval?
    public var roomTempC: Double?
    public var doughTempStartC: Double?
    public var doughTempReadings: [TempReading]?
    @Lenient public var targetRise: Rise? = nil
    @Lenient public var actualRise: Rise? = nil

    public init() {}
}

public struct LoafLog: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var weight: Double?
    @Lenient public var finalShape: FinalShape? = nil
    public var scored: Bool?

    public init(id: UUID = UUID(), weight: Double? = nil, finalShape: FinalShape? = nil, scored: Bool? = nil) {
        self.id = id
        self.weight = weight
        self.finalShape = finalShape
        self.scored = scored
    }
}

/// Divide and final shape.
public struct ShapeLog: Codable, Hashable, Sendable {
    public var loaves: [LoafLog]?

    public init(loaves: [LoafLog]? = nil) {
        self.loaves = loaves
    }

    /// The default division: total bulk weight ÷ loaf count, each loaf equal.
    public static func equalLoaves(totalWeight: Double, count: Int, shape: FinalShape? = nil) -> ShapeLog {
        guard count > 0 else { return ShapeLog(loaves: []) }
        let each = totalWeight / Double(count)
        return ShapeLog(loaves: (0..<count).map { _ in LoafLog(weight: each, finalShape: shape) })
    }
}

public struct ProofLog: Codable, Hashable, Sendable, TimedLog {
    public var start: Date?
    public var end: Date?
    public var roomTempC: Double?
    @Lenient public var rise: ProofRise? = nil

    public init() {}
}

public struct ColdLog: Codable, Hashable, Sendable, TimedLog {
    @Lenient public var location: ColdLocation? = nil
    public var start: Date?
    public var end: Date?
    public var tempC: Double?

    public init() {}
}

/// The Bake step's log (called `BakeLog` in the spec; renamed to avoid confusion with the `Bake` model).
public struct OvenLog: Codable, Hashable, Sendable, TimedLog {
    public var preheatTempC: Double?
    @Lenient public var vessel: Vessel? = nil
    public var steam: String?
    public var coveredTempC: Double?
    public var coveredDuration: TimeInterval?
    public var uncoveredTempC: Double?
    public var uncoveredDuration: TimeInterval?
    public var tempChanges: [String]?
    public var start: Date?
    public var end: Date?

    public init() {}
}

public struct Evaluation: Codable, Hashable, Sendable {
    public static let scoreRange = 1...10

    // Out of the oven
    public var crustColour: Int?
    public var ovenSpring: Int?
    public var hasEar: Bool?
    public var internalTempC: Double?

    // Cooled and cut
    public var crumb: Int?
    public var crustTexture: Int?
    public var flavour: Int?
    public var coolingDuration: TimeInterval?
    /// The user's own qualities, scored 1–10.
    public var custom: [String: Int]?

    // Rating and notes
    public var overall: Int?
    public var worked: String?
    public var didnt: String?
    public var nextTime: String?

    public init() {}

    /// A bake can be completed once it has an overall score from 1 to 10.
    public var canComplete: Bool {
        overall.map(Self.scoreRange.contains) ?? false
    }

    /// True if every score given is within 1–10.
    public var scoresAreValid: Bool {
        let scores = [crustColour, ovenSpring, crumb, crustTexture, flavour, overall].compactMap { $0 }
            + (custom.map { Array($0.values) } ?? [])
        return scores.allSatisfy(Self.scoreRange.contains)
    }
}

/// An adjunct added during the bake that wasn't in the plan. Not part of the scaling.
public struct AdjunctAddition: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var grams: Double
    public var stage: AdjunctStage
    public var at: Date

    public init(id: UUID = UUID(), name: String, grams: Double, stage: AdjunctStage, at: Date = Date()) {
        self.id = id
        self.name = name
        self.grams = grams
        self.stage = stage
        self.at = at
    }
}

/// Every step's actuals for one bake, stored together.
public struct BakeLogs: Codable, Hashable, Sendable {
    public var mix: MixLog?
    public var bulk: BulkLog?
    public var shape: ShapeLog?
    public var proof: ProofLog?
    public var cold: ColdLog?
    public var oven: OvenLog?
    public var evaluation: Evaluation?
    public var additions: [AdjunctAddition]?

    public init() {}
}
