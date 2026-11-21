import CoreGraphics
import Foundation

/// Mirrors `schema-group.json` written by tools/amayama/scrape_page.js (format_version 1).
/// Decoded with `.convertFromSnakeCase`, so `variant_id` -> `variantId`, etc.
public struct SchemaGroupFile: Codable {
    public let formatVersion: Int
    public let source: Source
    public let vehicle: Vehicle
    public let group: GroupInfo
    public let images: [String: ImageInfo]
    public let schemas: [Schema]
}

public struct Source: Codable {
    public let site: String
    public let url: String
    public let scrapedAt: String?

    /// The site's name for link labels: "amayama" -> "Amayama", "megazip" -> "Megazip".
    public var siteName: String { site.capitalized }
}

public struct Vehicle: Codable {
    public let make: String
    public let catalog: String?
    public let model: String
    public let frame: String
    public let variantId: String
    public let period: Period?
    public let engine: String?
    public let body: String?
    public let grade: String?
    public let transmission: String?
    public let options: [String]
}

public struct GroupInfo: Codable {
    public let category: String
    public let code: String
    public let name: String
    public let titleRaw: String?
}

public struct ImageInfo: Codable {
    public let url: String
    public let width: Double
    public let height: Double
}

public struct Period: Codable, Hashable {
    public let from: String?
    /// "..." on the site is stored as the last production month (1998-12); `raw` keeps the original.
    public let to: String?
    public let raw: String

    public var display: String { "\(from ?? "?") – \(to ?? "?")" }
}

public struct Schema: Codable, Identifiable {
    public let id: String          // e.g. 101B_001_0
    public let index: Int
    public let of: Int?
    public let applies: [String]
    public let period: Period?
    public let image: String       // file name in the frame's _images/ folder
    public let callouts: [Callout]
}

public struct Callout: Codable, Identifiable {
    public let pnc: String         // the label on the diagram, e.g. 10102 / R10102
    public let name: String?
    public let hotspots: [Hotspot]
    public let parts: [Part]

    public var id: String { pnc }
    public var displayName: String { (name ?? "").localizedCapitalized }

    public func contains(oem: String) -> Bool {
        parts.contains { $0.matches(oem) }
    }
}

public struct Hotspot: Codable {
    public let shape: String
    public let rect: HotspotRect   // pixels in the full-size image
    public let norm: HotspotRect   // 0...1 fractions of image width/height
    public let title: String?
}

public struct HotspotRect: Codable {
    public let x1: Double
    public let y1: Double
    public let x2: Double
    public let y2: Double
}

public struct Part: Codable {
    public let oem: String
    public let url: String?
    public let applies: [String]
    public let details: [String: String]
    public let period: Period?
    public let qty: Int?
    public let qtyRaw: String?
    public let price: Price
    public let replacements: [Replacement]
    public let descriptionRaw: String?

    /// True if this part or one of its replacements is `oem` (dash/case-insensitive).
    public func matches(_ oem: String) -> Bool {
        let n = CatalogueStore.normalize(oem)
        return CatalogueStore.normalize(self.oem) == n
            || replacements.contains { CatalogueStore.normalize($0.oem) == n }
    }
}

public struct Replacement: Codable {
    public let oem: String
    public let url: String?
    public let price: Price
}

public struct Price: Codable, Sendable {
    /// "Available", or the site's own wording, e.g. "Discontinued", "Not available".
    public let status: String?
    public let amount: Double?
    public let currency: String
    public let raw: String?
}

extension Schema {
    /// The callout whose hotspot contains `point`, in 0...1 fractions of the diagram's width and height.
    /// `tolerance` (also a fraction) widens each hotspot so small labels are easy to hit.
    public func callout(at point: CGPoint, tolerance: CGFloat = 0) -> Callout? {
        callouts.first { callout in
            callout.hotspots.contains { $0.norm.rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
        }
    }
}

extension HotspotRect {
    /// The rect as a CGRect, in the same units (pixels for `rect`, 0...1 fractions for `norm`).
    public var rect: CGRect { CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1) }
}

