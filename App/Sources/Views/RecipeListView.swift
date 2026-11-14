import SwiftUI
import SwiftData
import BakeMath
import BakeCore
import BakeStore

struct RecipeListView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Recipe> { !$0.isArchived }, sort: \Recipe.name)
    private var recipes: [Recipe]

    @State private var showingNewRecipe = false
    @State private var newName = ""
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(recipes) { recipe in
                NavigationLink(value: recipe) {
                    RecipeRow(recipe: recipe)
                }
            }
        }
        .overlay {
            if recipes.isEmpty {
                ContentUnavailableView(
                    "No recipes yet",
                    systemImage: "book",
                    description: Text("Tap + to add your first recipe.")
                )
            }
        }
        .navigationTitle("Recipes")
        .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
        .navigationDestination(for: BuildTarget.self) { BuildView(version: $0.version) }
        .toolbar {
            Button {
                newName = ""
                showingNewRecipe = true
            } label: {
                Label("New recipe", systemImage: "plus")
            }
        }
        .alert("New recipe", isPresented: $showingNewRecipe) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create", action: createRecipe)
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

    private func createRecipe() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            try BakeService(context: context).createRecipe(name: name, formula: .newRecipeDefault())
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(recipe.name).font(.headline)
            if let version = recipe.latestVersion {
                Text("v\(version.number) · \(Format.percent(version.formula.hydration)) hydration")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack { RecipeListView() }
        .modelContainer(BakeStoreContainer.preview())
}
