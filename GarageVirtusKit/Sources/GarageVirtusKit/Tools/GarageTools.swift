import Foundation

/// What the MCP server's tools do, independent of MCP: look things up in the catalogue and My garage and answer in
/// JSON text for Claude. Totals are computed here from catalogue prices, never by the model.
@MainActor
public final class GarageTools {
    public enum Failure: Error, Equatable, LocalizedError {
        case unknownGroup(String)
        case statusNotAllowed(String)

        public var errorDescription: String? {
            switch self {
            case .unknownGroup(let code): "No scraped group with code \(code). Use list_groups to see what's available."
            case .statusNotAllowed(let status): "add_to_garage records needs and wants only, not \(status)."
            }
        }
    }

    private let catalogue: CatalogueStore
    private let garage: GarageStore

    public init(catalogue: CatalogueStore, garage: GarageStore) {
        self.catalogue = catalogue
        self.garage = garage
    }

    /// Where a part number (or partial number, or Amayama link) appears, with its price.
    public func searchParts(query: String) throws -> String {
        let results = catalogue.searchParts(query).prefix(40).map { ref -> [String: Any] in
            var row: [String: Any] = ["oem": ref.oem, "group_code": ref.groupCode, "group_name": ref.groupName,
                                      "variant": ref.variantTitle, "diagram": ref.schemaId, "pnc": ref.pnc,
                                      "callout": ref.calloutName, "price": ref.priceText]
            if let replaced = ref.replacementOf { row["replaces"] = replaced }
            return row
        }
        return Self.json(["query": query, "results": Array(results)])
    }

    /// The catalogue's groups (one row per group code), optionally for one category.
    public func listGroups(category: String?) throws -> String {
        var byCode: [String: [String: Any]] = [:]
        for variant in catalogue.frames.flatMap(\.variants) {
            for categoryNode in variant.categories where category == nil || categoryNode.key == category {
                for group in categoryNode.groups {
                    let isScraped = group.isScraped || (byCode[group.code]?["scraped"] as? Bool ?? false)
                    if byCode[group.code] == nil || group.isScraped {
                        byCode[group.code] = ["code": group.code, "name": group.name, "category": categoryNode.key,
                                              "variant": group.variantTitle, "scraped": isScraped]
                    }
                }
            }
        }
        let groups = byCode.values.sorted { ($0["code"] as? String ?? "") < ($1["code"] as? String ?? "") }
        return Self.json(["groups": groups])
    }

    /// A group's diagrams, callouts and parts with quantity, price, replacements and My garage coverage.
    /// `year` ("1995" or "1995-03") keeps only diagrams for that build date.
    public func section(groupCode: String, year: String?) throws -> String {
        let (group, file) = try loadGroup(groupCode)
        let coverage = coverageByKey()
        let schemas = file.schemas.filter { schema in
            guard let year, let period = schema.period else { return true }
            return Self.overlaps(period, year: year)
        }
        let diagrams = schemas.map { schema -> [String: Any] in
            [
                "id": schema.id,
                "applies": schema.applies,
                "period": schema.period?.display ?? "",
                "callouts": schema.callouts.map { callout -> [String: Any] in
                    ["pnc": callout.pnc, "name": callout.name ?? "",
                     "parts": callout.parts.map { part in partRow(part, coverage: coverage) }]
                },
            ]
        }
        return Self.json([
            "group": ["code": group.code, "name": file.group.name, "category": file.group.category],
            "vehicle": [file.vehicle.model, file.vehicle.frame, file.vehicle.grade, file.vehicle.engine,
                        file.vehicle.transmission].compactMap { $0 }.joined(separator: " "),
            "diagrams": diagrams,
        ])
    }

    /// A priced list with line totals and a grand total.
    public func buildPartsList(title: String, items: [PartsListBuilder.Item]) throws -> String {
        let list = PartsListBuilder(parts: items.compactMap { cataloguePart($0.oem) }).build(title: title, items: items)
        return Self.json([
            "title": list.title,
            "total": "\(list.total)",
            "currency": list.currency,
            "unpriced_lines": list.unpricedCount,
            "lines": list.lines.map { line -> [String: Any] in
                var row: [String: Any] = ["oem": line.oem, "name": line.name, "quantity": line.quantity,
                                          "in_catalogue": line.isInSection]
                if let unit = line.unitPrice { row["unit_price"] = "\(unit)" }
                if let total = line.lineTotal { row["line_total"] = "\(total)" }
                if let status = line.status { row["status"] = status }
                if let reason = line.reason { row["reason"] = reason }
                return row
            },
        ])
    }

    /// Records parts as needed or wanted for the current car.
    public func addToGarage(items: [PartsListBuilder.Item], status: PartStatus) throws -> String {
        guard !status.isOwned else { throw Failure.statusNotAllowed(status.rawValue) }
        for item in items {
            let part = cataloguePart(item.oem)
            garage.markWanted(oemNumber: part?.oem ?? item.oem, name: part?.name ?? item.oem, status: status,
                              quantity: item.quantity)
        }
        return Self.json(["added": items.count, "status": status.title, "car": garage.activeCar.name])
    }

    /// The current car's counts per status, total spent, and needs not yet covered.
    public func garageStatus() throws -> String {
        let car = garage.activeCar
        let parts = garage.parts(for: car)
        let counts = Dictionary(grouping: parts, by: \.statusRaw).mapValues(\.count)
        let spent = parts.filter(\.status.isOwned).compactMap(\.cost).reduce(Decimal.zero, +)
        let short = parts.filter { $0.status == .need }.compactMap { need -> [String: Any]? in
            guard let key = need.oemKey else { return nil }
            let coverage = GarageStore.coverage(forOEMKey: key, in: parts)
            guard coverage.short > 0 else { return nil }
            return ["oem": need.oemNumber ?? "", "name": need.name, "need": coverage.needed,
                    "have": coverage.owned, "short": coverage.short]
        }
        return Self.json(["car": car.name, "counts": counts, "total_spent": "\(spent)", "still_short": short])
    }

    // MARK: helpers

    private func loadGroup(_ code: String) throws -> (GroupNode, SchemaGroupFile) {
        let groups = catalogue.frames.flatMap(\.variants).flatMap(\.categories).flatMap(\.groups)
        guard let group = groups.first(where: { $0.code.caseInsensitiveCompare(code) == .orderedSame && $0.isScraped }),
              let file = try? catalogue.load(group) else { throw Failure.unknownGroup(code) }
        return (group, file)
    }

    private func coverageByKey() -> [String: Coverage] {
        let parts = garage.parts(for: garage.activeCar)
        var coverage: [String: Coverage] = [:]
        for key in Set(parts.compactMap(\.oemKey)) {
            coverage[key] = GarageStore.coverage(forOEMKey: key, in: parts)
        }
        return coverage
    }

    private func partRow(_ part: Part, coverage: [String: Coverage]) -> [String: Any] {
        var row: [String: Any] = ["oem": part.oem, "applies": part.applies, "period": part.period?.display ?? ""]
        if let qty = part.qty { row["qty_per_car"] = qty }
        if let amount = part.price.amount { row["price"] = amount } else { row["status"] = part.price.status ?? "no price" }
        if !part.replacements.isEmpty { row["replaced_by"] = part.replacements.map(\.oem) }
        if let covered = coverage[CatalogueStore.normalize(part.oem)] {
            row["garage"] = ["need": covered.needed, "have": covered.owned]
        }
        return row
    }

    /// The catalogue's entry for a part number (as a part or a replacement), with the callout name and price.
    private func cataloguePart(_ oem: String) -> PartsListBuilder.CataloguePart? {
        let key = CatalogueStore.normalize(oem)
        for ref in catalogue.refs(for: oem) {
            guard let group = catalogue.group(id: ref.groupID), let file = try? catalogue.load(group) else { continue }
            for callout in file.schemas.flatMap(\.callouts) {
                for part in callout.parts {
                    if CatalogueStore.normalize(part.oem) == key {
                        return .init(oem: part.oem, name: callout.name ?? part.oem, price: part.price)
                    }
                    if let replacement = part.replacements.first(where: { CatalogueStore.normalize($0.oem) == key }) {
                        return .init(oem: replacement.oem, name: callout.name ?? replacement.oem, price: replacement.price)
                    }
                }
            }
        }
        return nil
    }

    /// True when a "YYYY-MM" period overlaps the year ("1995") or month ("1995-03").
    static func overlaps(_ period: Period, year: String) -> Bool {
        let start = year.count == 4 ? year + "-01" : year
        let end = year.count == 4 ? year + "-12" : year
        return (period.from ?? "0000-00") <= end && start <= (period.to ?? "9999-99")
    }

    static func json(_ object: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
