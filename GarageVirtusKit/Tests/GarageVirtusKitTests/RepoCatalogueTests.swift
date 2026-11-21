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

    @Test func everySchemaGroupDecodesWithItsImages() throws {
        let files = Self.files { $0.lastPathComponent == "schema-group.json" }
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
        let image: CGImage = try #require(store.image(named: "imgjp16/RS13/101B_001.png", for: group))
        #expect(image.width == 1280)
        #expect(image.height == 639)
    }

    @Test @MainActor func missingDiagramIsNil() throws {
        let store = CatalogueStore(folder: Self.catalogue)
        let group = try #require(store.frames.flatMap(\.variants).flatMap(\.categories).flatMap(\.groups).first { $0.isScraped })
        #expect(store.image(named: "nope/missing.png", for: group) == nil)
    }
}
