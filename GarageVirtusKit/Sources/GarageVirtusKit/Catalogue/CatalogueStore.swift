import AppKit
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

    @ObservationIgnored private var groupsByID: [String: GroupNode] = [:]
    @ObservationIgnored private var partIndex: [String: [PartRef]] = [:]
    @ObservationIgnored private var imageCache: [URL: NSImage] = [:]
    @ObservationIgnored private var partsDirs: [URL] = []
    @ObservationIgnored private var partPageCache: [String: PartPage?] = [:]

    static let fileName = "schema-group.json"
    static let categoryOrder = ["engine", "body", "trans", "electric", "misc"]
    static let categoryTitles = [
        "engine": "Engine & fuel system",
        "body": "Body parts",
        "trans": "Chassis & transmission",
        "electric": "Electrics",
        "misc": "Accessories",
    ]

    /// Creates a store that reads the catalogue in `folder`.
    public init(folder: URL?) {
        root = folder
        reload()
    }

    /// The schema group with folder path `id`, if it's in the current catalogue.
    public func group(id: String) -> GroupNode? { groupsByID[id] }

    /// Rereads the folder tree and rebuilds the part index.
    public func reload() {
        imageCache.removeAll()
        partPageCache.removeAll()
        var byID: [String: GroupNode] = [:]
        var result: [FrameNode] = []
        var parts: [URL] = []

        for make in root.map(subdirs) ?? [] {
            let imagesDir = make.appendingPathComponent("_images", isDirectory: true)
            parts.append(make.appendingPathComponent("_parts", isDirectory: true))
            for model in subdirs(make) {
                for frame in subdirs(model) {
                    let legacyImagesDir = frame.appendingPathComponent("_images", isDirectory: true)
                    let variants = subdirs(frame).map { variantDir -> VariantNode in
                        let (vid, vtitle) = Self.splitCodeName(variantDir.lastPathComponent)
                        let categories = subdirs(variantDir)
                            .sorted { Self.rank($0.lastPathComponent) < Self.rank($1.lastPathComponent) }
                            .map { catDir -> CategoryNode in
                                let key = catDir.lastPathComponent
                                let groups = subdirs(catDir).map { g -> GroupNode in
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
        groupsByID = byID
        partsDirs = parts
        frames = result
        totalCount = byID.count
        scrapedCount = byID.values.filter(\.isScraped).count
        buildPartIndex()
    }

    // MARK: part index & search

    /// "10102-50FR2", "1010250fr2" -> "1010250FR2"
    public nonisolated static func normalize(_ oem: String) -> String {
        oem.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func priceText(_ price: Price) -> String {
        if let amount = price.amount {
            return amount.formatted(.currency(code: price.currency))
        }
        return price.status ?? "—"
    }

    /// Reads every scraped schema-group.json once and indexes each OEM number (parts and replacements).
    private func buildPartIndex() {
        var index: [String: [PartRef]] = [:]
        var seen = Set<String>()
        for group in groupsByID.values where group.isScraped {
            guard let file = try? load(group) else { continue }
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
        partIndex = index
        indexedPartCount = index.count
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

    /// `path` is the schema's image key, e.g. "imgjp16/RS13/101B_001.png" (v2) or "101B_001.png" (v1).
    public func image(named path: String, for group: GroupNode) -> NSImage? {
        let candidates = [
            group.imagesDir.appendingPathComponent(path),
            group.legacyImagesDir.appendingPathComponent((path as NSString).lastPathComponent),
        ]
        for url in candidates {
            if let cached = imageCache[url] { return cached }
            if let image = NSImage(contentsOf: url) {
                imageCache[url] = image
                return image
            }
        }
        return nil
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

    private func subdirs(_ url: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return items
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { !$0.lastPathComponent.hasPrefix("_") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func rank(_ key: String) -> Int { categoryOrder.firstIndex(of: key) ?? 99 }

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
