import GarageVirtusKit
import SwiftData
import SwiftUI

@main
struct GarageVirtusApp: App {
    @State private var model: CatalogueViewModel
    @State private var garage: GarageStore

    private let container: ModelContainer

    init() {
        // Ryan's garage records live in the app's container (Application Support), apart from the bundled catalogue.
        let container: ModelContainer
        var warning: String?
        do {
            container = try GarageStore.makeContainer()
        } catch {
            // Keep the app usable, but say plainly that nothing will be saved.
            warning = "Couldn't open your garage data (\(error.localizedDescription)). Changes made now won't be saved."
            container = try! GarageStore.makeContainer(isStoredInMemoryOnly: true)
        }
        self.container = container
        let garage = GarageStore(container: container)
        _ = garage.defaultCar()
        if let saved = UserDefaults.standard.string(forKey: "currentCarID") {
            garage.currentCar = garage.cars().first { $0.id.uuidString == saved }
        }
        _garage = State(initialValue: garage)
        let model = CatalogueViewModel()
        model.garageStoreWarning = warning
        _model = State(initialValue: model)
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
            if FeatureFlags.isAskAIEnabled {
                AssistantSettingsView()
            }
        }
    }
}
