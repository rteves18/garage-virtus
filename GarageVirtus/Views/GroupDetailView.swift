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
            model.selectDefaultYearWindow(buildMonth: catalogue.buildMonth)
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
        // A plain side panel at a fixed width, not `.inspector`: inside NavigationSplitView's detail column the
        // inspector adds another split-view column whose size SwiftUI keeps renegotiating, which looped layout
        // until AppKit killed the app whenever a group opened.
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                GroupHeader(model: model, file: file)
                Divider()
                SchemaStackView(model: model, file: file)
            }
            if model.showInspector, let schema = model.schema {
                Divider()
                PartsInspector(schema: schema, groupCode: model.group.code, selectedPNC: $model.selectedPNC, hoveredPNC: $model.hoveredPNC,
                               highlightedOEM: $model.highlightedOEM)
                    .frame(width: 380)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $model.showHotspots) {
                    Label("Hotspots", systemImage: "square.dashed")
                }
                .help("Outline every clickable callout on the diagram")
                Button(action: toggleInspector) {
                    Label("Parts", systemImage: "sidebar.right")
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

            HStack(spacing: 12) {
                if !model.yearWindows.isEmpty {
                    YearWindowPicker(model: model)
                }
                if model.visibleSchemas.count > 1 {
                    // Menus, not segmented controls: segments can't shrink, and resizing the window with them on
                    // screen sends NSSplitView into a constraint loop that AppKit kills the app for.
                    Picker("Jump to schema", selection: $model.schemaIndex) {
                        ForEach(model.visibleSchemas, id: \.schema.id) { entry in
                            Text(model.label(for: entry.schema)).tag(entry.index)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 120, maxWidth: 420, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// Picks the build period to show schemas for. The choice carries over to other groups.
private struct YearWindowPicker: View {
    @Environment(CatalogueViewModel.self) private var catalogue
    let model: GroupDetailViewModel

    var body: some View {
        Picker("Years", selection: selection) {
            Text("All years").tag(YearWindow?.none)
            ForEach(model.yearWindows) { window in
                Text(window.title).tag(YearWindow?.some(window))
            }
        }
        .pickerStyle(.menu)
        .frame(minWidth: 120, maxWidth: 240, alignment: .leading)
    }

    private var selection: Binding<YearWindow?> {
        Binding(
            get: { model.selectedYearWindow },
            set: { window in
                model.selectedYearWindow = window
                catalogue.buildMonth = window?.from
            })
    }
}
