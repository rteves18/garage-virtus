import SwiftUI

struct GroupDetailView: View {
    @Environment(CatalogueStore.self) private var store
    let group: GroupNode

    @State private var file: SchemaGroupFile?
    @State private var loadError: String?
    @State private var schemaIndex = 0
    @State private var selectedPNC: String?
    @State private var hoveredPNC: String?
    @State private var highlightedOEM: String?
    @State private var showInspector = true
    @State private var showHotspots = true

    var body: some View {
        Group {
            if let file, !file.schemas.isEmpty {
                content(file)
            } else if let loadError {
                ContentUnavailableView("Couldn't read schema-group.json", systemImage: "exclamationmark.triangle",
                                       description: Text(loadError))
            } else if !group.isScraped {
                ContentUnavailableView("Not scraped yet", systemImage: "circle.dashed",
                                       description: Text(group.folder.lastPathComponent))
            } else if file != nil {
                ContentUnavailableView("No schemas on this page", systemImage: "doc")
            } else {
                ProgressView()
            }
        }
        .navigationTitle("\(group.code) · \(group.name)")
        .task {
            guard group.isScraped else { return }
            do { file = try store.load(group) } catch { loadError = String(describing: error) }
            applyFocus()
        }
        .onChange(of: store.focus) { _, _ in applyFocus() }
    }

    /// Jump to the schema / callout / part requested by search or a part page.
    private func applyFocus() {
        guard let focus = store.focus, focus.groupID == group.id, let file else { return }
        if let sid = focus.schemaId, let i = file.schemas.firstIndex(where: { $0.id == sid }) {
            schemaIndex = i
        }
        selectedPNC = focus.pnc
        highlightedOEM = focus.oem
        showInspector = true
    }

    @ViewBuilder
    private func content(_ file: SchemaGroupFile) -> some View {
        let schema = file.schemas[min(schemaIndex, file.schemas.count - 1)]
        let info = file.images[schema.image]
        let image = store.image(named: schema.image, for: group)
        let size = CGSize(width: info?.width ?? image?.size.width ?? 1280,
                          height: info?.height ?? image?.size.height ?? 640)

        VStack(spacing: 0) {
            header(file, schema: schema)
            Divider()
            if let image {
                DiagramView(image: image, imageSize: size, callouts: schema.callouts,
                            showHotspots: showHotspots,
                            selectedPNC: $selectedPNC, hoveredPNC: $hoveredPNC)
            } else {
                ContentUnavailableView("Diagram missing", systemImage: "photo",
                                       description: Text("Expected _images/\(schema.image)"))
            }
        }
        .inspector(isPresented: $showInspector) {
            PartsInspector(schema: schema, selectedPNC: $selectedPNC, hoveredPNC: $hoveredPNC,
                           highlightedOEM: $highlightedOEM)
                .inspectorColumnWidth(min: 320, ideal: 420, max: 640)
        }
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $showHotspots) {
                    Label("Hotspots", systemImage: "square.dashed")
                }
                .help("Outline every clickable callout on the diagram")
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        .onChange(of: selectedPNC) { old, new in
            if new != nil { showInspector = true }
            let current = file.schemas[min(schemaIndex, file.schemas.count - 1)]
            if old != new, let oem = highlightedOEM,
               !current.callouts.contains(where: { $0.pnc == new && $0.contains(oem: oem) }) {
                highlightedOEM = nil
            }
        }
        .onChange(of: schemaIndex) { _, _ in
            let pncs = Set(file.schemas[min(schemaIndex, file.schemas.count - 1)].callouts.map(\.pnc))
            if let sel = selectedPNC, !pncs.contains(sel) { selectedPNC = nil }
        }
    }

    private func header(_ file: SchemaGroupFile, schema: Schema) -> some View {
        let v = file.vehicle
        let summary = [v.model + " " + v.frame, v.grade, v.transmission, v.engine, v.options.joined(separator: " ")]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(file.group.name.localizedCapitalized).font(.title3.weight(.semibold))
                Spacer()
                if let url = URL(string: file.source.url) {
                    Link("View on Amayama", destination: url).font(.callout)
                }
            }
            Text(summary + (v.period.map { " · " + $0.display } ?? ""))
                .font(.callout).foregroundStyle(.secondary)

            if file.schemas.count > 1 {
                Picker("Schema", selection: $schemaIndex) {
                    ForEach(file.schemas.indices, id: \.self) { i in
                        Text(label(for: file.schemas[i])).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } else {
                Text(label(for: schema)).font(.callout)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func label(for schema: Schema) -> String {
        var parts = ["Schema \(schema.index)"]
        if !schema.applies.isEmpty { parts.append(schema.applies.joined(separator: ", ")) }
        if let p = schema.period { parts.append(p.display) }
        return parts.joined(separator: " · ")
    }
}
