import SwiftUI

/// Right-hand inspector: every callout on the current schema with its OEM parts.
/// Selecting a hotspot scrolls here and highlights; hovering a card highlights the diagram.
struct PartsInspector: View {
    let schema: Schema
    @Binding var selectedPNC: String?
    @Binding var hoveredPNC: String?
    @Binding var highlightedOEM: String?
    /// Selections made here (clicking a card header) shouldn't scroll the list out from under the cursor.
    @State private var selectedFromInspector = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Eager VStack (not Lazy): a LazyVStack that's been programmatically scrolled can report
                // stale frames on macOS, which mis-aims hover and popover anchors. Schemas are small.
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(schema.callouts) { callout in
                        CalloutCard(callout: callout,
                                    isSelected: callout.pnc == selectedPNC,
                                    isHovered: callout.pnc == hoveredPNC,
                                    highlightedOEM: highlightedOEM,
                                    onSelect: {
                                        selectedFromInspector = true
                                        selectedPNC = (selectedPNC == callout.pnc) ? nil : callout.pnc
                                    })
                            .id(callout.pnc)
                            .onHover { inside in
                                if inside { hoveredPNC = callout.pnc }
                                else if hoveredPNC == callout.pnc { hoveredPNC = nil }
                            }
                    }
                }
                .padding(12)
            }
            .onChange(of: selectedPNC) { _, new in
                if selectedFromInspector { selectedFromInspector = false; return }
                guard let new else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(new, anchor: .top) }
            }
            .onChange(of: highlightedOEM) { _, _ in
                guard let pnc = selectedPNC else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(pnc, anchor: .top) }
            }
        }
    }
}

private struct CalloutCard: View {
    let callout: Callout
    let isSelected: Bool
    let isHovered: Bool
    let highlightedOEM: String?
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(callout.pnc)
                    .font(.system(.headline, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Text(callout.displayName).font(.headline)
                Spacer()
                Text("\(callout.parts.count) part\(callout.parts.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)   // only the header selects, so the ⓘ buttons don't
            ForEach(Array(callout.parts.enumerated()), id: \.offset) { index, part in
                if index > 0 { Divider() }
                PartRow(part: part, calloutName: callout.displayName, highlightedOEM: highlightedOEM)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : isHovered ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct PartRow: View {
    @Environment(CatalogueStore.self) private var store
    let part: Part
    let calloutName: String
    let highlightedOEM: String?
    @State private var showDetail = false

    private var isHighlighted: Bool {
        guard let h = highlightedOEM else { return false }
        return CatalogueStore.normalize(part.oem) == CatalogueStore.normalize(h)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                CopyableOEM(oem: part.oem)
                Button { showDetail = true } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Part details: where it's used, replacements")
                    .popover(isPresented: $showDetail, arrowEdge: .trailing) {  // opens leftward, over the diagram
                        PartDetailView(oem: part.oem, name: calloutName, price: part.price,
                                       url: part.url, replacedBy: part.replacements)
                            .environment(store)
                    }
                Spacer()
                PriceLabel(price: part.price)
            }

            let meta = [
                part.applies.isEmpty ? nil : part.applies.joined(separator: ", "),
                part.period?.display,
                part.qty.map { "Qty \($0)" },
            ].compactMap { $0 }
            if !meta.isEmpty {
                Text(meta.joined(separator: "  ·  ")).font(.caption).foregroundStyle(.secondary)
            }

            ForEach(part.details.keys.sorted().filter { $0 != "applies" }, id: \.self) { key in
                Text("\(key.replacingOccurrences(of: "_", with: " ").capitalized): \(part.details[key] ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ForEach(Array(part.replacements.enumerated()), id: \.offset) { _, replacement in
                let isHit = highlightedOEM.map { CatalogueStore.normalize($0) == CatalogueStore.normalize(replacement.oem) } ?? false
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
                    Text("Replaced by").foregroundStyle(.secondary)
                    CopyableOEM(oem: replacement.oem, font: .system(.callout, design: .monospaced))
                    Spacer()
                    PriceLabel(price: replacement.price)
                }
                .font(.callout)
                .padding(.leading, 4)
                .padding(2)
                .background(isHit ? Color.yellow.opacity(0.35) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(4)
        .background(isHighlighted ? Color.yellow.opacity(0.35) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .animation(.easeOut(duration: 0.2), value: isHighlighted)
    }
}

/// In-app version of Amayama's part page: every place this OEM number appears, and its replacement chain.
struct PartDetailView: View {
    @Environment(CatalogueStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let oem: String
    let name: String
    let price: Price
    let url: String?
    let replacedBy: [Replacement]

    var body: some View {
        // Fixed size: a popover that resizes after opening gets re-positioned by macOS.
        ScrollView { details }
            .frame(width: 400, height: 520)
    }

    private var details: some View {
        let refs = store.refs(for: oem)
        let usedIn = refs.filter { $0.replacementOf == nil }
        let replaces = Array(Set(refs.compactMap(\.replacementOf))).sorted()
        let page = store.partPage(for: oem)

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                CopyableOEM(oem: oem, font: .system(.title2, design: .monospaced).weight(.semibold))
                Text(page?.name.localizedCapitalized ?? name).foregroundStyle(.secondary)
                if let page {
                    Text([page.brand, page.weight.kg.map { "\($0.formatted()) kg" } ?? "Weight \(page.weight.raw ?? "unknown")"]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Catalogue price").foregroundStyle(.secondary)
                Spacer()
                PriceLabel(price: price)
            }
            if let page {
                ForEach(Array(page.notices.enumerated()), id: \.offset) { _, notice in
                    Label(notice.text, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                }
                if !page.offers.isEmpty {
                    section("Offers") {
                        ForEach(Array(page.offers.enumerated()), id: \.offset) { _, offer in
                            HStack(alignment: .firstTextBaseline) {
                                Text(offer.from ?? "—")
                                Spacer()
                                if let price = offer.price {
                                    Text(price, format: .currency(code: offer.currency)).monospacedDigit()
                                } else {
                                    Text(offer.priceRaw ?? "—").foregroundStyle(.secondary)
                                }
                            }
                            Text(["Delivery \(offer.deliveryRaw ?? "?")", "Stock \(offer.availability ?? "?")"].joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !page.fits.isEmpty {
                    section("May fit") {
                        ForEach(page.fits.keys.sorted(), id: \.self) { k in
                            HStack { Text(k.capitalized).foregroundStyle(.secondary); Spacer(); Text(page.fits[k] ?? "") }
                        }
                    }
                }
                if !page.substitutes.isEmpty || !page.aftermarket.isEmpty {
                    section("Substitutes & aftermarket") {
                        ForEach(Array((page.substitutes + page.aftermarket).enumerated()), id: \.offset) { _, row in
                            Text(row.cells.joined(separator: " · ")).font(.callout)
                        }
                    }
                }
            }
            if !replacedBy.isEmpty {
                section("Replaced by") {
                    ForEach(replacedBy.map(\.oem), id: \.self) { CopyableOEM(oem: $0, font: .system(.body, design: .monospaced)) }
                }
            }
            if !replaces.isEmpty {
                section("Replaces") {
                    ForEach(replaces, id: \.self) { CopyableOEM(oem: $0, font: .system(.body, design: .monospaced)) }
                }
            }
            section("Used in (\(usedIn.count))") {
                ForEach(usedIn) { ref in
                    Button { dismiss(); store.open(ref) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(ref.groupCode) \(ref.groupName) · Schema \(ref.schemaIndex) · \(ref.pnc)")
                            Text("Variant \(ref.variantId) · \(ref.variantTitle)").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if let page {
                let local = Set(usedIn.map { "\($0.variantId)|\($0.groupCode)" })
                let elsewhere = page.diagrams.filter { !local.contains("\($0.variantId)|\($0.group)") }
                if !elsewhere.isEmpty {
                    section("Also on Amayama (\(elsewhere.count), not scraped)") {
                        ForEach(elsewhere, id: \.self) { ref in
                            if let link = URL(string: ref.url) {
                                Link("\(ref.model.uppercased()) \(ref.frame) · \(ref.variantId) · \(ref.category)/\(ref.group)", destination: link)
                                    .font(.callout)
                            }
                        }
                    }
                }
            }
            Divider()
            if let page {
                Text("Part page scraped \(page.source.scrapedAt ?? "?"). Offers change often.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Weight, offers and fitment come from Amayama's part page, which hasn't been scraped for this part yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let link = URL(string: page?.source.url ?? url ?? "") {
                Link("Open part page on Amayama", destination: link).font(.callout)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            content()
        }
    }
}

struct PriceLabel: View {
    let price: Price

    var body: some View {
        if let amount = price.amount {
            Text(amount, format: .currency(code: price.currency))
                .monospacedDigit()
        } else {
            Text(price.status ?? "—")
                .foregroundStyle(price.status == "Discontinued" ? Color.red.opacity(0.85) : Color.secondary)
        }
    }
}
