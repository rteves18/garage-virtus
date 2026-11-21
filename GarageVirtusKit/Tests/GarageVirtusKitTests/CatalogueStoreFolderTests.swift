import Foundation
import Testing
@testable import GarageVirtusKit

@MainActor
struct CatalogueStoreFolderTests {
    let space: TempSpace

    init() throws { space = try TempSpace() }

    @Test func noSavedFolderMeansNoRoot() {
        let store = CatalogueStore(folderAccess: space.makeAccess())
        #expect(store.root == nil)
        #expect(store.hasCatalogue == false)
    }

    @Test func openingCatalogueFolderLoadsTree() throws {
        let store = CatalogueStore(folderAccess: space.makeAccess())
        try store.open(folder: try space.makeCatalogue())
        #expect(store.hasCatalogue)
        #expect(store.scrapedCount == 1)
        #expect(store.frames.first?.title == "Nissan 180SX KRPS13")
    }

    @Test func wrongFolderShowsNoCatalogueFound() throws {
        let store = CatalogueStore(folderAccess: space.makeAccess())
        try store.open(folder: try space.makeFolder("empty"))
        #expect(store.root != nil)
        #expect(store.hasCatalogue == false)
    }

    @Test func reopenedStoreRestoresFolder() throws {
        try CatalogueStore(folderAccess: space.makeAccess()).open(folder: try space.makeCatalogue())
        #expect(CatalogueStore(folderAccess: space.makeAccess()).hasCatalogue)
    }
}
