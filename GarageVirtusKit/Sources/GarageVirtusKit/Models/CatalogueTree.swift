import Foundation

/// Folder tree on disk (format v2):
/// catalogue/<make>/_images/<path on Amayama image server>     e.g. imgjp16/RS13/101B_001.png  (shared across frames)
/// catalogue/<make>/_parts/<key[0..<2]>/<key>.json              e.g. 10/1010250FR2.json        (one file per OEM number)
/// catalogue/<make>/<model>/<frame>/<variant>/<category>/<group>/schema-group.json
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
    public let jsonURL: URL?       // nil until scraped
    public let imagesDir: URL        // catalogue/<make>/_images
    public let legacyImagesDir: URL  // v1: catalogue/<make>/<model>/<frame>/_images
    public let variantId: String
    public let variantTitle: String

    public var isScraped: Bool { jsonURL != nil }
}
