import GarageVirtusKit
import SwiftData
import SwiftUI

struct SidebarView: View {
    @Environment(CatalogueViewModel.self) private var model
    @State private var collapsed: Set<String> = []

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            let partHits = model.partHits
            if !partHits.isEmpty {
                Section("Parts (\(partHits.count))") {
                    ForEach(partHits) { ref in
                        Button { model.open(ref) } label: { PartHitRow(ref: ref) }
                            .buttonStyle(.plain)
                    }
                }
            }
            MyGarageSection()
            ForEach(model.store.frames) { frame in
                Section(frame.title) {
                    ForEach(frame.variants) { variant in
                        let categories = model.visibleCategories(for: variant)
                        if !categories.isEmpty {
                            DisclosureGroup(isExpanded: expanded(variant.id)) {
                                ForEach(categories) { visible in
                                    let category = visible.category
                                    DisclosureGroup(isExpanded: expanded(category.id)) {
                                        ForEach(visible.groups) { group in
                                            GroupRow(group: group).tag(group.id)
                                        }
                                    } label: {
                                        Label(category.title, systemImage: icon(category.key))
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(variant.title).fontWeight(.medium)
                                    Text("Variant \(variant.variantId)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if model.isSidebarEmpty {
                ContentUnavailableView("Nothing scraped yet", systemImage: "tray",
                                       description: Text("Turn on “Show unscraped” to browse the folder tree."))
            }
        }
    }

    private func expanded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(id) },
            set: { isOpen in if isOpen { collapsed.remove(id) } else { collapsed.insert(id) } }
        )
    }

    private func icon(_ key: String) -> String {
        switch key {
        case "engine": "engine.combustion"
        case "body": "car.side"
        case "trans": "gearshape.2"
        case "electric": "bolt"
        default: "shippingbox"
        }
    }
}

private struct GroupRow: View {
    let group: GroupNode

    var body: some View {
        HStack(spacing: 8) {
            Text(group.code)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 34, alignment: .leading)
            Text(group.name)
                .lineLimit(1)
            Spacer(minLength: 0)
            if !group.isScraped {
                Image(systemName: "circle.dashed").foregroundStyle(.tertiary)
            }
        }
        .opacity(group.isScraped ? 1 : 0.6)
    }
}

private struct PartHitRow: View {
    let ref: PartRef

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(ref.oem).font(.system(.body, design: .monospaced).weight(.medium))
                Spacer()
                Text(ref.priceText).font(.caption).foregroundStyle(.secondary)
            }
            Text("\(ref.groupCode) \(ref.groupName) · Schema \(ref.schemaIndex) · \(ref.pnc)")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(ref.replacementOf.map { "Variant \(ref.variantId) · replaces \($0)" } ?? "Variant \(ref.variantId)")
                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

/// My garage: one row per status, with how many rows each has.
private struct MyGarageSection: View {
    @Query private var parts: [GaragePart]

    var body: some View {
        let counts = Dictionary(grouping: parts, by: \.statusRaw).mapValues(\.count)
        Section("My garage") {
            ForEach(PartStatus.allCases, id: \.self) { status in
                HStack {
                    Label(status.title, systemImage: icon(status))
                    Spacer()
                    Text("\(counts[status.rawValue] ?? 0)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .tag(CatalogueViewModel.garageTag(status))
            }
        }
    }

    private func icon(_ status: PartStatus) -> String {
        switch status {
        case .need: "exclamationmark.circle"
        case .want: "star"
        case .inStorage: "shippingbox"
        case .waitingToInstall: "clock"
        case .installed: "checkmark.circle"
        }
    }
}
