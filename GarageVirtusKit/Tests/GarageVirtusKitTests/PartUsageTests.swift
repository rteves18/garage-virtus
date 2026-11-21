import Foundation
import Testing
@testable import GarageVirtusKit

@MainActor
struct PartUsageTests {
    let space: TempSpace
    let store: CatalogueStore

    init() throws {
        space = try TempSpace()
        store = CatalogueStore(folderAccess: space.makeAccess())
        try store.open(folder: try space.makeCatalogue())
    }

    @Test func usedInListsOnlyDirectUses() {
        let usage = store.usage(of: "10102-50FR2")
        #expect(usage.usedIn.map(\.pnc) == ["R10102", "R10102"])
        #expect(usage.usedIn.allSatisfy { $0.replacementOf == nil })
    }

    @Test func replacesListsPartsThisNumberSupersedes() {
        #expect(store.usage(of: "1010250fr2").replaces == ["1010B-50F52"])
    }

    @Test func elsewhereSkipsTheLocalVariantAndGroup() throws {
        let usage = store.usage(of: "10102-50FR2")
        let page = try #require(usage.page)
        #expect(page.diagrams.count == 8)
        #expect(usage.elsewhere.count == 7)
        #expect(usage.elsewhere.contains { $0.variantId == "6976" && $0.group == "101" } == false)
    }

    @Test func partWithoutScrapedPageHasNoPageOrElsewhere() {
        let usage = store.usage(of: "10102-50F50")
        #expect(usage.page == nil)
        #expect(usage.elsewhere.isEmpty)
        #expect(usage.usedIn.count == 2)
    }
}
