import CoreGraphics
import Foundation
import ImageIO
import Observation

/// The scraped catalogue: its folder tree, part index and search, read from a folder of JSON and diagram images.
@MainActor
@Observable
public final class CatalogueStore {
    /// The catalogue folder (holding make folders), or nil when there is none.
    public let root: URL?
    public private(set) var frames: [FrameNode] = []
    /// False when there's no folder or it has no make/model/frame folders.
    public var hasCatalogue: Bool { !frames.isEmpty }
    public private(set) var totalCount = 0
    public private(set) var scrapedCount = 0

    public private(set) var indexedPartCount = 0
    /// False until the first scan of `root` finishes.
    public private(set) var isLoaded = false

    @ObservationIgnored private var groupsByID: [String: GroupNode] = [:]
    @ObservationIgnored private var partIndex: [String: [PartRef]] = [:]
    @ObservationIgnored private var imageCache: [URL: CGImage] = [:]
    @ObservationIgnored private var partsDirs: [URL] = []
    @ObservationIgnored private var partPageCache: [String: PartPage?] = [:]

    nonisolated static let fileName = "schema-group.json"
    nonisolated static let categoryOrder = ["engine", "body", "trans", "electric", "misc"]
    nonisolated static let categoryTitles = [
        "engine": "Engine & fuel system",
        "body": "Body parts",
        "trans": "Chassis & transmission",
        "electric": "Electrics",
        "misc": "Accessories",
    ]

    /// Creates a store for the catalogue in `folder`. With `isLoadedImmediately: false`, call `loadInBackground()`
    /// to read it off the main thread.
    public init(folder: URL?, isLoadedImmediately: Bool = true) {
        root = folder
        if isLoadedImmediately { reload() }
    }

    /// Reads the folder tree and builds the part index on a background thread, then shows the result.
    public func loadInBackground() async {
        let root = root
        let snapshot = await Task.detached(priority: .userInitiated) { Self.scan(root) }.value
        apply(snapshot)
    }

    /// The schema group with folder path `id`, if it's in the current catalogue.
    public func group(id: String) -> GroupNode? { groupsByID[id] }

    /// Rereads the folder tree and rebuilds the part index on the calling (main) thread.
    public func reload() {
        apply(Self.scan(root))
    }

    /// Everything a scan of the catalogue folder produces, built off the main thread.
    struct Snapshot: Sendable {
        var frames: [FrameNode] = []
        var groupsByID: [String: GroupNode] = [:]
        var partsDirs: [URL] = []
        var partIndex: [String: [PartRef]] = [:]
    }

    private func apply(_ snapshot: Snapshot) {
        imageCache.removeAll()
        partPageCache.removeAll()
        groupsByID = snapshot.groupsByID
        partsDirs = snapshot.partsDirs
        frames = snapshot.frames
        totalCount = snapshot.groupsByID.count
        scrapedCount = snapshot.groupsByID.values.filter(\.isScraped).count
        partIndex = snapshot.partIndex
        indexedPartCount = snapshot.partIndex.count
        isLoaded = true
    }

    nonisolated static func scan(_ root: URL?) -> Snapshot {
        var byID: [String: GroupNode] = [:]
        var result: [FrameNode] = []
        var parts: [URL] = []

        for make in root.map(Self.subdirs) ?? [] {
            let imagesDir = make.appendingPathComponent("_images", isDirectory: true)
            parts.append(make.appendingPathComponent("_parts", isDirectory: true))
            for model in Self.subdirs(make) {
                for frame in Self.subdirs(model) {
                    let legacyImagesDir = frame.appendingPathComponent("_images", isDirectory: true)
                    let variants = Self.subdirs(frame).map { variantDir -> VariantNode in
                        let (vid, vtitle) = Self.splitCodeName(variantDir.lastPathComponent)
                        let categories = Self.subdirs(variantDir)
                            .sorted { Self.rank($0.lastPathComponent) < Self.rank($1.lastPathComponent) }
                            .map { catDir -> CategoryNode in
                                let key = catDir.lastPathComponent
                                let groups = Self.subdirs(catDir).map { g -> GroupNode in
                                    let json = g.appendingPathComponent(Self.fileName)
                                    let (code, name) = Self.splitCodeName(g.lastPathComponent)
                                    let node = GroupNode(
                                        id: g.path, code: code, name: name, folder: g,
                                        jsonURL: FileManager.default.fileExists(atPath: json.path) ? json : nil,
                                        imagesDir: imagesDir, legacyImagesDir: legacyImagesDir,
                                        variantId: vid, variantTitle: vtitle)
                                    byID[node.id] = node
                                    return node
                                }
                                return CategoryNode(id: catDir.path, key: key,
                                                    title: Self.categoryTitles[key] ?? key, groups: groups)
                            }
                        return VariantNode(id: variantDir.path, variantId: vid,
                                           title: vtitle.replacingOccurrences(of: " ", with: " · "),
                                           categories: categories)
                    }
                    let title = "\(make.lastPathComponent.capitalized) \(model.lastPathComponent.uppercased()) \(frame.lastPathComponent)"
                    result.append(FrameNode(id: frame.path, title: title, imagesDir: imagesDir, variants: variants))
                }
            }
        }
        return Snapshot(frames: result, groupsByID: byID, partsDirs: parts, partIndex: partIndex(for: Array(byID.values)))
    }

    // MARK: part index & search

    /// "10102-50FR2", "1010250fr2" -> "1010250FR2"
    public nonisolated static func normalize(_ oem: String) -> String {
        oem.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private nonisolated static func priceText(_ price: Price) -> String {
        if let amount = price.amount {
            return amount.formatted(.currency(code: price.currency))
        }
        return price.status ?? "—"
    }

    /// Reads every scraped schema-group.json once and indexes each OEM number (parts and replacements).
    private nonisolated static func partIndex(for groups: [GroupNode]) -> [String: [PartRef]] {
        var index: [String: [PartRef]] = [:]
        var seen = Set<String>()
        for group in groups where group.isScraped {
            guard let url = group.jsonURL, let data = try? Data(contentsOf: url),
                  let file = try? makeDecoder().decode(SchemaGroupFile.self, from: data) else { continue }
            for schema in file.schemas {
                for callout in schema.callouts {
                    func add(_ oem: String, replacementOf: String?, price: Price) {
                        let ref = PartRef(
                            oem: oem, groupID: group.id, groupCode: group.code, groupName: group.name,
                            variantId: group.variantId, variantTitle: group.variantTitle,
                            schemaId: schema.id, schemaIndex: schema.index, pnc: callout.pnc,
                            calloutName: callout.displayName, replacementOf: replacementOf,
                            priceText: Self.priceText(price))
                        guard seen.insert(ref.id).inserted else { return }
                        index[Self.normalize(oem), default: []].append(ref)
                    }
                    for part in callout.parts {
                        add(part.oem, replacementOf: nil, price: part.price)
                        for r in part.replacements { add(r.oem, replacementOf: part.oem, price: r.price) }
                    }
                }
            }
        }
        return index
    }

    /// Every place an OEM number appears.
    public func refs(for oem: String) -> [PartRef] {
        (partIndex[Self.normalize(oem)] ?? []).sorted { ($0.variantId, $0.groupCode, $0.schemaIndex) < ($1.variantId, $1.groupCode, $1.schemaIndex) }
    }

    /// Accepts an OEM number (any dash/case form, partial ok) or an Amayama part URL
    /// like https://www.amayama.com/en/part/nissan/1010250fr2?sid=101B_001_1.R10102
    public func searchParts(_ query: String) -> [PartRef] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = Self.parseAmayamaPartURL(q) {
            let all = refs(for: parsed.oem)
            if let schemaId = parsed.schemaId {
                let exact = all.filter { $0.schemaId == schemaId && (parsed.pnc == nil || $0.pnc == parsed.pnc) }
                if !exact.isEmpty { return exact + all.filter { !exact.contains($0) } }
            }
            return all
        }
        let n = Self.normalize(q)
        guard n.count >= 4, n.contains(where: \.isNumber) else { return [] }
        if let exact = partIndex[n] { return refs(for: exact[0].oem) }
        return partIndex.keys.filter { $0.contains(n) }.sorted().prefix(25).flatMap { refs(for: $0) }
    }

    /// Where `oem` is used, what it replaces, and its scraped part page.
    public func usage(of oem: String) -> PartUsage {
        let refs = refs(for: oem)
        let usedIn = refs.filter { $0.replacementOf == nil }
        let replaces = Array(Set(refs.compactMap(\.replacementOf))).sorted()
        let page = partPage(for: oem)
        let local = Set(usedIn.map { "\($0.variantId)|\($0.groupCode)" })
        let elsewhere = page?.diagrams.filter { !local.contains("\($0.variantId)|\($0.group)") } ?? []
        return PartUsage(usedIn: usedIn, replaces: replaces, page: page, elsewhere: elsewhere)
    }

    nonisolated static func parseAmayamaPartURL(_ string: String) -> (oem: String, schemaId: String?, pnc: String?)? {
        guard let comps = URLComponents(string: string), comps.host?.contains("amayama") == true else { return nil }
        let pieces = comps.path.split(separator: "/")
        guard let partIdx = pieces.firstIndex(of: "part"), pieces.count > partIdx + 2 else { return nil }
        let oem = String(pieces[partIdx + 2])
        var schemaId: String?, pnc: String?
        if let sid = comps.queryItems?.first(where: { $0.name == "sid" })?.value {
            let bits = sid.split(separator: ".", maxSplits: 1).map(String.init)
            schemaId = bits.first
            pnc = bits.count > 1 ? bits[1] : nil
        }
        return (oem, schemaId, pnc)
    }

    /// Decoder for catalogue JSON (snake_case keys).
    nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// Decodes the group's `schema-group.json`.
    /// - Throws: `CocoaError(.fileNoSuchFile)` for an unscraped group, or a decoding error.
    public func load(_ group: GroupNode) throws -> SchemaGroupFile {
        guard let url = group.jsonURL else { throw CocoaError(.fileNoSuchFile) }
        return try Self.makeDecoder().decode(SchemaGroupFile.self, from: Data(contentsOf: url))
    }

    /// The schema's diagram, decoded once with ImageIO and cached. `path` is the schema's image key, e.g.
    /// "imgjp16/RS13/101B_001.png" (v2) or "101B_001.png" (v1). Platform-neutral, so iOS can use it too.
    public func image(named path: String, for group: GroupNode) -> CGImage? {
        let candidates = [
            group.imagesDir.appendingPathComponent(path),
            group.legacyImagesDir.appendingPathComponent((path as NSString).lastPathComponent),
        ]
        for url in candidates {
            if let cached = imageCache[url] { return cached }
            if let image = Self.decodeImage(at: url) {
                imageCache[url] = image
                return image
            }
        }
        return nil
    }

    private nonisolated static func decodeImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    /// Scraped Amayama part page for an OEM number, if present: _parts/<key[0..<2]>/<key>.json
    public func partPage(for oem: String) -> PartPage? {
        let key = Self.normalize(oem)
        if let cached = partPageCache[key] { return cached }
        let decoder = Self.makeDecoder()
        var page: PartPage?
        for dir in partsDirs {
            let url = dir.appendingPathComponent(String(key.prefix(2))).appendingPathComponent("\(key).json")
            if let data = try? Data(contentsOf: url), let decoded = try? decoder.decode(PartPage.self, from: data) {
                page = decoded
                break
            }
        }
        partPageCache[key] = page
        return page
    }

    // MARK: helpers

    private nonisolated static func subdirs(_ url: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return items
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { !$0.lastPathComponent.hasPrefix("_") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private nonisolated static func rank(_ key: String) -> Int { categoryOrder.firstIndex(of: key) ?? 99 }

    /// "101_Bearing-and-short-engine-assembly" -> ("101", "Bearing and short engine assembly")
    /// "6976_1994-1998_TYPE-RX_MT_4WS" -> ("6976", "1994-1998 TYPE-RX MT 4WS")
    nonisolated static func splitCodeName(_ folder: String) -> (String, String) {
        guard let underscore = folder.firstIndex(of: "_") else { return (folder, folder) }
        let code = String(folder[..<underscore])
        var rest = String(folder[folder.index(after: underscore)...])
        if rest.contains("_") {
            rest = rest.replacingOccurrences(of: "_", with: " ")      // variant folder
        } else {
            rest = rest.replacingOccurrences(of: "-", with: " ")      // group folder
        }
        return (code, rest)
    }
}
