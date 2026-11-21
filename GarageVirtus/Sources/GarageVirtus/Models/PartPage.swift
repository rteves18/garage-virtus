import Foundation

/// Mirrors catalogue/<make>/_parts/<key[0..<2]>/<key>.json written by tools/amayama/scrape_part.js.
/// Offers (price, stock, delivery) change often — check `source.scrapedAt`.
struct PartPage: Codable {
    let formatVersion: Int
    let source: Source
    let make: String
    let oem: String
    let key: String
    let name: String
    let brand: String?
    let catalogName: String?
    let weight: Weight
    let offers: [Offer]
    let substitutes: [Row]
    let aftermarket: [Row]
    let notices: [Notice]
    let fits: [String: String]
    let photos: [String]
    let diagrams: [DiagramRef]

    struct Weight: Codable {
        let kg: Double?
        let raw: String?
    }

    struct Offer: Codable {
        let from: String?
        let price: Double?
        let priceRaw: String?
        let currency: String
        let shippingRaw: String?
        let deliveryRaw: String?
        let availability: String?
    }

    struct Row: Codable {
        let cells: [String]
    }

    struct Notice: Codable {
        let kind: String
        let text: String
    }

    /// A catalogue page on Amayama that lists this part (may be a frame/variant we haven't scraped).
    struct DiagramRef: Codable, Hashable {
        let catalog: String
        let model: String
        let frame: String
        let variantId: String
        let category: String
        let group: String
        let url: String
    }
}
