import Foundation

/// Mirrors `schema-group.json` written by tools/amayama/scrape_page.js (format_version 1).
/// Decoded with `.convertFromSnakeCase`, so `variant_id` -> `variantId`, etc.
struct SchemaGroupFile: Codable {
    let formatVersion: Int
    let source: Source
    let vehicle: Vehicle
    let group: GroupInfo
    let images: [String: ImageInfo]
    let schemas: [Schema]
}

struct Source: Codable {
    let site: String
    let url: String
    let scrapedAt: String?
}

struct Vehicle: Codable {
    let make: String
    let catalog: String?
    let model: String
    let frame: String
    let variantId: String
    let period: Period?
    let engine: String?
    let body: String?
    let grade: String?
    let transmission: String?
    let options: [String]
}

struct GroupInfo: Codable {
    let category: String
    let code: String
    let name: String
    let titleRaw: String?
}

struct ImageInfo: Codable {
    let url: String
    let width: Double
    let height: Double
}

struct Period: Codable, Hashable {
    let from: String?
    /// "..." on the site is stored as the last production month (1998-12); `raw` keeps the original.
    let to: String?
    let raw: String

    var display: String { "\(from ?? "?") – \(to ?? "?")" }
}

struct Schema: Codable, Identifiable {
    let id: String          // e.g. 101B_001_0
    let index: Int
    let of: Int?
    let applies: [String]
    let period: Period?
    let image: String       // file name in the frame's _images/ folder
    let callouts: [Callout]
}

struct Callout: Codable, Identifiable {
    let pnc: String         // the label on the diagram, e.g. 10102 / R10102
    let name: String?
    let hotspots: [Hotspot]
    let parts: [Part]

    var id: String { pnc }
    var displayName: String { (name ?? "").localizedCapitalized }

    func contains(oem: String) -> Bool {
        parts.contains { $0.matches(oem) }
    }
}

struct Hotspot: Codable {
    let shape: String
    let rect: HotspotRect   // pixels in the full-size image
    let norm: HotspotRect   // 0...1 fractions of image width/height
    let title: String?
}

struct HotspotRect: Codable {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double
}

struct Part: Codable {
    let oem: String
    let url: String?
    let applies: [String]
    let details: [String: String]
    let period: Period?
    let qty: Int?
    let qtyRaw: String?
    let price: Price
    let replacements: [Replacement]
    let descriptionRaw: String?

    /// True if this part or one of its replacements is `oem` (dash/case-insensitive).
    func matches(_ oem: String) -> Bool {
        let n = CatalogueStore.normalize(oem)
        return CatalogueStore.normalize(self.oem) == n
            || replacements.contains { CatalogueStore.normalize($0.oem) == n }
    }
}

struct Replacement: Codable {
    let oem: String
    let url: String?
    let price: Price
}

struct Price: Codable {
    /// "Available", or the site's own wording, e.g. "Discontinued", "Not available".
    let status: String?
    let amount: Double?
    let currency: String
    let raw: String?
}
