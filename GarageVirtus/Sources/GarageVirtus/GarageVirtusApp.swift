import SwiftUI
import AppKit

@main
struct GarageVirtusApp: App {
    @State private var store = CatalogueStore()

    init() {
        // Lets `swift run` show a normal Dock app + menu bar (no .app bundle needed).
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Garage Virtus") {
            ContentView()
                .environment(store)
                .frame(minWidth: 1000, minHeight: 640)
                .onAppear { NSApp.activate() }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Catalogue Folder…") { store.chooseRoot() }
                    .keyboardShortcut("o")
                Button("Reload Catalogue") { store.reload() }
                    .keyboardShortcut("r")
            }
        }
    }
}
