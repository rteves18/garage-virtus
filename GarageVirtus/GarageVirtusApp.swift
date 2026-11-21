import SwiftUI

@main
struct GarageVirtusApp: App {
    @State private var model = CatalogueViewModel()

    var body: some Scene {
        WindowGroup("Garage Virtus") {
            ContentView()
                .environment(model)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Catalogue Folder…") { model.chooseCatalogueFolder() }
                    .keyboardShortcut("o")
                Button("Reload Catalogue") { model.reload() }
                    .keyboardShortcut("r")
            }
        }
    }
}
