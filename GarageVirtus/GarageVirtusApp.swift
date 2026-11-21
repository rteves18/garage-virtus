import SwiftUI
import GarageVirtusKit

@main
struct GarageVirtusApp: App {
    @State private var store = CatalogueStore()

    var body: some Scene {
        WindowGroup("Garage Virtus") {
            ContentView()
                .environment(store)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Catalogue Folder…") { store.chooseCatalogueFolder() }
                    .keyboardShortcut("o")
                Button("Reload Catalogue") { store.reload() }
                    .keyboardShortcut("r")
            }
        }
    }
}
