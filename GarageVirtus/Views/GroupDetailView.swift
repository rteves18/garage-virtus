import GarageVirtusKit
import SwiftUI

struct GroupDetailView: View {
    @Environment(CatalogueViewModel.self) private var catalogue
    @State private var model: GroupDetailViewModel

    init(group: GroupNode, store: CatalogueStore) {
        _model = State(initialValue: GroupDetailViewModel(group: group, store: store))
    }

    var body: some View {
        Group {
            switch model.content {
            case .loading:
                ProgressView()
            case .notScraped:
                ContentUnavailableView("Not scraped yet", systemImage: "circle.dashed",
                                       description: Text(model.group.folder.lastPathComponent))
            case .failed(let message):
                ContentUnavailableView("Couldn't read schema-group.json", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            case .noSchemas:
                ContentUnavailableView("No schemas on this page", systemImage: "doc")
            case .loaded(let file):
                GroupContentView(model: model, file: file)
            }
        }
        .navigationTitle(model.title)
        .task {
            model.load()
            model.apply(catalogue.focus)
        }
        .onChange(of: catalogue.focus) { _, focus in
            model.apply(focus)
        }
    }
}

/// Header, diagram and parts inspector for a loaded group.
private struct GroupContentView: View {
    @Bindable var model: GroupDetailViewModel
    let file: SchemaGroupFile

    var body: some View {
        VStack(spacing: 0) {
            if let schema = model.schema {
                GroupHeader(model: model, file: file, schema: schema)
                Divider()
                if let image = model.image {
                    DiagramView(image: image, imageSize: model.imageSize, callouts: schema.callouts,
                                showHotspots: model.showHotspots,
                                selectedPNC: $model.selectedPNC, hoveredPNC: $model.hoveredPNC)
                } else {
                    ContentUnavailableView("Diagram missing", systemImage: "photo",
                                           description: Text("Expected _images/\(schema.image)"))
                }
            }
        }
        .inspector(isPresented: $model.showInspector) {
            if let schema = model.schema {
                PartsInspector(schema: schema, selectedPNC: $model.selectedPNC, hoveredPNC: $model.hoveredPNC,
                               highlightedOEM: $model.highlightedOEM)
                    .inspectorColumnWidth(min: 320, ideal: 420, max: 640)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $model.showHotspots) {
                    Label("Hotspots", systemImage: "square.dashed")
                }
                .help("Outline every clickable callout on the diagram")
                Button(action: toggleInspector) {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
    }

    private func toggleInspector() {
        model.showInspector.toggle()
    }
}

private struct GroupHeader: View {
    @Bindable var model: GroupDetailViewModel
    let file: SchemaGroupFile
    let schema: Schema

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(file.group.name.localizedCapitalized).font(.title3.weight(.semibold))
                Spacer()
                if let url = URL(string: file.source.url) {
                    Link("View on Amayama", destination: url).font(.callout)
                }
            }
            Text(model.vehicleSummary)
                .font(.callout).foregroundStyle(.secondary)

            if file.schemas.count > 1 {
                Picker("Schema", selection: $model.schemaIndex) {
                    ForEach(file.schemas.indices, id: \.self) { index in
                        Text(model.label(for: file.schemas[index])).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } else {
                Text(model.label(for: schema)).font(.callout)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
