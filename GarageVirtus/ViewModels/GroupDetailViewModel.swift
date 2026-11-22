import CoreGraphics
import Foundation
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

    /// The build period to show schemas for, or nil for all years. Choosing one moves the current schema into view.
    var selectedYearWindow: YearWindow? {
        didSet {
            guard selectedYearWindow != oldValue,
                  let first = visibleSchemas.first, !visibleSchemas.contains(where: { $0.index == schemaIndex }) else { return }
            schemaIndex = first.index
        }
    }
    var highlightedOEM: String?
    var showInspector = true
    /// True when the right-hand panel shows the AI chat instead of the parts list.
    var showAssistant = false
    /// The chat about this group, created the first time it's opened (needs the API key).
    var assistant: PartsAssistant?
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
    func image(for schema: Schema) -> CGImage? {
        store.image(named: schema.image, for: group)
    }

    /// Diagram size from the scraped image info, then the image itself, then 1280×640.
    func imageSize(for schema: Schema) -> CGSize {
        if let info = file?.images[schema.image] { return CGSize(width: info.width, height: info.height) }
        if let image = image(for: schema) { return CGSize(width: image.width, height: image.height) }
        return CGSize(width: 1280, height: 640)
    }

    /// "180SX KRPS13 · grade · transmission · engine · options · period" for the header.
    var vehicleSummary: String {
        guard let vehicle = file?.vehicle else { return "" }
        let summary = [vehicle.model + " " + vehicle.frame, vehicle.grade, vehicle.transmission, vehicle.engine,
                       vehicle.options.joined(separator: " ")]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return summary + (vehicle.period.map { " · " + $0.display } ?? "")
    }

    /// The group's build periods, from where its schemas' date ranges start and end. Empty when they don't vary.
    var yearWindows: [YearWindow] {
        let windows = YearWindow.windows(for: file?.schemas.compactMap(\.period) ?? [])
        return windows.count > 1 ? windows : []
    }

    /// Schemas for the selected year window (all schemas without one), with their index in the file.
    var visibleSchemas: [(index: Int, schema: Schema)] {
        let schemas = Array((file?.schemas ?? []).enumerated()).map { (index: $0.offset, schema: $0.element) }
        guard let window = selectedYearWindow else { return schemas }
        return schemas.filter { entry in entry.schema.period.map(window.overlaps) ?? true }
    }

    /// Opens on a section of years rather than all years: the window containing the month last picked in any
    /// group (`buildMonth`), or else the vehicle's production start.
    func selectDefaultYearWindow(buildMonth: String?) {
        selectYearWindow(containing: buildMonth ?? file?.vehicle.period?.from)
    }

    /// Selects this group's year window containing `month` ("YYYY-MM"), or all years when none does.
    func selectYearWindow(containing month: String?) {
        selectedYearWindow = month.flatMap { month in yearWindows.first { $0.contains(month: month) } }
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

    /// Every part (and replacement) on the visible schemas, with catalogue prices, for pricing the assistant's lists.
    func assistantParts() -> [PartsListBuilder.CataloguePart] {
        visibleSchemas.flatMap { entry in
            entry.schema.callouts.flatMap { callout in
                callout.parts.flatMap { part in
                    [PartsListBuilder.CataloguePart(oem: part.oem, name: callout.name ?? "", price: part.price)]
                        + part.replacements.map { .init(oem: $0.oem, name: callout.name ?? "", price: $0.price) }
                }
            }
        }
    }

    /// What the assistant is told about this group: the visible schemas, their parts, and My garage coverage.
    func assistantContext(coverage: [String: Coverage]) -> String {
        guard let file else { return "" }
        return SectionContext.describe(file: file, schemas: visibleSchemas.map(\.schema), coverage: coverage)
    }

    /// Starts a new chat about the visible schemas.
    func startAssistant(apiKey: String, coverage: [String: Coverage]) {
        assistant = PartsAssistant(client: ClaudeClient(apiKey: apiKey), context: assistantContext(coverage: coverage),
                                   parts: assistantParts())
    }

    /// The group's page on Amayama, the primary source — even when this group's diagrams come from Megazip.
    var amayamaURL: URL? { store.amayamaURL(for: group) }

    /// Reads the group's primary source: Amayama, or Megazip for the few groups Amayama has nothing for.
    /// One diagram per group; other sites show up per part as "Also on …".
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
            if !visibleSchemas.contains(where: { $0.index == index }) { selectedYearWindow = nil }
            schemaIndex = index
        }
        selectedPNC = focus.pnc
        highlightedOEM = focus.oem
        showInspector = true
    }
}
