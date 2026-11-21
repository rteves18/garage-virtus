import GarageVirtusKit
import SwiftData
import SwiftUI

/// Every part with one status, as a table. Owned lists show purchase details and total spent; the Need list shows
/// how many Ryan has against how many he needs.
struct GarageListView: View {
    @Environment(GarageStore.self) private var garage
    let status: PartStatus

    @Query private var rows: [GaragePart]
    @Query private var allParts: [GaragePart]

    init(status: PartStatus) {
        self.status = status
        let raw = status.rawValue
        _rows = Query(filter: #Predicate<GaragePart> { $0.statusRaw == raw }, sort: \GaragePart.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GarageListHeader(status: status, rows: rows)
            Divider()
            if status.isOwned {
                OwnedTable(rows: rows)
            } else {
                WishTable(rows: rows, allParts: allParts, isNeedList: status == .need)
            }
        }
        .navigationTitle(status.title)
        .toolbar {
            ToolbarItem {
                Button(action: addPart) { Label("Add part", systemImage: "plus") }
                    .help("Add a part with no catalogue part number")
            }
        }
    }

    private func addPart() {
        if status.isOwned {
            garage.addOwned(oemNumber: nil, name: "New part", status: status)
        } else {
            garage.markWanted(oemNumber: nil, name: "New part", status: status)
        }
    }
}

private struct GarageListHeader: View {
    let status: PartStatus
    let rows: [GaragePart]

    var body: some View {
        let spent = rows.compactMap(\.cost).reduce(Decimal.zero, +)
        HStack {
            Text(status.title).font(.title3.weight(.semibold))
            Text("Parts: \(rows.count)").foregroundStyle(.secondary)
            Spacer()
            if status.isOwned {
                Text("Spent: \(spent, format: .currency(code: "USD"))").monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct OwnedTable: View {
    let rows: [GaragePart]

    var body: some View {
        Table(rows) {
            TableColumn("Name", value: \.name)
            TableColumn("Part number") { Text($0.oemNumber ?? "—").monospaced() }
            TableColumn("Qty") { Text("\($0.quantity)").monospacedDigit() }.width(40)
            TableColumn("Condition") { Text($0.condition?.title ?? "—") }
            TableColumn("Cost") { part in
                Text(part.cost.map { $0.formatted(.currency(code: part.currency)) } ?? "—").monospacedDigit()
            }
            TableColumn("Seller") { Text($0.seller ?? "—") }
            TableColumn("Location") { Text($0.storageLocation ?? "—") }
        }
    }
}

private struct WishTable: View {
    let rows: [GaragePart]
    let allParts: [GaragePart]
    let isNeedList: Bool

    var body: some View {
        Table(rows) {
            TableColumn("Name", value: \.name)
            TableColumn("Part number") { Text($0.oemNumber ?? "—").monospaced() }
            TableColumn("Qty") { Text("\($0.quantity)").monospacedDigit() }.width(40)
            TableColumn("Have") { part in
                if isNeedList, let key = part.oemKey {
                    let coverage = GarageStore.coverage(forOEMKey: key, in: allParts)
                    Text("\(coverage.owned) of \(coverage.needed)")
                        .monospacedDigit()
                        .foregroundStyle(coverage.short == 0 ? .secondary : .primary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            TableColumn("Target price") { part in
                Text(part.targetPrice.map { $0.formatted(.currency(code: part.currency)) } ?? "—").monospacedDigit()
            }
        }
    }
}
