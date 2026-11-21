import GarageVirtusKit
import SwiftUI

struct ContentView: View {
    @Environment(CatalogueViewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 310)
                .searchable(text: $model.search, placement: .sidebar, prompt: "Group, OEM number or Amayama link")
                .toolbar {
                    ToolbarItem {
                        Toggle(isOn: $model.showUnscraped) {
                            Label("Show unscraped", systemImage: "circle.dashed")
                        }
                        .help("Show groups that haven't been scraped yet")
                    }
                }
        } detail: {
            if let id = model.selection, let group = model.store.group(id: id) {
                GroupDetailView(group: group, store: model.store)
                    .id(group.id)
            } else {
                CatalogueEmptyView(state: model.emptyState, chooseFolder: model.chooseCatalogueFolder)
            }
        }
    }
}

/// The detail area when no group is selected: first launch, wrong folder, or a summary.
private struct CatalogueEmptyView: View {
    let state: CatalogueViewModel.EmptyState
    let chooseFolder: () -> Void

    var body: some View {
        switch state {
        case .chooseFolder:
            ContentUnavailableView {
                Label("Choose your catalogue folder", systemImage: "folder.badge.questionmark")
            } description: {
                Text("Garage Virtus reads diagrams and parts from your garage-virtus/catalogue folder.")
            } actions: {
                chooseFolderButton
            }
        case .noCatalogue(let path):
            ContentUnavailableView {
                Label("No catalogue found", systemImage: "tray")
            } description: {
                Text("\(path) has no make/model/frame folders.")
            } actions: {
                chooseFolderButton
            }
        case .ready(let summary):
            ContentUnavailableView("Select a schema group", systemImage: "wrench.and.screwdriver",
                                   description: Text(summary))
        }
    }

    private var chooseFolderButton: some View {
        Button("Choose Catalogue Folder…", action: chooseFolder)
            .buttonStyle(.borderedProminent)
    }
}
