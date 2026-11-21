import AppKit
import GarageVirtusKit
import Observation

/// State for one schema group: its diagrams, the selected and hovered callouts, and the highlighted part.
@MainActor
@Observable
final class GroupDetailViewModel {
    /// What the group screen shows.
    enum Content {
        case loading
        case notScraped
        case failed(message: String)
        case noSchemas
        case loaded(SchemaGroupFile)
    }

    let group: GroupNode
    private(set) var content: Content = .loading

    /// Index into the loaded file's schemas. Changing it clears a selected callout the new schema doesn't have.
    var schemaIndex = 0 {
        didSet {
            guard let selectedPNC, schema?.callouts.contains(where: { $0.pnc == selectedPNC }) != true else { return }
            self.selectedPNC = nil
        }
    }

    /// The selected callout. Selecting one opens the inspector and clears a highlighted part it doesn't list.
    var selectedPNC: String? {
        didSet {
            if selectedPNC != nil { showInspector = true }
            guard selectedPNC != oldValue, let highlightedOEM else { return }
            let keepsHighlight = schema?.callouts.contains { $0.pnc == selectedPNC && $0.contains(oem: highlightedOEM) } == true
            if !keepsHighlight { self.highlightedOEM = nil }
        }
    }

    var hoveredPNC: String?
    var highlightedOEM: String?
    var showInspector = true
    var showHotspots = true

    @ObservationIgnored private let store: CatalogueStore

    init(group: GroupNode, store: CatalogueStore) {
        self.group = group
        self.store = store
    }

    var title: String { "\(group.code) · \(group.name)" }

    var file: SchemaGroupFile? {
        if case .loaded(let file) = content { file } else { nil }
    }

    /// The schema on screen (index clamped to the file's schemas).
    var schema: Schema? {
        guard let schemas = file?.schemas, !schemas.isEmpty else { return nil }
        return schemas[min(max(schemaIndex, 0), schemas.count - 1)]
    }

    var image: NSImage? {
        schema.flatMap { store.image(named: $0.image, for: group) }
    }

    /// Diagram size from the scraped image info, then the image itself, then 1280×640.
    var imageSize: CGSize {
        let info = schema.flatMap { file?.images[$0.image] }
        return CGSize(width: info?.width ?? image?.size.width ?? 1280,
                      height: info?.height ?? image?.size.height ?? 640)
    }

    /// "180SX KRPS13 · grade · transmission · engine · options · period" for the header.
    var vehicleSummary: String {
        guard let vehicle = file?.vehicle else { return "" }
        let summary = [vehicle.model + " " + vehicle.frame, vehicle.grade, vehicle.transmission, vehicle.engine,
                       vehicle.options.joined(separator: " ")]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return summary + (vehicle.period.map { " · " + $0.display } ?? "")
    }

    /// True when the schemas fit a segmented picker next to the inspector at the minimum window width.
    /// Larger groups (some have 20 schemas) use a menu, because segments can't shrink and would trigger a layout loop.
    static func fitsSegmentedPicker(schemaCount: Int) -> Bool {
        schemaCount <= 5
    }

    /// Short title for the schema picker's segment. Segmented pickers can't truncate, so long titles would force
    /// the detail column wider than the window allows next to the inspector.
    func segmentTitle(for schema: Schema) -> String {
        "Schema \(schema.index)"
    }

    /// Full description of a schema: number, engines it applies to, and production period.
    func label(for schema: Schema) -> String {
        var parts = ["Schema \(schema.index)"]
        if !schema.applies.isEmpty { parts.append(schema.applies.joined(separator: ", ")) }
        if let period = schema.period { parts.append(period.display) }
        return parts.joined(separator: " · ")
    }

    /// Reads the group's schema-group.json.
    func load() {
        guard group.isScraped else { content = .notScraped; return }
        do {
            let file = try store.load(group)
            content = file.schemas.isEmpty ? .noSchemas : .loaded(file)
        } catch {
            content = .failed(message: String(describing: error))
        }
    }

    /// Jumps to the schema, callout and part in `focus` when it targets this group.
    func apply(_ focus: PartFocus?) {
        guard let focus, focus.groupID == group.id, let file else { return }
        if let schemaId = focus.schemaId, let index = file.schemas.firstIndex(where: { $0.id == schemaId }) {
            schemaIndex = index
        }
        selectedPNC = focus.pnc
        highlightedOEM = focus.oem
        showInspector = true
    }
}
