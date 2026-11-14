import SwiftUI
import BakeMath
import BakeCore
import BakeStore

/// Pushes the Build screen for a version.
struct BuildTarget: Hashable {
    let version: RecipeVersion
}

private struct ShowActiveBakeKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Switches to the bake in progress (used after a bake is started).
    var showActiveBake: () -> Void {
        get { self[ShowActiveBakeKey.self] }
        set { self[ShowActiveBakeKey.self] = newValue }
    }
}

/// A sentence for any error the screens can hit.
func describe(_ error: Error) -> String {
    switch error {
    case let error as BuildError:
        return error.message
    case BakePlanError.loafCountMustBePositive:
        return "Set at least one loaf."
    case let error as BakeServiceError:
        switch error {
        case .anotherBakeActive: return "Another bake is in progress. Finish or abandon it first."
        case .bakeNotActive: return "This bake has already finished."
        case .evaluationIncomplete: return "Give the bake an overall score first."
        case .versionChoiceRequired: return "Choose where to save this bake's changes."
        case .versionIsFrozen: return "This version has been baked, so it can't change. Make a new version instead."
        case .missingPlan: return "This bake's plan couldn't be read."
        }
    default:
        return error.localizedDescription
    }
}
