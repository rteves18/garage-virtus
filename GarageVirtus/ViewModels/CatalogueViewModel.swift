import AppKit
import GarageVirtusKit
import Observation

/// App-wide browsing state: the chosen catalogue, sidebar selection and search, and jumps to parts.
@MainActor
@Observable
final class CatalogueViewModel {
    /// What the detail area shows when no group is selected.
    enum EmptyState: Equatable {
        case chooseFolder
        case noCatalogue(path: String)
        case ready(summary: String)
    }

    /// A category with only the groups the sidebar should show.
    struct VisibleCategory: Identifiable {
        let category: CategoryNode
        let groups: [GroupNode]
        var id: String { category.id }
    }

    let store: CatalogueStore
    var selection: String?
    var search = ""
    var showUnscraped = false
    /// The latest jump request. Group detail screens apply it when it targets them.
    private(set) var focus: PartFocus?

    init(store: CatalogueStore = CatalogueStore()) {
        self.store = store
    }

    /// Parts matching the search text (OEM number in any form, or an Amayama part link).
    var partHits: [PartRef] { store.searchParts(search) }

    /// True when the sidebar has nothing to list because no group is scraped and unscraped groups are hidden.
    var isSidebarEmpty: Bool { store.scrapedCount == 0 && !showUnscraped }

    var emptyState: EmptyState {
        guard let root = store.root else { return .chooseFolder }
        guard store.hasCatalogue else { return .noCatalogue(path: root.path) }
        return .ready(summary: "\(store.scrapedCount) of \(store.totalCount) groups scraped · \(store.indexedPartCount) part numbers\n\(root.path)")
    }

    /// The variant's categories, each with the groups that are scraped (or all, with `showUnscraped`) and match the search.
    func visibleCategories(for variant: VariantNode) -> [VisibleCategory] {
        variant.categories.compactMap { category in
            let groups = category.groups.filter { group in
                (showUnscraped || group.isScraped) && matchesSearch(group)
            }
            return groups.isEmpty ? nil : VisibleCategory(category: category, groups: groups)
        }
    }

    /// Asks for the catalogue folder and opens it. Cancelling keeps the current folder.
    func chooseCatalogueFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = store.root ?? CatalogueStore.suggestedFolder
        panel.message = "Choose the garage-virtus/catalogue folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFolder(url)
    }

    /// Opens `url` as the catalogue. If it can't be opened, the current catalogue and selection stay.
    func openFolder(_ url: URL) {
        do {
            try store.open(folder: url)
            selection = nil
        } catch {
            // Keep the current folder. The open panel only offers folders the app may read.
        }
    }

    /// Selects the part's group and asks it to show the part's schema and callout.
    func open(_ ref: PartRef) {
        focus = PartFocus(groupID: ref.groupID, schemaId: ref.schemaId, pnc: ref.pnc, oem: ref.oem)
        selection = ref.groupID
    }

    func reload() {
        store.reload()
    }

    private func matchesSearch(_ group: GroupNode) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return group.code.localizedCaseInsensitiveContains(query) || group.name.localizedCaseInsensitiveContains(query)
    }
}
