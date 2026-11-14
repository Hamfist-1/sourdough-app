import Foundation
import BakeMath

// MARK: - Building a plan

public enum BakePlanError: Error, Hashable, Sendable {
    case loafCountMustBePositive
}

public extension BakePlan {
    /// Solves the Build step and snapshots the plan. If the inputs imply a different hydration
    /// than the version's, the plan's formula carries the new hydration, which makes it a variation.
    static func build(
        formula: Formula,
        process: ProcessPlan,
        inputs: BuildInputs,
        loafCount: Int
    ) throws -> BakePlan {
        guard loafCount >= 1 else { throw BakePlanError.loafCountMustBePositive }
        let weights = try BuildSolver.solve(formula, inputs)
        var planned = formula
        if weights.hydrationDiffersFromFormula { planned.hydration = weights.hydration }
        return BakePlan(formula: planned, process: process, targetMass: inputs.totalMass,
                        loafCount: loafCount, weights: weights)
    }
}

// MARK: - Versions (SPEC §5)

/// What to do with a bake that varied from its version, chosen when it completes. SPEC §5.3.
public enum CompletionChoice: Hashable, Sendable {
    /// Version n+1 of the same recipe (the default).
    case newVersion
    /// Version 1 of a new recipe with this name.
    case newRecipe(name: String)
}

public enum VersionRules {
    /// A version freezes once any of its bakes is completed. Abandoned bakes don't count.
    public static func isFrozen(_ statuses: some Sequence<BakeStatus>) -> Bool {
        statuses.contains(.completed)
    }

    /// True if the bake's plan differs from the version it started from: a deliberate change,
    /// not an actual. Actuals that differ from the plan never count. SPEC §5.2.
    public static func variesFromVersion(formula: Formula, process: ProcessPlan, plan: BakePlan) -> Bool {
        !PlanDiff.changes(from: (formula, process), to: (plan.formula, plan.process)).isEmpty
    }
}

// MARK: - Describing changes

/// A value in a change note, kept typed so temperatures follow the user's unit setting.
public enum PlanValue: Hashable, Sendable {
    case none
    case percent(Double)
    case duration(TimeInterval)
    case temperatureC(Double)
    case number(Double)
    case text(String)

    public func formatted(_ unit: TemperatureUnit) -> String {
        switch self {
        case .none: "none"
        case .percent(let x): Format.percent(x)
        case .duration(let t): Format.duration(t)
        case .temperatureC(let c): unit.format(celsius: c)
        case .number(let n): Format.number(n)
        case .text(let s): s
        }
    }
}

public struct PlanChange: Hashable, Sendable {
    public let field: String
    public let from: PlanValue
    public let to: PlanValue

    /// "Hydration 72% → 75%"
    public func description(_ unit: TemperatureUnit) -> String {
        "\(field) \(from.formatted(unit)) → \(to.formatted(unit))"
    }
}

/// Lists what changed between a version and a bake's plan, for `variesFromVersion` and to
/// pre-fill the new version's change note. SPEC §5.3.
public enum PlanDiff {
    public static func changes(
        from old: (formula: Formula, process: ProcessPlan),
        to new: (formula: Formula, process: ProcessPlan)
    ) -> [PlanChange] {
        formulaChanges(old.formula, new.formula) + processChanges(old.process, new.process)
    }

    /// One line per change, joined with "; ".
    public static func changeNote(_ changes: [PlanChange], unit: TemperatureUnit) -> String {
        changes.map { $0.description(unit) }.joined(separator: "; ")
    }

    static func formulaChanges(_ a: Formula, _ b: Formula) -> [PlanChange] {
        var result: [PlanChange] = []
        func percent(_ field: String, _ x: Double, _ y: Double) {
            if abs(x - y) > 0.00005 { result.append(PlanChange(field: field, from: .percent(x), to: .percent(y))) }
        }
        percent("Hydration", a.hydration, b.hydration)
        percent("Salt", a.saltPct, b.saltPct)
        percent("Starter", a.starterPct, b.starterPct)
        percent("Starter hydration", a.starterHydration, b.starterHydration)

        let flours = (describe(a.flours), describe(b.flours))
        if flours.0 != flours.1 { result.append(PlanChange(field: "Flour", from: .text(flours.0), to: .text(flours.1))) }
        let adjuncts = (describe(a.adjuncts), describe(b.adjuncts))
        if adjuncts.0 != adjuncts.1 {
            result.append(PlanChange(field: "Adjuncts", from: adjuncts.0.isEmpty ? .none : .text(adjuncts.0),
                                     to: adjuncts.1.isEmpty ? .none : .text(adjuncts.1)))
        }
        if a.starterFlourType != b.starterFlourType {
            result.append(PlanChange(field: "Starter flour", from: a.starterFlourType.map(PlanValue.text) ?? .none,
                                     to: b.starterFlourType.map(PlanValue.text) ?? .none))
        }
        return result
    }

    static func describe(_ flours: [FlourComponent]) -> String {
        flours.map { "\($0.type ?? "flour") \(Format.percent($0.share))" }.joined(separator: ", ")
    }

    static func describe(_ adjuncts: [AdjunctComponent]) -> String {
        adjuncts.map { "\($0.name) \(Format.percent($0.pct)) (\($0.stage.rawValue))" }.joined(separator: ", ")
    }

    /// Compares every field of the process plan by reflection, so new fields are covered automatically.
    static func processChanges(_ a: ProcessPlan, _ b: ProcessPlan) -> [PlanChange] {
        let left = Mirror(reflecting: a).children
        let right = Array(Mirror(reflecting: b).children)
        var result: [PlanChange] = []
        for (index, child) in left.enumerated() {
            guard let label = child.label else { continue }
            let x = value(label, child.value)
            let y = value(label, right[index].value)
            if x != y { result.append(PlanChange(field: humanize(label), from: x, to: y)) }
        }
        return result
    }

    static func value(_ label: String, _ any: Any) -> PlanValue {
        guard let unwrapped = unwrap(any) else { return .none }
        switch unwrapped {
        case let d as Double where label.hasSuffix("TempC"): return .temperatureC(d)
        case let d as Double where isDuration(label): return .duration(d)
        case let d as Double: return .number(d)
        case let i as Int: return .number(Double(i))
        case let b as Bool: return .text(b ? "yes" : "no")
        case let l as any PlanLabeled: return .text(l.label)
        case let s as String: return .text(s)
        default: return .text(String(describing: unwrapped))
        }
    }

    static func isDuration(_ label: String) -> Bool {
        label.hasSuffix("Duration") || label == "autolyse" || label == "setInterval"
    }

    static func unwrap(_ any: Any) -> Any? {
        let mirror = Mirror(reflecting: any)
        guard mirror.displayStyle == .optional else { return any }
        return mirror.children.first.map(\.value)
    }

    /// Field names that read better under a baker's term.
    static let fieldNames = ["strengthMethod": "Folds", "bulkDuration": "Bulk time"]

    /// "proofTempC" → "Proof temp", "setInterval" → "Set interval".
    static func humanize(_ label: String) -> String {
        if let name = fieldNames[label] { return name }
        var name = label
        if name.hasSuffix("TempC") { name.removeLast() }
        var words = ""
        for character in name {
            if character.isUppercase { words.append(" ") }
            words.append(character.lowercased())
        }
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
