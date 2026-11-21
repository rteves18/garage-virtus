import Foundation

/// A priced list of parts the assistant proposed, with totals computed by the app (never by the model).
public struct PartsList: Equatable, Sendable, Identifiable {
    public struct Line: Equatable, Sendable {
        public let oem: String
        public let name: String
        public let quantity: Int
        public let unitPrice: Decimal?
        public let lineTotal: Decimal?
        /// The catalogue's wording when there's no price, e.g. "Discontinued" or "Not available".
        public let status: String?
        public let reason: String?
        /// False when the part number isn't in the section the chat is about.
        public let isInSection: Bool
    }

    public let id = UUID()
    public let title: String
    public let lines: [Line]
    public let currency: String

    public var total: Decimal { lines.compactMap(\.lineTotal).reduce(Decimal.zero, +) }
    /// Lines with no price (unavailable, discontinued, or not in the section), so not in `total`.
    public var unpricedCount: Int { lines.filter { $0.lineTotal == nil }.count }

    public static func == (lhs: PartsList, rhs: PartsList) -> Bool {
        lhs.title == rhs.title && lhs.lines == rhs.lines && lhs.currency == rhs.currency
    }
}

/// Resolves part numbers the assistant asked for against the section's catalogue parts and prices them.
public struct PartsListBuilder: Sendable {
    public struct CataloguePart: Sendable {
        public let oem: String
        public let name: String
        public let price: Price

        public init(oem: String, name: String, price: Price) {
            self.oem = oem
            self.name = name
            self.price = price
        }
    }

    public struct Item: Sendable, Equatable {
        public let oem: String
        public let quantity: Int
        public let reason: String?

        public init(oem: String, quantity: Int, reason: String?) {
            self.oem = oem
            self.quantity = quantity
            self.reason = reason
        }
    }

    private let partsByKey: [String: CataloguePart]

    public init(parts: [CataloguePart]) {
        var byKey: [String: CataloguePart] = [:]
        for part in parts where byKey[CatalogueStore.normalize(part.oem)] == nil {
            byKey[CatalogueStore.normalize(part.oem)] = part
        }
        partsByKey = byKey
    }

    public func build(title: String, items: [Item]) -> PartsList {
        let lines = items.map { item -> PartsList.Line in
            guard let part = partsByKey[CatalogueStore.normalize(item.oem)] else {
                return .init(oem: item.oem, name: "Not in this section", quantity: item.quantity, unitPrice: nil,
                             lineTotal: nil, status: nil, reason: item.reason, isInSection: false)
            }
            let unit = part.price.amount.flatMap { Decimal(string: "\($0)") }
            return .init(oem: part.oem, name: part.name, quantity: item.quantity, unitPrice: unit,
                         lineTotal: unit.map { $0 * Decimal(item.quantity) }, status: unit == nil ? part.price.status : nil,
                         reason: item.reason, isInSection: true)
        }
        return PartsList(title: title, lines: lines, currency: "USD")
    }
}
