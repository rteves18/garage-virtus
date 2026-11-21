import SwiftUI

struct SidebarView: View {
    @Environment(CatalogueStore.self) private var store
    @Binding var selection: String?
    let showUnscraped: Bool
    let search: String

    @State private var collapsed: Set<String> = []

    var body: some View {
        List(selection: $selection) {
            let partHits = store.searchParts(search)
            if !partHits.isEmpty {
                Section("Parts (\(partHits.count))") {
                    ForEach(partHits) { ref in
                        Button { store.open(ref) } label: { PartHitRow(ref: ref) }
                            .buttonStyle(.plain)
                    }
                }
            }
            ForEach(store.frames) { frame in
                Section(frame.title) {
                    ForEach(frame.variants) { variant in
                        let categories = visibleCategories(variant)
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
            if store.scrapedCount == 0 && !showUnscraped {
                ContentUnavailableView("Nothing scraped yet", systemImage: "tray",
                                       description: Text("Turn on “Show unscraped” to browse the folder tree."))
            }
        }
    }

    private struct VisibleCategory: Identifiable {
        let category: CategoryNode
        let groups: [GroupNode]
        var id: String { category.id }
    }

    private func visibleCategories(_ variant: VariantNode) -> [VisibleCategory] {
        variant.categories.compactMap { category in
            let groups = category.groups.filter { group in
                (showUnscraped || group.isScraped) && matches(group)
            }
            return groups.isEmpty ? nil : VisibleCategory(category: category, groups: groups)
        }
    }

    private func matches(_ group: GroupNode) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return group.code.localizedCaseInsensitiveContains(q) || group.name.localizedCaseInsensitiveContains(q)
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
