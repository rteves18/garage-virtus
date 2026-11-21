import Testing
@testable import GarageVirtusKit

struct CatalogueStoreParsingTests {
    @Test(arguments: [
        ("10102-50FR2", "1010250FR2"),
        ("1010250fr2", "1010250FR2"),
        (" 10102 50fr2 ", "1010250FR2"),
    ])
    func normalizeStripsPunctuationAndUppercases(input: String, expected: String) {
        #expect(CatalogueStore.normalize(input) == expected)
    }

    @Test func splitCodeNameReadsGroupFolder() {
        let (code, name) = CatalogueStore.splitCodeName("101_Bearing-and-short-engine-assembly")
        #expect(code == "101")
        #expect(name == "Bearing and short engine assembly")
    }

    @Test func splitCodeNameReadsVariantFolder() {
        let (code, name) = CatalogueStore.splitCodeName("6976_1994-1998_TYPE-RX_MT_4WS")
        #expect(code == "6976")
        #expect(name == "1994-1998 TYPE-RX MT 4WS")
    }

    @Test func splitCodeNameWithoutUnderscoreReturnsFolderTwice() {
        let (code, name) = CatalogueStore.splitCodeName("engine")
        #expect(code == "engine")
        #expect(name == "engine")
    }

    @Test func parsesAmayamaPartURLWithSchemaAndCallout() throws {
        let parsed = try #require(CatalogueStore.parseAmayamaPartURL(
            "https://www.amayama.com/en/part/nissan/1010250fr2?sid=101B_001_1.R10102"))
        #expect(parsed.oem == "1010250fr2")
        #expect(parsed.schemaId == "101B_001_1")
        #expect(parsed.pnc == "R10102")
    }

    @Test func parsesAmayamaPartURLWithoutSid() throws {
        let parsed = try #require(CatalogueStore.parseAmayamaPartURL(
            "https://www.amayama.com/en/part/nissan/1010250fr2"))
        #expect(parsed.oem == "1010250fr2")
        #expect(parsed.schemaId == nil)
        #expect(parsed.pnc == nil)
    }

    @Test(arguments: [
        "https://example.com/en/part/nissan/1010250fr2",
        "10102-50FR2",
        "https://www.amayama.com/en/genuine-catalogs/nissan",
    ])
    func rejectsNonAmayamaPartURLs(input: String) {
        #expect(CatalogueStore.parseAmayamaPartURL(input) == nil)
    }
}
