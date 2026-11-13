import SwiftUI
import SwiftData
import BakeStore

@main
struct SourdoughApp: App {
    let container: ModelContainer

    init() {
        do {
            // iCloud sync is off until there's a paid developer account (docs/DECISIONS.md).
            container = try BakeStoreContainer.make()
        } catch {
            fatalError("Could not open the bake store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
