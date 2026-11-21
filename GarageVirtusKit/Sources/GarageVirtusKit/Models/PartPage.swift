import Foundation

/// Mirrors catalogue/<make>/_parts/<key[0..<2]>/<key>.json written by tools/amayama/scrape_part.js.
/// Offers (price, stock, delivery) change often — check `source.scrapedAt`.
public struct PartPage: Codable {
    public let formatVersion: Int
    public let source: Source
    public let make: String
    public let oem: String
    public let key: String
    public let name: String
    public let brand: String?
    public let catalogName: String?
    public let weight: Weight
    public let offers: [Offer]
    public let substitutes: [Row]
    public let aftermarket: [Row]
    public let notices: [Notice]
    public let fits: [String: String]
    public let photos: [String]
    public let diagrams: [DiagramRef]

    public struct Weight: Codable {
        public let kg: Double?
        public let raw: String?
    }

    public struct Offer: Codable {
        public let from: String?
        public let price: Double?
        public let priceRaw: String?
        public let currency: String
        public let shippingRaw: String?
        public let deliveryRaw: String?
        public let availability: String?
    }

    public struct Row: Codable {
        public let cells: [String]
    }

    public struct Notice: Codable {
        public let kind: String
        public let text: String
    }

    /// A catalogue page on Amayama that lists this part (may be a frame/variant we haven't scraped).
    public struct DiagramRef: Codable, Hashable {
        public let catalog: String
        public let model: String
        public let frame: String
        public let variantId: String
        public let category: String
        public let group: String
        public let url: String
    }
}
