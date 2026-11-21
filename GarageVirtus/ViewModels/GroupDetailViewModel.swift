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

    /// The schema's diagram image.
    func image(for schema: Schema) -> NSImage? {
        store.image(named: schema.image, for: group)
    }

    /// Diagram size from the scraped image info, then the image itself, then 1280×640.
    func imageSize(for schema: Schema) -> CGSize {
        let info = file?.images[schema.image]
        let image = info == nil ? image(for: schema) : nil
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

    /// The id of the current schema, for scroll position: scrolling a schema into view makes it current, and
    /// making a schema current (picker, search jump) scrolls to it. Unknown ids are ignored.
    var currentSchemaID: String? {
        get { schema?.id }
        set {
            guard let newValue, let index = file?.schemas.firstIndex(where: { $0.id == newValue }) else { return }
            if index != schemaIndex { schemaIndex = index }
        }
    }

    /// Selects a callout on any schema in the stack, making that schema current.
    func selectCallout(_ pnc: String, inSchemaAt index: Int) {
        schemaIndex = index
        selectedPNC = pnc
    }

    /// True for the selected callout on the current schema (callout labels repeat across schemas).
    func isSelected(_ pnc: String, inSchemaAt index: Int) -> Bool {
        index == schemaIndex && pnc == selectedPNC
    }

    /// True for the hovered callout on the current schema.
    func isHovered(_ pnc: String, inSchemaAt index: Int) -> Bool {
        index == schemaIndex && pnc == hoveredPNC
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
