import SwiftUI
import SwiftData
import BakeCore
import BakeStore

/// Home: the bake in progress. Placeholder until the step screens are built.
struct ActiveBakeView: View {
    @Query(filter: Bake.isActive) private var activeBakes: [Bake]
    var showRecipes: () -> Void

    var body: some View {
        Group {
            if let bake = activeBakes.first {
                List {
                    Section("Recipe") {
                        Text(bake.version?.recipe?.name ?? "Untitled")
                        Text("Version \(bake.version?.number ?? 0)")
                    }
                    Section("Current step") {
                        Text(bake.currentStep.title)
                    }
                }
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
}
