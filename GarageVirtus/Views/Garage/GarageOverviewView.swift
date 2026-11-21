import GarageVirtusKit
import SwiftData
import SwiftUI

/// The current car at a glance: rows per status, total spent, and the needs still short.
struct GarageOverviewView: View {
    @Environment(GarageStore.self) private var garage
    @Environment(CatalogueViewModel.self) private var catalogue
    @Query private var allParts: [GaragePart]

    var body: some View {
        let car = garage.activeCar
        let parts = allParts.filter { $0.car?.id == car.id }
        let counts = Dictionary(grouping: parts, by: \.status).mapValues(\.count)
        let spent = parts.filter(\.status.isOwned).compactMap(\.cost).reduce(Decimal.zero, +)
        let shortNeeds = parts.filter { $0.status == .need }.compactMap { need -> (GaragePart, Coverage)? in
            guard let key = need.oemKey else { return nil }
            let coverage = GarageStore.coverage(forOEMKey: key, in: parts)
            return coverage.short > 0 ? (need, coverage) : nil
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(car.name).font(.largeTitle.weight(.semibold))
                    Text("Spent: \(spent, format: .currency(code: "USD"))").font(.title3).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(PartStatus.allCases, id: \.self) { status in
                        Button { catalogue.selection = CatalogueViewModel.garageTag(status) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(counts[status] ?? 0)").font(.system(size: 32, weight: .semibold)).monospacedDigit()
                                Text(status.title).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Still short").font(.headline)
                    if shortNeeds.isEmpty {
                        Text("Nothing short: every need is covered by parts you have.").foregroundStyle(.secondary)
                    }
                    ForEach(shortNeeds, id: \.0.id) { need, coverage in
                        HStack {
                            Text(need.name.localizedCapitalized)
                            Text(need.oemNumber ?? "").font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                            Spacer()
                            Text("Have \(coverage.owned) of \(coverage.needed)").monospacedDigit()
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("My garage")
    }
}
