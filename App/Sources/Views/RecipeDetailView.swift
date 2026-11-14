import SwiftUI
import SwiftData
import BakeMath
import BakeCore
import BakeStore

/// Everything about one version of a recipe: formula with sample weights, process, bakes and actions.
struct RecipeDetailView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("temperatureUnit") private var unit: TemperatureUnit = .default

    let recipe: Recipe

    @State private var selectedNumber: Int?
    @State private var sampleMass: Double?
    @State private var editing: RecipeVersion?
    @State private var errorMessage: String?

    private var version: RecipeVersion? {
        let versions = recipe.sortedVersions
        return versions.first { $0.number == selectedNumber } ?? versions.last
    }

    var body: some View {
        List {
            if let version {
                header(version)
                actions(version)
                formula(version)
                process(version)
                bakes(version)
            }
        }
        .keyboardDoneButton()
        .navigationTitle(recipe.name)
        .toolbar {
            if recipe.sortedVersions.count > 1 {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Version", selection: versionSelection) {
                        ForEach(recipe.sortedVersions) { version in
                            Text("Version \(version.number)").tag(version.number)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .sheet(item: $editing) { version in
            NavigationStack {
                VersionEditorView(recipe: recipe, version: version)
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var versionSelection: Binding<Int> {
        Binding(
            get: { version?.number ?? 1 },
            set: { selectedNumber = $0; sampleMass = nil }
        )
    }

    // MARK: Sections

    @ViewBuilder
    private func header(_ version: RecipeVersion) -> some View {
        Section {
            HStack {
                Text("Version \(version.number)")
                    .font(.title3.weight(.semibold))
                if version.isFrozen {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Locked: baked at least once")
                }
                Spacer()
                let count = version.completedBakes.count
                Text(count == 1 ? "Baked once" : count == 0 ? "Not baked yet" : "Baked \(count) times")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !version.changeNote.isEmpty {
                Text(version.changeNote)
                    .font(.subheadline)
            }
            if let parent = version.derivedFrom, parent.recipe?.id != recipe.id {
                Text("Made from \(parent.recipe?.name ?? "another recipe"), version \(parent.number)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !recipe.notes.isEmpty {
                Text(recipe.notes)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func actions(_ version: RecipeVersion) -> some View {
        Section {
            NavigationLink(value: BuildTarget(version: version)) {
                Label("Start a bake", systemImage: "play.fill")
            }
            if version.isFrozen {
                Button {
                    makeNewVersion(from: version)
                } label: {
                    Label("New version from this", systemImage: "plus.square.on.square")
                }
            } else {
                Button {
                    editing = version
                } label: {
                    Label("Edit version \(version.number)", systemImage: "pencil")
                }
            }
        } footer: {
            if version.isFrozen {
                Text("This version has been baked, so it's locked. Changes go into a new version.")
            }
        }
    }

    @ViewBuilder
    private func formula(_ version: RecipeVersion) -> some View {
        let defaultMass = version.completedBakes.last?.plan?.targetMass ?? 1000
        let mass = sampleMass ?? defaultMass
        Section {
            NumberField(
                title: "Sample dough weight",
                value: Binding(get: { sampleMass ?? defaultMass }, set: { sampleMass = $0 }),
                suffix: "g"
            )
            switch sampleTable(version.formula, mass: mass) {
            case .success(let sections):
                FormulaTableView(sections: sections)
            case .failure(let error):
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Formula")
        } footer: {
            Text("Percentages are of total flour, including the flour in the starter. Change the sample weight to see other sizes; it doesn't change the recipe.")
        }
    }

    @ViewBuilder
    private func process(_ version: RecipeVersion) -> some View {
        let sections = ProcessSummary.sections(version.process, unit: unit)
        if sections.isEmpty {
            Section("Process") {
                Text(version.isFrozen ? "No process details." : "No process details yet. Tap Edit to add them.")
                    .foregroundStyle(.secondary)
            }
        } else {
            ProcessSections(sections: sections)
        }
    }

    @ViewBuilder
    private func bakes(_ version: RecipeVersion) -> some View {
        let all = (version.bakes ?? []).sorted { $0.startedAt > $1.startedAt }
        Section("Bakes of this version") {
            if all.isEmpty {
                Text("None yet.").foregroundStyle(.secondary)
            }
            ForEach(all) { bake in
                HStack {
                    Text(bake.startedAt.formatted(date: .abbreviated, time: .omitted))
                    Spacer()
                    switch bake.status {
                    case .active:
                        Text("In progress").foregroundStyle(.tint)
                    case .abandoned:
                        Text("Abandoned").foregroundStyle(.secondary)
                    case .completed:
                        if let score = bake.logs.evaluation?.overall {
                            Text("\(score)/10").monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func sampleTable(_ formula: Formula, mass: Double) -> Result<[FormulaSection], SampleError> {
        guard mass > 0 else { return .failure(SampleError(message: "Enter a sample weight.")) }
        do {
            let weights = try BuildSolver.solve(formula, BuildInputs(totalMass: mass))
            return .success(FormulaTable.sections(formula, weights))
        } catch {
            return .failure(SampleError(message: describe(error)))
        }
    }

    private func makeNewVersion(from version: RecipeVersion) {
        do {
            let new = try BakeService(context: context).newVersion(from: version)
            selectedNumber = new.number
            editing = new
        } catch {
            errorMessage = describe(error)
        }
    }
}

private struct SampleError: Error {
    let message: String
}
