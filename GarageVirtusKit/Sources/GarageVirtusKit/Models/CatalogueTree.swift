import Foundation

/// Folder tree on disk — one file per source site, so scrapers for different sites never touch each other's data:
/// catalogue/<make>/_images/<site>/<path>                     e.g. amayama/imgjp16/RS13/101B_001.png, megazip/RS13/140_001.png
/// catalogue/<make>/_parts/<key[0..<2]>/<key>/<site>.json     e.g. 10/1010250FR2/amayama.json  (one folder per OEM number)
/// catalogue/<make>/<model>/<frame>/<variant>/<category>/<group>/<site>.json   e.g. …/engine/101_…/amayama.json, megazip.json
/// Legacy single-source names (schema-group.json, _parts/<k2>/<key>.json) are still read.
public struct FrameNode: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let imagesDir: URL
    public let variants: [VariantNode]
}

public struct VariantNode: Identifiable, Sendable {
    public let id: String
    public let variantId: String
    public let title: String
    public let categories: [CategoryNode]
}

public struct CategoryNode: Identifiable, Sendable {
    public let id: String
    public let key: String
    public let title: String
    public let groups: [GroupNode]
}

public struct GroupNode: Identifiable, Hashable, Sendable {
    public let id: String          // folder path
    public let code: String
    public let name: String
    public let folder: URL
    /// The group's source files, primary first (see `CatalogueStore.sourcePriority`). Empty until scraped.
    public let sources: [SourceFile]
    public let imagesDir: URL        // catalogue/<make>/_images
    public let legacyImagesDir: URL  // v1: catalogue/<make>/<model>/<frame>/_images
    public let variantId: String
    public let variantTitle: String

    public var isScraped: Bool { !sources.isEmpty }
    /// The primary source's file.
    public var jsonURL: URL? { sources.first?.url }
    /// The primary source, e.g. "amayama".
    public var primarySite: String? { sources.first?.site }
}

/// One site's scrape of a schema group (or of a part page).
public struct SourceFile: Hashable, Sendable {
    /// "amayama", "megazip", … ("legacy" for an old schema-group.json, whose real site is inside the file).
    public let site: String
    public let url: URL

    /// "amayama" -> "Amayama".
    public var siteName: String { site.capitalized }
}
