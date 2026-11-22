import GarageVirtusKit
import SwiftData
import SwiftUI

/// Right-hand inspector: every callout on the current schema with its OEM parts.
/// Selecting a hotspot scrolls here and highlights; hovering a card highlights the diagram.
struct PartsInspector: View {
    let schema: GarageVirtusKit.Schema
    /// The schema group's code, recorded with parts marked from here.
    let groupCode: String
    /// The site this schema comes from; other sites' listings show as alternatives under each part.
    let site: String
    @Binding var selectedPNC: String?
    @Binding var hoveredPNC: String?
    @Binding var highlightedOEM: String?
    /// Selections made here (clicking a card header) shouldn't scroll the list out from under the cursor.
    @State private var selectedFromInspector = false
    /// One query for the whole panel (not one per row); rows get their tracked entries by part number.
    @Query private var garageParts: [GaragePart]
    @Environment(GarageStore.self) private var garage

    var body: some View {
        let carID = garage.activeCar.id
        let trackedByKey = Dictionary(grouping: garageParts.filter { $0.oemKey != nil && $0.car?.id == carID }) { $0.oemKey ?? "" }
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
                                    groupCode: groupCode,
                                    site: site,
                                    trackedByKey: trackedByKey,
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
    let groupCode: String
    let site: String
    let trackedByKey: [String: [GaragePart]]
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
                Text("Parts: \(callout.parts.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)   // only the header selects, so the ⓘ buttons don't
            ForEach(Array(callout.parts.enumerated()), id: \.offset) { index, part in
                if index > 0 { Divider() }
                PartRow(part: part, calloutName: callout.displayName, highlightedOEM: highlightedOEM,
                        groupCode: groupCode, pnc: callout.pnc, site: site,
                        tracked: trackedByKey[CatalogueStore.normalize(part.oem)] ?? [])
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.10)) : AnyShapeStyle(.background))
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
    @Environment(CatalogueViewModel.self) private var catalogue
    @Environment(GarageStore.self) private var garage
    let part: Part
    let calloutName: String
    let highlightedOEM: String?
    let groupCode: String
    let pnc: String
    /// The site this part list comes from.
    let site: String
    /// My garage rows for this part number.
    let tracked: [GaragePart]
    @State private var showDetail = false

    /// The same number on other sites, primary-first order.
    private var alternatives: [SourceOffer] {
        catalogue.store.offers(for: part.oem).filter { $0.site != site }
    }

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
                            .environment(catalogue)
                    }
                Spacer()
                if !tracked.isEmpty {
                    GarageBadge(tracked: tracked) { catalogue.selection = CatalogueViewModel.garageTag($0) }
                }
                PriceLabel(price: part.price)
            }

            ForEach(alternatives) { offer in
                AlternativeRow(offer: offer)
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
        .contextMenu { GarageMenu(oem: part.oem, name: calloutName, groupCode: groupCode, pnc: pnc, tracked: tracked) }
    }
}

/// "Also on Megazip · $1.18 ↗": another site's listing for the same number, under the primary price.
private struct AlternativeRow: View {
    let offer: SourceOffer

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Also on \(offer.siteName)").foregroundStyle(.secondary)
            Spacer()
            OfferPriceText(offer: offer)
            if let urlString = offer.url, let url = URL(string: urlString) {
                Link(destination: url) { Image(systemName: "arrow.up.right") }
                    .help("Open on \(offer.siteName)")
            }
        }
        .font(.caption)
    }
}

/// An offer's best price, else its status ("Discontinued"), else a dash.
private struct OfferPriceText: View {
    let offer: SourceOffer

    var body: some View {
        if let amount = offer.bestAmount {
            Text(amount, format: .currency(code: offer.price?.currency ?? offer.page?.offers.first?.currency ?? "USD"))
                .monospacedDigit()
        } else if let price = offer.price {
            PriceLabel(price: price)
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }
}

/// In-app part page: every place this OEM number appears, and its replacement chain.
struct PartDetailView: View {
    @Environment(CatalogueViewModel.self) private var catalogue
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
        let usage = catalogue.store.usage(of: oem)
        let usedIn = usage.usedIn
        let page = usage.page

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
            if usage.offers.isEmpty {
                HStack {
                    Text("Catalogue price").foregroundStyle(.secondary)
                    Spacer()
                    PriceLabel(price: price)
                }
            } else {
                section("Where to get it") {
                    ForEach(Array(usage.offers.enumerated()), id: \.element.id) { index, offer in
                        HStack(alignment: .firstTextBaseline) {
                            Text(offer.siteName).fontWeight(index == 0 ? .semibold : .regular)
                            if index == 0 {
                                Text("primary").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            OfferPriceText(offer: offer)
                            if let urlString = offer.url, let link = URL(string: urlString) {
                                Link(destination: link) { Image(systemName: "arrow.up.right") }
                                    .help("Open on \(offer.siteName)")
                            }
                        }
                    }
                }
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
            if !usage.replaces.isEmpty {
                section("Replaces") {
                    ForEach(usage.replaces, id: \.self) { CopyableOEM(oem: $0, font: .system(.body, design: .monospaced)) }
                }
            }
            section("Used in (\(usedIn.count))") {
                ForEach(usedIn) { ref in
                    Button { dismiss(); catalogue.open(ref) } label: {
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
            if !usage.elsewhere.isEmpty {
                section("Also on \(usage.page?.source.siteName ?? "the source site") (\(usage.elsewhere.count), not in this catalogue)") {
                    ForEach(usage.elsewhere, id: \.self) { ref in
                        if let link = URL(string: ref.url) {
                            Link("\(ref.model.uppercased()) \(ref.frame) · \(ref.variantId) · \(ref.category)/\(ref.group)", destination: link)
                                .font(.callout)
                        }
                    }
                }
            }
            Divider()
            if let page {
                Text("Part page scraped \(page.source.scrapedAt ?? "?"). Offers change often.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Weight, offers and fitment come from the part's page on the source site, which hasn't been scraped for this part yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let link = URL(string: page?.source.url ?? url ?? "") {
                Link("View on \(page?.source.siteName ?? "Amayama")", destination: link).font(.callout)
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

/// Where a part number stands in My garage: "Need · have 2 of 4", "Want", or "Have 3". Clicking opens that list.
private struct GarageBadge: View {
    let tracked: [GaragePart]
    let open: (PartStatus) -> Void

    var body: some View {
        let wish = tracked.first { !$0.status.isOwned }
        let owned = tracked.filter(\.status.isOwned).reduce(0) { $0 + $1.quantity }
        let status = wish?.status ?? tracked.first?.status ?? .inStorage
        Button { open(status) } label: {
            Text(label(wish: wish, owned: owned))
                .font(.caption.weight(.medium))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(color(wish: wish, owned: owned).opacity(0.18), in: Capsule())
                .foregroundStyle(color(wish: wish, owned: owned))
        }
        .buttonStyle(.plain)
        .help("Open in My garage")
    }

    private func label(wish: GaragePart?, owned: Int) -> String {
        switch wish?.status {
        case .need: "Need · have \(owned) of \(wish?.quantity ?? 0)"
        case .want: owned > 0 ? "Want · have \(owned)" : "Want"
        default: "Have \(owned)"
        }
    }

    private func color(wish: GaragePart?, owned: Int) -> Color {
        switch wish?.status {
        case .need: owned >= (wish?.quantity ?? 0) ? .green : .orange
        case .want: .purple
        default: .green
        }
    }
}

/// Right-click actions to record a catalogue part in My garage.
private struct GarageMenu: View {
    @Environment(GarageStore.self) private var garage
    let oem: String
    let name: String
    let groupCode: String
    let pnc: String
    let tracked: [GaragePart]

    var body: some View {
        Button("Need it") { garage.markWanted(oemNumber: oem, name: name, status: .need, groupCode: groupCode, pnc: pnc) }
        Button("Want it") { garage.markWanted(oemNumber: oem, name: name, status: .want, groupCode: groupCode, pnc: pnc) }
        Divider()
        Button("Have it (in storage)") { garage.addOwned(oemNumber: oem, name: name, status: .inStorage, groupCode: groupCode, pnc: pnc) }
        Button("Have it, waiting to install") { garage.addOwned(oemNumber: oem, name: name, status: .waitingToInstall, groupCode: groupCode, pnc: pnc) }
        Button("Installed") { garage.addOwned(oemNumber: oem, name: name, status: .installed, groupCode: groupCode, pnc: pnc) }
        if let wish = tracked.first(where: { !$0.status.isOwned }) {
            Divider()
            Button("Stop tracking \(wish.status.title.lowercased())") { garage.delete(wish) }
        }
    }
}
