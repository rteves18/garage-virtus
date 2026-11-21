import Foundation
import GarageVirtusKit
import Observation

/// App-wide browsing state: the catalogue, sidebar selection and search, and jumps to parts.
@MainActor
@Observable
final class CatalogueViewModel {
    /// What the detail area shows when no group is selected.
    enum EmptyState: Equatable {
        case loading
        case noCatalogue
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
    /// The start month ("YYYY-MM") of the year window last picked in any group, so each group opens on the matching
    /// window. Set only when the user picks a window, so a group with no matching window doesn't clear it.
    var buildMonth: String?
    /// The latest jump request. Group detail screens apply it when it targets them.
    private(set) var focus: PartFocus?

    /// - Parameter store: defaults to the catalogue copied into the app from the repo's `catalogue/` folder at build time.
    init(store: CatalogueStore = CatalogueStore(folder: Bundle.main.url(forResource: "catalogue", withExtension: nil),
                                                isLoadedImmediately: false)) {
        self.store = store
    }

    /// Sidebar tag for a My garage status row.
    static func garageTag(_ status: PartStatus) -> String {
        "garage:" + status.rawValue
    }

    /// The My garage status selected in the sidebar, or nil when a catalogue group (or nothing) is selected.
    var selectedGarageStatus: PartStatus? {
        guard let selection, selection.hasPrefix("garage:") else { return nil }
        return PartStatus(rawValue: String(selection.dropFirst("garage:".count)))
    }

    /// Parts matching the search text (OEM number in any form, or an Amayama part link).
    var partHits: [PartRef] { store.searchParts(search) }

    /// True when the sidebar has nothing to list because no group is scraped and unscraped groups are hidden.
    var isSidebarEmpty: Bool { store.scrapedCount == 0 && !showUnscraped }

    var emptyState: EmptyState {
        guard store.isLoaded else { return .loading }
        guard store.hasCatalogue else { return .noCatalogue }
        return .ready(summary: "\(store.scrapedCount) of \(store.totalCount) groups scraped · \(store.indexedPartCount) part numbers")
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

    /// Reads the catalogue off the main thread (the app calls this once at launch).
    func load() async {
        guard !store.isLoaded else { return }
        await store.loadInBackground()
    }

    /// Selects the part's group and asks it to show the part's schema and callout.
    func open(_ ref: PartRef) {
        focus = PartFocus(groupID: ref.groupID, schemaId: ref.schemaId, pnc: ref.pnc, oem: ref.oem)
        selection = ref.groupID
    }

    private func matchesSearch(_ group: GroupNode) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return group.code.localizedCaseInsensitiveContains(query) || group.name.localizedCaseInsensitiveContains(query)
    }
}
