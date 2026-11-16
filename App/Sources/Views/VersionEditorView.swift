import SwiftUI
import SwiftData
import BakeMath
import BakeCore
import BakeStore

/// Edits a version that hasn't been baked yet: the recipe's name and notes, its batch (total dough
/// weight and loaves), the formula and the process plan. Nothing is saved until Save.
///
/// The formula can be entered as percentages plus a total, or as weights (what goes on the scale),
/// with the total as their sum. Both edit the same recipe: `formula` and `batchMass`.
struct VersionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("temperatureUnit") private var unit: TemperatureUnit = .default
    @AppStorage("enterRecipeAsWeights") private var asWeights = false

    let recipe: Recipe
    let version: RecipeVersion

    @State private var name: String
    @State private var notes: String
    @State private var changeNote: String
    @State private var formula: Formula
    @State private var process: ProcessPlan
    @State private var batchMass: Double
    @State private var loafCount: Int
    @State private var errorMessage: String?
    /// Autolyse yes/no. The duration is only asked for when it's on.
    @State private var autolyseOn: Bool

    init(recipe: Recipe, version: RecipeVersion) {
        self.recipe = recipe
        self.version = version
        _name = State(initialValue: recipe.name)
        _notes = State(initialValue: recipe.notes)
        _changeNote = State(initialValue: version.changeNote)
        _formula = State(initialValue: version.formula)
        _process = State(initialValue: version.process)
        _batchMass = State(initialValue: version.batchMass)
        _loafCount = State(initialValue: max(version.loafCount, 1))
        _autolyseOn = State(initialValue: version.process.autolyse != nil)
    }

    var body: some View {
        Form {
            recipeSection
            batchSection
            formulaSection
            starterSection
            floursSection
            adjunctsSection
            mixSection
            bulkSection
            shapeSection
            proofSection
            bakeSection
        }
        .keyboardDoneButton()
        .navigationTitle("Version \(version.number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
        .alert("Can't save yet", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Weights mode

    /// The recipe as weights at the current batch size.
    private var weights: RecipeWeights {
        RecipeWeights(formula: formula, totalMass: batchMass)
    }

    /// Applies edited weights: the percentages and the total both follow from them.
    private func apply(_ edited: RecipeWeights) {
        guard let newFormula = edited.formula() else { return }
        formula = newFormula
        batchMass = edited.totalMass
    }

    private func weight(_ keyPath: WritableKeyPath<RecipeWeights, Double>) -> Binding<Double?> {
        Binding(
            get: { weights[keyPath: keyPath] },
            set: { newValue in
                guard let newValue else { return }
                var edited = weights
                edited[keyPath: keyPath] = newValue
                apply(edited)
            }
        )
    }

    private func flourWeight(_ id: UUID) -> Binding<Double?> {
        Binding(
            get: { weights.flours.first { $0.id == id }?.grams },
            set: { newValue in
                guard let newValue else { return }
                var edited = weights
                guard let index = edited.flours.firstIndex(where: { $0.id == id }) else { return }
                edited.flours[index].grams = newValue
                apply(edited)
            }
        )
    }

    private func adjunctWeight(_ id: UUID) -> Binding<Double?> {
        Binding(
            get: { weights.adjuncts.first { $0.id == id }?.grams },
            set: { newValue in
                guard let newValue else { return }
                var edited = weights
                guard let index = edited.adjuncts.firstIndex(where: { $0.id == id }) else { return }
                edited.adjuncts[index].grams = newValue
                apply(edited)
            }
        )
    }

    // MARK: Recipe, batch and formula

    private var recipeSection: some View {
        Section("Recipe") {
            TextField("Name", text: $name)
            TextField("Notes", text: $notes, axis: .vertical)
            if version.number > 1 {
                TextField("What changed in this version", text: $changeNote, axis: .vertical)
            }
        }
    }

    private var batchSection: some View {
        Section {
            Picker("Enter as", selection: $asWeights) {
                Text("Percentages").tag(false)
                Text("Weights").tag(true)
            }
            .pickerStyle(.segmented)

            if asWeights {
                LabeledContent("Total dough", value: "\(Format.number(WeightDisplay.rounded(batchMass))) g")
            } else {
                NumberField(
                    title: "Total dough weight",
                    value: Binding(get: { batchMass }, set: { if let v = $0, v > 0 { batchMass = v } }),
                    suffix: "g"
                )
            }
            Stepper("Loaves: \(loafCount)", value: $loafCount, in: 1...12)
        } header: {
            Text("Batch")
        } footer: {
            Text(asWeights
                 ? "Enter what goes on the scale. The total is their sum, and the percentages are worked out for you."
                 : "Enter percentages and a total; the grams are worked out for you. Changing the total or loaves only scales the recipe.")
        }
    }

    private var formulaSection: some View {
        Section {
            if asWeights {
                NumberField(title: "Water", value: weight(\.water), suffix: "g")
                LabeledContent("Hydration", value: Format.percent(formula.hydration))
                NumberField(title: "Salt", value: weight(\.salt), suffix: "g")
                LabeledContent("Salt %", value: Format.percent(formula.saltPct))
            } else {
                NumberField(title: "Hydration", value: .percent($formula.hydration), suffix: "%")
                NumberField(title: "Salt", value: .percent($formula.saltPct), suffix: "%")
            }
        } header: {
            Text("Water and salt")
        } footer: {
            Text(asWeights
                 ? "Water is what you add. Hydration counts the starter's water too."
                 : "Percentages are of total flour, including the flour in the starter. Hydration counts the starter's water.")
        }
    }

    private var starterSection: some View {
        Section {
            if asWeights {
                NumberField(title: "Starter", value: weight(\.starter), suffix: "g")
                LabeledContent("Starter %", value: Format.percent(formula.starterPct))
            } else {
                NumberField(title: "Starter", value: .percent($formula.starterPct), suffix: "%")
            }
            NumberField(title: "Starter hydration", value: .percent($formula.starterHydration), suffix: "%")
            TextField("Starter flour (optional)", text: .optional($formula.starterFlourType))
        } header: {
            Text("Starter")
        } footer: {
            let grams = weights.starter
            if grams > 0 {
                Text("\(StarterAmount.description(grams: grams, starterHydration: formula.starterHydration)).")
            }
        }
    }

    private var blendTotal: Double {
        formula.flours.reduce(0) { $0 + $1.share }
    }

    private func removeFlours(at offsets: IndexSet) {
        if asWeights {
            var edited = weights
            edited.flours.remove(atOffsets: offsets)
            apply(edited)
        } else {
            formula.flours.remove(atOffsets: offsets)
            if formula.flours.count == 1 { formula.flours[0].share = 1 }
        }
    }

    private var floursSection: some View {
        Section {
            ForEach($formula.flours) { $flour in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Flour type (e.g. bread flour)", text: .optional($flour.type))
                    if asWeights {
                        NumberField(title: "Weight", value: flourWeight(flour.id), suffix: "g")
                    } else if formula.flours.count > 1 {
                        NumberField(title: "Share of the flour you add", value: .percent($flour.share), suffix: "%")
                    }
                }
                .padding(.vertical, 2)
            }
            .onDelete(perform: removeFlours)
            .deleteDisabled(formula.flours.count <= 1)

            if formula.flours.count < Formula.flourCountLimit.upperBound {
                Button {
                    formula.flours.append(FlourComponent(share: 0))
                } label: {
                    Label("Add a flour", systemImage: "plus")
                }
            }
        } header: {
            Text("Flours (1 to 3)")
        } footer: {
            if !asWeights && formula.flours.count > 1 {
                let ok = abs(blendTotal - 1) <= 0.001
                Text("Blend adds up to \(Format.percent(blendTotal))\(ok ? "." : ". It needs to be 100%.")")
                    .foregroundStyle(ok ? Color.secondary : Color.red)
            } else {
                Text("Swipe left on a flour to remove it.")
            }
        }
    }

    /// In weights mode, removing an adjunct lowers the total; the other weights stay put.
    private func removeAdjuncts(at offsets: IndexSet) {
        if asWeights {
            var edited = weights
            edited.adjuncts.remove(atOffsets: offsets)
            apply(edited)
        } else {
            formula.adjuncts.remove(atOffsets: offsets)
        }
    }

    private var adjunctsSection: some View {
        Section {
            ForEach($formula.adjuncts) { $adjunct in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("What it is (e.g. walnuts)", text: $adjunct.name)
                    if asWeights {
                        NumberField(title: "Weight", value: adjunctWeight(adjunct.id), suffix: "g")
                    } else {
                        NumberField(title: "Amount", value: .percent($adjunct.pct), suffix: "%")
                    }
                    Picker("Added in", selection: $adjunct.stage) {
                        ForEach(AdjunctStage.allCases, id: \.self) { stage in
                            Text(stage.label.prefix(1).uppercased() + stage.label.dropFirst()).tag(stage)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .onDelete(perform: removeAdjuncts)

            Button {
                formula.adjuncts.append(AdjunctComponent(name: "", pct: 0))
            } label: {
                Label("Add an adjunct", systemImage: "plus")
            }
        } header: {
            Text("Adjuncts")
        } footer: {
            Text("Seeds, nuts, cheese and other additions. Their percentages are of total flour, and they count toward the total dough weight.")
        }
    }

    // MARK: Process

    private var mixSection: some View {
        Section("Mix") {
            ChoicePicker(title: "First in", selection: $process.firstIn)
            Toggle("Autolyse", isOn: $autolyseOn)
            if autolyseOn {
                NumberField(title: "Autolyse time", value: .minutes($process.autolyse), suffix: "min")
                OptionalPicker(title: "Starter added", selection: $process.starterTiming,
                               options: StarterTiming.allCases, label: { $0.label })
            }
            OptionalPicker(title: "Mix method", selection: $process.mixMethod,
                           options: MixMethod.allCases, label: { $0.label.prefix(1).uppercased() + $0.label.dropFirst() })
            NumberField(title: "Mix time", value: .minutes($process.mixDuration), suffix: "min")
        }
    }

    private var bulkSection: some View {
        Section("Bulk ferment") {
            OptionalPicker(title: "Folds", selection: $process.strengthMethod,
                           options: StrengthMethod.allCases, label: { $0.label })
            NumberField(title: "Sets", value: .whole($process.sets))
            NumberField(title: "Between sets", value: .minutes($process.setInterval), suffix: "min")
            OptionalPicker(title: "Target rise", selection: $process.targetRise,
                           options: Rise.targets, label: { $0.label })
            NumberField(title: "Expected time", value: .hours($process.bulkDuration), suffix: "h")
        }
    }

    private var shapeSection: some View {
        Section("Shape") {
            ChoicePicker(title: "Final shape", selection: $process.finalShape)
        }
    }

    private var coldFerment: Binding<Bool> {
        Binding(get: { process.coldFerment ?? false }, set: { process.coldFerment = $0 })
    }

    private var proofSection: some View {
        Section("Proof") {
            OptionalPicker(title: "Final proof rise", selection: $process.proofRise,
                           options: Rise.targets, label: { $0.label })
            NumberField(title: "Proof time", value: .hours($process.proofDuration), suffix: "h")
            NumberField(title: "Proof temp", value: .temperature($process.proofTempC, unit: unit), suffix: unit.symbol)
            Toggle("Cold ferment", isOn: coldFerment)
            if process.coldFerment == true {
                NumberField(title: "Cold time", value: .hours($process.coldDuration), suffix: "h")
                NumberField(title: "Cold temp", value: .temperature($process.coldTempC, unit: unit), suffix: unit.symbol)
            }
        }
    }

    private var scored: Binding<Bool> {
        Binding(get: { process.scored ?? false }, set: { process.scored = $0 })
    }

    private var bakeSection: some View {
        Section("Bake") {
            Toggle("Scored", isOn: scored)
            NumberField(title: "Preheat", value: .temperature($process.preheatTempC, unit: unit), suffix: unit.symbol)
            ChoicePicker(title: "Vessel", selection: $process.vessel)
            TextField("Steam (e.g. lid on, ice cubes)", text: .optional($process.steam))
            NumberField(title: "Covered", value: .minutes($process.coveredDuration), suffix: "min")
            NumberField(title: "Covered temp", value: .temperature($process.coveredTempC, unit: unit), suffix: unit.symbol)
            NumberField(title: "Uncovered", value: .minutes($process.uncoveredDuration), suffix: "min")
            NumberField(title: "Uncovered temp", value: .temperature($process.uncoveredTempC, unit: unit), suffix: unit.symbol)
        }
    }

    // MARK: Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Give the recipe a name."
            return
        }

        var cleaned = formula
        if cleaned.flours.count == 1 { cleaned.flours[0].share = 1 }
        cleaned.adjuncts = cleaned.adjuncts.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty || $0.pct > 0 }
        if cleaned.adjuncts.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
            errorMessage = "Give each adjunct a name."
            return
        }
        if autolyseOn {
            guard let minutes = process.autolyse, minutes > 0 else {
                errorMessage = "Enter how long the autolyse is, or switch it off."
                return
            }
        } else {
            process.autolyse = nil
            process.starterTiming = nil
        }

        do {
            try BuildSolver.validate(cleaned)
            guard batchMass > 0 else {
                errorMessage = "Enter a total dough weight."
                return
            }
            recipe.name = trimmedName
            recipe.notes = notes
            version.changeNote = changeNote
            try BakeService(context: context).update(version, formula: cleaned, process: process,
                                                     batchMass: batchMass, loafCount: loafCount)
            dismiss()
        } catch {
            errorMessage = describe(error)
        }
    }
}
