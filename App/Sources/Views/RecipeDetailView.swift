import SwiftUI
import SwiftData
import BakeMath
import BakeCore
import BakeStore

/// A recipe's versions. Placeholder until the version editor, Build and Compare are built.
struct RecipeDetailView: View {
    let recipe: Recipe

    var body: some View {
        List {
            if !recipe.notes.isEmpty {
                Section { Text(recipe.notes) }
            }
            Section("Versions") {
                ForEach(recipe.sortedVersions.reversed()) { version in
                    VersionRow(version: version)
                }
            }
        }
        .navigationTitle(recipe.name)
    }
}

private struct VersionRow: View {
    let version: RecipeVersion

    var body: some View {
        let formula = version.formula
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Version \(version.number)").font(.headline)
                if version.isFrozen {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Locked: baked at least once")
                }
                Spacer()
                Text("\(version.completedBakes.count) bakes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Hydration \(Format.percent(formula.hydration)) · Salt \(Format.percent(formula.saltPct)) · Starter \(Format.percent(formula.starterPct)) at \(Format.percent(formula.starterHydration))")
                .font(.subheadline)
            if !version.changeNote.isEmpty {
                Text(version.changeNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
