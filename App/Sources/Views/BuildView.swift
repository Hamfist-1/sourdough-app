import SwiftUI
import SwiftData
import BakeMath
import BakeCore
import BakeStore

/// Build: scale a version to this bake's size from whatever you know, then start the bake. SPEC §3.
struct BuildView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.showActiveBake) private var showActiveBake

    let version: RecipeVersion

    @State private var totalMass: Double?
    @State private var addedFlour: Double?
    @State private var addedWater: Double?
    @State private var hydrationPercent: Double?
    @State private var loafCount = 1
    @State private var errorMessage: String?

    private var inputs: BuildInputs {
        BuildInputs(
            totalMass: totalMass,
            addedFlour: addedFlour,
            addedWater: addedWater,
            hydration: hydrationPercent.map { $0 / 100 }
        )
    }

    private var hasWeight: Bool {
        totalMass != nil || addedFlour != nil || addedWater != nil
    }

    private var outcome: Result<BakePlan, BuildFailure>? {
        guard hasWeight else { return nil }
        do {
            return .success(try BakePlan.build(
                formula: version.formula,
                process: version.process,
                inputs: inputs,
                loafCount: loafCount
            ))
        } catch {
            return .failure(BuildFailure(message: describe(error)))
        }
    }

    var body: some View {
        let recipeHydration = Format.percent(version.formula.hydration)
        Form {
            Section {
                NumberField(title: "Total dough", value: $totalMass, suffix: "g")
                NumberField(title: "Flour", value: $addedFlour, suffix: "g")
                NumberField(title: "Water", value: $addedWater, suffix: "g")
                NumberField(
                    title: "Hydration",
                    value: $hydrationPercent,
                    suffix: "%",
                    prompt: String(recipeHydration.dropLast())
                )
            } header: {
                Text("What you know")
            } footer: {
                Text("Enter one weight to use the recipe's \(recipeHydration) hydration, or any two numbers. Flour and water are what you put on the scale, not counting the starter.")
            }

            Section {
                Stepper("Loaves: \(loafCount)", value: $loafCount, in: 1...12)
            }

            switch outcome {
            case .none:
                Section {
                    Text("Enter a weight to see the recipe scaled.")
                        .foregroundStyle(.secondary)
                }
            case .some(.failure(let failure)):
                Section {
                    Label(failure.message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            case .some(.success(let plan)):
                result(plan)
            }
        }
        .navigationTitle("Build")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Can't start the bake", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func result(_ plan: BakePlan) -> some View {
        if plan.formula.hydration != version.formula.hydration {
            Section {
                Label(
                    "Hydration \(Format.percent(version.formula.hydration)) → \(Format.percent(plan.formula.hydration)). When this bake is done it will save as a new version.",
                    systemImage: "arrow.triangle.branch"
                )
            }
        }
        if plan.weights.warnings.contains(where: { if case .hydrationOutsideTypicalRange = $0 { true } else { false } }) {
            Section {
                Label("That hydration is unusual. Double-check it.", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
            }
        }

        Section {
            FormulaTableView(sections: FormulaTable.sections(plan.formula, plan.weights))
            LabeledContent(
                loafCount == 1 ? "One loaf" : "Each of \(loafCount) loaves",
                value: "\(Format.number(WeightDisplay.rounded(plan.weights.massPerLoaf(loafCount)))) g"
            )
        } header: {
            Text("\(version.recipe?.name ?? "Recipe"), version \(version.number)")
        }

        Section {
            Button {
                start(plan)
            } label: {
                Label("Start the bake", systemImage: "play.fill")
                    .font(.headline)
            }
        }
    }

    private func start(_ plan: BakePlan) {
        do {
            try BakeService(context: context).startBake(from: version, plan: plan)
            showActiveBake()
        } catch {
            errorMessage = describe(error)
        }
    }
}

private struct BuildFailure: Error {
    let message: String
}
