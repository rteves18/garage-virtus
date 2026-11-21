import Foundation
import Testing
@testable import GarageVirtusKit

@MainActor
struct CatalogueStoreFolderTests {
    let space: TempSpace

    init() throws { space = try TempSpace() }

    @Test func missingFolderMeansNoCatalogue() {
        let store = CatalogueStore(folder: nil)
        #expect(store.root == nil)
        #expect(store.hasCatalogue == false)
    }

    @Test func catalogueFolderLoadsTree() throws {
        let store = CatalogueStore(folder: try space.makeCatalogue())
        #expect(store.hasCatalogue)
        #expect(store.scrapedCount == 1)
        #expect(store.frames.first?.title == "Nissan 180SX KRPS13")
    }

    @Test func emptyFolderHasNoCatalogue() throws {
        let store = CatalogueStore(folder: try space.makeFolder("empty"))
        #expect(store.root != nil)
        #expect(store.hasCatalogue == false)
    }
}
