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
            GroupHeader(model: model, file: file)
            Divider()
            SchemaStackView(model: model, file: file)
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

/// Group title, vehicle, source link, and a picker that jumps to a schema in the stack.
private struct GroupHeader: View {
    @Bindable var model: GroupDetailViewModel
    let file: SchemaGroupFile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(file.group.name.localizedCapitalized).font(.title3.weight(.semibold))
                Spacer()
                if let url = URL(string: file.source.url) {
                    Link("View on \(file.source.siteName)", destination: url).font(.callout)
                }
            }
            Text(model.vehicleSummary)
                .font(.callout).foregroundStyle(.secondary)

            if file.schemas.count > 1 {
                if GroupDetailViewModel.fitsSegmentedPicker(schemaCount: file.schemas.count) {
                    Picker("Schema", selection: $model.schemaIndex) {
                        ForEach(file.schemas.indices, id: \.self) { index in
                            Text(model.segmentTitle(for: file.schemas[index])).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                } else {
                    Picker("Schema", selection: $model.schemaIndex) {
                        ForEach(file.schemas.indices, id: \.self) { index in
                            Text(model.label(for: file.schemas[index])).tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 360, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
