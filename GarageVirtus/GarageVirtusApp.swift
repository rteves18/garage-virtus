import GarageVirtusKit
import SwiftData
import SwiftUI

@main
struct GarageVirtusApp: App {
    @State private var model = CatalogueViewModel()
    @State private var garage: GarageStore

    private let container: ModelContainer

    init() {
        // Ryan's garage records live in the app's container (Application Support), apart from the bundled catalogue.
        let container: ModelContainer
        do {
            container = try GarageStore.makeContainer()
        } catch {
            assertionFailure("Couldn't open the garage store: \(error)")
            container = try! GarageStore.makeContainer(isStoredInMemoryOnly: true)
        }
        self.container = container
        _garage = State(initialValue: GarageStore(container: container))
    }

    var body: some Scene {
        WindowGroup("Garage Virtus") {
            ContentView()
                .environment(model)
                .environment(garage)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .modelContainer(container)

        Settings {
            AssistantSettingsView()
        }
    }
}
