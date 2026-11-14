import SwiftUI
import SwiftData
import BakeMath
import BakeCore
import BakeStore

/// Home: the bake in progress. The step screens and timers come in the next chunk;
/// for now it shows the plan's weights and lets you abandon the bake.
struct ActiveBakeView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: Bake.isActive) private var activeBakes: [Bake]
    var showRecipes: () -> Void

    @State private var confirmingAbandon = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let bake = activeBakes.first {
                content(bake)
            } else {
                ContentUnavailableView {
                    Label("No bake in progress", systemImage: "timer")
                } description: {
                    Text("Pick a recipe to start a bake.")
                } actions: {
                    Button("Go to Recipes", action: showRecipes)
                }
            }
        }
        .navigationTitle("Bake")
    }

    private func content(_ bake: Bake) -> some View {
        List {
            Section {
                LabeledContent("Recipe", value: bake.version?.recipe?.name ?? "Untitled")
                LabeledContent("Version", value: "\(bake.version?.number ?? 0)")
                LabeledContent("Started", value: bake.startedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Current step", value: bake.currentStep.title)
            }

            if let plan = bake.plan {
                Section {
                    FormulaTableView(sections: FormulaTable.sections(plan.formula, plan.weights))
                    LabeledContent("Loaves", value: "\(plan.loafCount)")
                } header: {
                    Text("Weights")
                }
            }

            Section {
                Button("Abandon this bake", role: .destructive) {
                    confirmingAbandon = true
                }
            } footer: {
                Text("An abandoned bake is kept with whatever was logged, and doesn't lock its version.")
            }
        }
        .confirmationDialog("Abandon this bake?", isPresented: $confirmingAbandon, titleVisibility: .visible) {
            Button("Abandon", role: .destructive) { abandon(bake) }
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

    private func abandon(_ bake: Bake) {
        do {
            try BakeService(context: context).abandon(bake)
        } catch {
            errorMessage = describe(error)
        }
    }
}
