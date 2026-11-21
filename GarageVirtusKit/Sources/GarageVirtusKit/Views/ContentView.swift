import SwiftUI

public struct ContentView: View {
    @Environment(CatalogueStore.self) private var store
    @State private var selection: String?
    @State private var showUnscraped = false
    @State private var search = ""

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, showUnscraped: showUnscraped, search: search)
                .navigationSplitViewColumnWidth(min: 260, ideal: 310)
                .searchable(text: $search, placement: .sidebar, prompt: "Group, OEM number or Amayama link")
                .toolbar {
                    ToolbarItem {
                        Toggle(isOn: $showUnscraped) {
                            Label("Show unscraped", systemImage: "circle.dashed")
                        }
                        .help("Show groups that haven't been scraped yet")
                    }
                }
        } detail: {
            if let id = selection, let group = store.group(id: id) {
                GroupDetailView(group: group)
                    .id(group.id)
            } else {
                ContentUnavailableView(
                    "Select a schema group",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("\(store.scrapedCount) of \(store.totalCount) groups scraped · \(store.indexedPartCount) part numbers\n\(store.root.path)")
                )
            }
        }
        .onChange(of: store.focus) { _, focus in
            if let focus { selection = focus.groupID }
        }
    }
}
