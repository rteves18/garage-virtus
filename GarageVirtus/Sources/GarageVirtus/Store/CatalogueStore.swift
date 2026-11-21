import AppKit
import Observation

/// Folder tree on disk (format v2):
/// catalogue/<make>/_images/<path on Amayama image server>     e.g. imgjp16/RS13/101B_001.png  (shared across frames)
/// catalogue/<make>/_parts/<key[0..<2]>/<key>.json              e.g. 10/1010250FR2.json        (one file per OEM number)
/// catalogue/<make>/<model>/<frame>/<variant>/<category>/<group>/schema-group.json
struct FrameNode: Identifiable {
    let id: String
    let title: String
    let imagesDir: URL
    let variants: [VariantNode]
}

struct VariantNode: Identifiable {
    let id: String
    let variantId: String
    let title: String
    let categories: [CategoryNode]
}

struct CategoryNode: Identifiable {
    let id: String
    let key: String
    let title: String
    let groups: [GroupNode]
}

struct GroupNode: Identifiable, Hashable {
    let id: String          // folder path
    let code: String
    let name: String
    let folder: URL
    let jsonURL: URL?       // nil until scraped
    let imagesDir: URL        // catalogue/<make>/_images
    let legacyImagesDir: URL  // v1: catalogue/<make>/<model>/<frame>/_images
    let variantId: String
    let variantTitle: String

    var isScraped: Bool { jsonURL != nil }
}

/// One place an OEM number appears in the catalogue.
struct PartRef: Identifiable, Hashable {
    var id: String { "\(groupID)|\(schemaId)|\(pnc)|\(oem)|\(replacementOf ?? "")" }
    let oem: String
    let groupID: String
    let groupCode: String
    let groupName: String
    let variantId: String
    let variantTitle: String
    let schemaId: String
    let schemaIndex: Int
    let pnc: String
    let calloutName: String
    /// Set when this OEM is listed as a replacement for another part number.
    let replacementOf: String?
    let priceText: String
}

/// A request to open a group on a specific schema / callout / part (from search or a part page).
struct PartFocus: Equatable {
    let token = UUID()
    let groupID: String
    let schemaId: String?
    let pnc: String?
    let oem: String?
}

@MainActor
@Observable
final class CatalogueStore {
    private(set) var root: URL
    private(set) var frames: [FrameNode] = []
    private(set) var totalCount = 0
    private(set) var scrapedCount = 0

    private(set) var indexedPartCount = 0
    /// Set to jump the UI to a group/schema/callout/part.
    var focus: PartFocus?

    @ObservationIgnored private var groupsByID: [String: GroupNode] = [:]
    @ObservationIgnored private var partIndex: [String: [PartRef]] = [:]
    @ObservationIgnored private var imageCache: [URL: NSImage] = [:]
    @ObservationIgnored private var partsDirs: [URL] = []
    @ObservationIgnored private var partPageCache: [String: PartPage?] = [:]

    private static let rootKey = "catalogueRoot"
    static let fileName = "schema-group.json"
    static let categoryOrder = ["engine", "body", "trans", "electric", "misc"]
    static let categoryTitles = [
        "engine": "Engine & fuel system",
        "body": "Body parts",
        "trans": "Chassis & transmission",
        "electric": "Electrics",
        "misc": "Accessories",
    ]

    /// <repo>/GarageVirtus/Sources/GarageVirtus/Store/CatalogueStore.swift -> <repo>/catalogue
    static var defaultRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("catalogue", isDirectory: true)
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.rootKey),
           FileManager.default.fileExists(atPath: saved) {
            root = URL(fileURLWithPath: saved, isDirectory: true)
        } else {
            root = Self.defaultRoot
        }
        reload()
    }

    func group(id: String) -> GroupNode? { groupsByID[id] }

    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = root
        panel.message = "Choose the garage-virtus/catalogue folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        root = url
        UserDefaults.standard.set(url.path, forKey: Self.rootKey)
        reload()
    }

    func reload() {
        imageCache.removeAll()
        partPageCache.removeAll()
        var byID: [String: GroupNode] = [:]
        var result: [FrameNode] = []
        var parts: [URL] = []

        for make in subdirs(root) {
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
    nonisolated static func normalize(_ oem: String) -> String {
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
    func refs(for oem: String) -> [PartRef] {
        (partIndex[Self.normalize(oem)] ?? []).sorted { ($0.variantId, $0.groupCode, $0.schemaIndex) < ($1.variantId, $1.groupCode, $1.schemaIndex) }
    }

    /// Accepts an OEM number (any dash/case form, partial ok) or an Amayama part URL
    /// like https://www.amayama.com/en/part/nissan/1010250fr2?sid=101B_001_1.R10102
    func searchParts(_ query: String) -> [PartRef] {
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

    static func parseAmayamaPartURL(_ string: String) -> (oem: String, schemaId: String?, pnc: String?)? {
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

    func open(_ ref: PartRef) {
        focus = PartFocus(groupID: ref.groupID, schemaId: ref.schemaId, pnc: ref.pnc, oem: ref.oem)
    }

    func load(_ group: GroupNode) throws -> SchemaGroupFile {
        guard let url = group.jsonURL else { throw CocoaError(.fileNoSuchFile) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SchemaGroupFile.self, from: Data(contentsOf: url))
    }

    /// `path` is the schema's image key, e.g. "imgjp16/RS13/101B_001.png" (v2) or "101B_001.png" (v1).
    func image(named path: String, for group: GroupNode) -> NSImage? {
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
    func partPage(for oem: String) -> PartPage? {
        let key = Self.normalize(oem)
        if let cached = partPageCache[key] { return cached }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
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
    static func splitCodeName(_ folder: String) -> (String, String) {
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
