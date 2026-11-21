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
            Group {
                if model.isGarageOverviewSelected {
                    GarageOverviewView()
                } else if let status = model.selectedGarageStatus {
                    GarageListView(status: status)
                        .id(status)
                } else if let id = model.selection, let group = model.store.group(id: id) {
                    GroupDetailView(group: group, store: model.store)
                        .id(group.id)
                } else {
                    CatalogueEmptyView(state: model.emptyState)
                }
            }
            // A constant minimum size for the detail column. Left to SwiftUI, it's recomputed from the content
            // (header, menus, parts panel, spinner) and every change re-runs NSSplitView's constraint pass; when the
            // value flips, layout loops until AppKit kills the app. Room for the 380 pt parts panel plus a diagram.
            .frame(minWidth: 520, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        }
        .task { await model.load() }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let warning = model.garageStoreWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.85))
                    .foregroundStyle(.white)
            }
        }
    }
}

/// The detail area when no group is selected: a summary, or why there's nothing to show.
private struct CatalogueEmptyView: View {
    let state: CatalogueViewModel.EmptyState

    var body: some View {
        switch state {
        case .loading:
            ProgressView("Loading catalogue…")
        case .noCatalogue:
            ContentUnavailableView("No catalogue in this build", systemImage: "tray",
                                   description: Text("The app copies garage-virtus/catalogue in when it's built. Scrape at least one group, then build and run again."))
        case .ready(let summary):
            ContentUnavailableView("Select a schema group", systemImage: "wrench.and.screwdriver",
                                   description: Text(summary))
        }
    }
}
