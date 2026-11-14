import SwiftUI
import SwiftData
import BakeMath
import BakeCore
import BakeStore

/// Edits a version that hasn't been baked yet: the recipe's name and notes, the formula and the
/// process plan. Nothing is saved until Save.
struct VersionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("temperatureUnit") private var unit: TemperatureUnit = .default
    @AppStorage("starterInGrams") private var starterInGrams = false

    let recipe: Recipe
    let version: RecipeVersion

    @State private var name: String
    @State private var notes: String
    @State private var changeNote: String
    @State private var formula: Formula
    @State private var process: ProcessPlan
    @State private var errorMessage: String?
    /// The dough weight that starter grams are measured against.
    @State private var referenceMass: Double?
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
        _referenceMass = State(initialValue: version.completedBakes.last?.plan?.targetMass ?? 1000)
        _autolyseOn = State(initialValue: version.process.autolyse != nil)
    }

    var body: some View {
        Form {
            recipeSection
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

    // MARK: Recipe and formula

    private var recipeSection: some View {
        Section("Recipe") {
            TextField("Name", text: $name)
            TextField("Notes", text: $notes, axis: .vertical)
            if version.number > 1 {
                TextField("What changed in this version", text: $changeNote, axis: .vertical)
            }
        }
    }

    private var formulaSection: some View {
        Section {
            NumberField(title: "Hydration", value: .percent($formula.hydration), suffix: "%")
            NumberField(title: "Salt", value: .percent($formula.saltPct), suffix: "%")
        } header: {
            Text("Formula")
        } footer: {
            Text("Percentages are of total flour, including the flour in the starter. Hydration counts the starter's water.")
        }
    }

    private var mass: Double { max(referenceMass ?? 0, 0) }

    /// Starter typed as grams in a dough of `referenceMass`; stored as a %.
    private var starterGrams: Binding<Double?> {
        Binding(
            get: { mass > 0 ? StarterAmount.grams(formula, doughMass: mass) : nil },
            set: { grams in
                if let grams, mass > 0 {
                    formula.starterPct = StarterAmount.percent(grams: grams, formula, doughMass: mass)
                }
            }
        )
    }

    private var starterSection: some View {
        Section {
            Picker("Enter starter as", selection: $starterInGrams) {
                Text("%").tag(false)
                Text("Grams").tag(true)
            }
            .pickerStyle(.segmented)

            if starterInGrams {
                NumberField(title: "Starter", value: starterGrams, suffix: "g")
                NumberField(title: "In a dough of", value: $referenceMass, suffix: "g")
                LabeledContent("Starter %", value: Format.percent(formula.starterPct))
            } else {
                NumberField(title: "Starter", value: .percent($formula.starterPct), suffix: "%")
            }
            NumberField(title: "Starter hydration", value: .percent($formula.starterHydration), suffix: "%")
            TextField("Starter flour (optional)", text: .optional($formula.starterFlourType))
        } header: {
            Text("Starter")
        } footer: {
            if mass > 0 {
                Text("In a \(Format.number(mass.rounded())) g dough: \(StarterAmount.description(grams: StarterAmount.grams(formula, doughMass: mass), starterHydration: formula.starterHydration)).")
            }
        }
    }

    private var blendTotal: Double {
        formula.flours.reduce(0) { $0 + $1.share }
    }

    private var floursSection: some View {
        Section {
            ForEach($formula.flours) { $flour in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Flour type (e.g. bread flour)", text: .optional($flour.type))
                    if formula.flours.count > 1 {
                        NumberField(title: "Share of the flour you add", value: .percent($flour.share), suffix: "%")
                    }
                }
                .padding(.vertical, 2)
            }
            .onDelete { offsets in
                formula.flours.remove(atOffsets: offsets)
                if formula.flours.count == 1 { formula.flours[0].share = 1 }
            }
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
            if formula.flours.count > 1 {
                let ok = abs(blendTotal - 1) <= 0.001
                Text("Blend adds up to \(Format.percent(blendTotal))\(ok ? "." : ". It needs to be 100%.")")
                    .foregroundStyle(ok ? Color.secondary : Color.red)
            } else {
                Text("Swipe left on a flour to remove it.")
            }
        }
    }

    private var adjunctsSection: some View {
        Section {
            ForEach($formula.adjuncts) { $adjunct in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("What it is (e.g. walnuts)", text: $adjunct.name)
                    NumberField(title: "Amount", value: .percent($adjunct.pct), suffix: "%")
                    Picker("Added in", selection: $adjunct.stage) {
                        ForEach(AdjunctStage.allCases, id: \.self) { stage in
                            Text(stage.label.prefix(1).uppercased() + stage.label.dropFirst()).tag(stage)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .onDelete { formula.adjuncts.remove(atOffsets: $0) }

            Button {
                formula.adjuncts.append(AdjunctComponent(name: "", pct: 0))
            } label: {
                Label("Add an adjunct", systemImage: "plus")
            }
        } header: {
            Text("Adjuncts")
        } footer: {
            Text("Seeds, nuts, cheese and other additions, as a % of total flour. They count toward the total dough weight.")
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
            ChoicePicker(title: "Mix method", selection: $process.mixMethod)
            NumberField(title: "Mix time", value: .minutes($process.mixDuration), suffix: "min")
            NumberField(title: "Folds", value: .whole($process.mixFolds))
        }
    }

    private var bulkSection: some View {
        Section("Bulk ferment") {
            OptionalPicker(title: "Strength", selection: $process.strengthMethod,
                           options: StrengthMethod.allCases, label: { $0.label })
            NumberField(title: "Sets", value: .whole($process.sets))
            NumberField(title: "Between sets", value: .minutes($process.setInterval), suffix: "min")
            OptionalPicker(title: "Target rise", selection: $process.targetRise,
                           options: Rise.allCases.filter { $0 != .notMeasured }, label: { $0.label })
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
            NumberField(title: "Final proof", value: .hours($process.proofDuration), suffix: "h")
            NumberField(title: "Proof temp", value: .temperature($process.proofTempC, unit: unit), suffix: unit.symbol)
            Toggle("Cold ferment", isOn: coldFerment)
            if process.coldFerment == true {
                NumberField(title: "Cold time", value: .hours($process.coldDuration), suffix: "h")
                NumberField(title: "Cold temp", value: .temperature($process.coldTempC, unit: unit), suffix: unit.symbol)
            }
        }
    }

    private var bakeSection: some View {
        Section("Bake") {
            NumberField(title: "Preheat", value: .temperature($process.preheatTempC, unit: unit), suffix: unit.symbol)
            ChoicePicker(title: "Vessel", selection: $process.vessel)
            TextField("Steam (e.g. lid on, ice cubes)", text: .optional($process.steam))
            NumberField(title: "Covered", value: .minutes($process.coveredDuration), suffix: "min")
            NumberField(title: "Covered temp", value: .temperature($process.coveredTempC, unit: unit), suffix: unit.symbol)
            NumberField(title: "Uncovered", value: .minutes($process.uncoveredDuration), suffix: "min")
            NumberField(title: "Uncovered temp", value: .temperature($process.uncoveredTempC, unit: unit), suffix: unit.symbol)
            OptionalPicker(title: "Scored", selection: $process.scored,
                           options: [true, false], label: { $0 ? "Yes" : "No" })
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
            recipe.name = trimmedName
            recipe.notes = notes
            version.changeNote = changeNote
            try BakeService(context: context).update(version, formula: cleaned, process: process)
            dismiss()
        } catch {
            errorMessage = describe(error)
        }
    }
}
