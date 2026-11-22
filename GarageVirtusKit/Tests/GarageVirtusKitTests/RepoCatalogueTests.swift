import CoreGraphics
import Foundation
import Testing
@testable import GarageVirtusKit

/// Decodes every file in the repo's real `catalogue/`, so a scraper or converter that writes a bad file fails here.
struct RepoCatalogueTests {
    /// <repo>/GarageVirtusKit/Tests/GarageVirtusKitTests/RepoCatalogueTests.swift -> <repo>/catalogue
    static let catalogue: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("catalogue", isDirectory: true)
    }()

    static func files(named predicate: (URL) -> Bool) -> [URL] {
        let enumerator = FileManager.default.enumerator(at: catalogue, includingPropertiesForKeys: nil)
        return (enumerator?.allObjects as? [URL] ?? []).filter(predicate)
    }

    /// Every group source file (`amayama.json`, `megazip.json`, legacy `schema-group.json`), not part pages.
    @Test func everySchemaGroupDecodesWithItsImages() throws {
        let files = Self.files { $0.pathExtension == "json" && !$0.path.contains("/_parts/")
            && $0.pathComponents.count > Self.catalogue.pathComponents.count + 6 }
        try #require(files.isEmpty == false)
        for url in files {
            let file = try CatalogueStore.makeDecoder().decode(SchemaGroupFile.self, from: Data(contentsOf: url))
            for schema in file.schemas {
                let image = Self.catalogue.appendingPathComponent("nissan/_images").appendingPathComponent(schema.image)
                #expect(FileManager.default.fileExists(atPath: image.path), "\(url.path): missing \(schema.image)")
            }
        }
    }

    @Test func everyPartPageDecodes() throws {
        let files = Self.files { $0.pathExtension == "json" && $0.path.contains("/_parts/") }
        try #require(files.isEmpty == false)
        for url in files {
            #expect(throws: Never.self, "\(url.lastPathComponent)") {
                try CatalogueStore.makeDecoder().decode(PartPage.self, from: Data(contentsOf: url))
            }
        }
    }

    @Test @MainActor func storeLoadsWholeCatalogue() {
        let clock = ContinuousClock()
        var store: CatalogueStore?
        let elapsed = clock.measure { store = CatalogueStore(folder: Self.catalogue) }
        #expect(store?.scrapedCount == 191)
        #expect((store?.indexedPartCount ?? 0) > 5_000)
        #expect(elapsed < .seconds(3), "Loading took \(elapsed)")
        print("Catalogue load: \(elapsed), \(store?.indexedPartCount ?? 0) part numbers")
    }

    @Test @MainActor func diagramDecodesToCGImageAtFullSize() throws {
        let store = CatalogueStore(folder: Self.catalogue)
        let group = try #require(store.frames.flatMap(\.variants).flatMap(\.categories).flatMap(\.groups)
            .first { $0.code == "101" && $0.isScraped })
        let image: CGImage = try #require(store.image(named: "amayama/imgjp16/RS13/101B_001.png", for: group))
        #expect(image.width == 1280)
        #expect(image.height == 639)
    }

    @Test @MainActor func amayamaIsPrimaryAndMegazipIsAnAlternative() throws {
        let store = CatalogueStore(folder: Self.catalogue)
        let groups = store.frames.flatMap(\.variants).flatMap(\.categories).flatMap(\.groups)
        let both = try #require(groups.first { Set($0.sources.map(\.site)).isSuperset(of: ["amayama", "megazip"]) })
        #expect(both.primarySite == "amayama")
        #expect(try store.load(both).source.site == "amayama")
        #expect(try store.load(both, site: "megazip").source.site == "megazip")
    }

    @Test @MainActor func everyGroupLinksToAmayama() throws {
        let store = CatalogueStore(folder: Self.catalogue)
        let groups = store.frames.flatMap(\.variants).flatMap(\.categories).flatMap(\.groups).filter(\.isScraped)
        for group in groups {
            let url = try #require(store.amayamaURL(for: group), "\(group.id)")
            #expect(url.host == "www.amayama.com")
            #expect(url.path.hasSuffix("/\(group.code)"), "\(group.id): \(url)")
        }
        // A group whose diagrams come from Megazip (Amayama's H80 page lists no parts) still links to Amayama.
        let megazipOnly = try #require(groups.first { $0.code == "H80" && $0.primarySite == "megazip" })
        #expect(store.amayamaURL(for: megazipOnly)?.path.hasSuffix("/misc/H80") == true)
    }

    @Test @MainActor func missingDiagramIsNil() throws {
        let store = CatalogueStore(folder: Self.catalogue)
        let group = try #require(store.frames.flatMap(\.variants).flatMap(\.categories).flatMap(\.groups).first { $0.isScraped })
        #expect(store.image(named: "nope/missing.png", for: group) == nil)
    }
}
