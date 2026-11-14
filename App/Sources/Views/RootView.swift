import SwiftUI
import SwiftData
import BakeStore

enum AppSection: Hashable {
    case bake, recipes, settings
}

/// iPhone: a tab bar. iPad: a sidebar. SPEC §6.
/// Opens on the bake in progress; with none, on Recipes (SPEC §5.1).
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(filter: Bake.isActive) private var activeBakes: [Bake]
    @State private var section: AppSection?
    @State private var recipePath = NavigationPath()

    var body: some View {
        Group {
            if sizeClass == .compact {
                tabs
            } else {
                sidebar
            }
        }
        .environment(\.showActiveBake) {
            recipePath = NavigationPath()
            section = .bake
        }
        .onAppear {
            if section == nil {
                section = activeBakes.isEmpty ? .recipes : .bake
            }
        }
    }

    private var tabSelection: Binding<AppSection> {
        Binding(get: { section ?? .recipes }, set: { section = $0 })
    }

    private var tabs: some View {
        TabView(selection: tabSelection) {
            NavigationStack { ActiveBakeView(showRecipes: { section = .recipes }) }
                .tabItem { Label("Bake", systemImage: "timer") }
                .tag(AppSection.bake)
            NavigationStack(path: $recipePath) { RecipeListView() }
                .tabItem { Label("Recipes", systemImage: "book") }
                .tag(AppSection.recipes)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppSection.settings)
        }
    }

    private var sidebar: some View {
        NavigationSplitView {
            List(selection: $section) {
                Label("Bake in progress", systemImage: "timer").tag(AppSection.bake)
                Label("Recipes", systemImage: "book").tag(AppSection.recipes)
                Label("Settings", systemImage: "gearshape").tag(AppSection.settings)
            }
            .navigationTitle("Sourdough")
        } detail: {
            switch section ?? .recipes {
            case .bake:
                NavigationStack { ActiveBakeView(showRecipes: { section = .recipes }) }
            case .recipes:
                NavigationStack(path: $recipePath) { RecipeListView() }
            case .settings:
                NavigationStack { SettingsView() }
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(BakeStoreContainer.preview())
}
