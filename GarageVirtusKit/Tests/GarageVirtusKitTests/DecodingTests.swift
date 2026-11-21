import Foundation
import Testing
@testable import GarageVirtusKit

private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try CatalogueStore.makeDecoder().decode(type, from: Data(contentsOf: url))
}

struct DecodingTests {
    @Test func decodesSchemaGroupSample() throws {
        let file = try decode(SchemaGroupFile.self, "schema-group")
        #expect(file.vehicle.model == "180SX")
        #expect(file.vehicle.frame == "KRPS13")
        #expect(file.vehicle.variantId == "6976")
        #expect(file.group.code == "101")
        #expect(file.schemas.count == 2)
        let schema = file.schemas[0]
        #expect(schema.id == "101B_001_0")
        #expect(schema.image == "imgjp16/RS13/101B_001.png")
        #expect(schema.callouts.count == 3)
        #expect(schema.callouts[0].pnc == "10102")
        #expect(schema.callouts[0].parts.map(\.oem) == ["10102-50F50", "10102-50F52", "10102-50FM2"])
    }

    @Test func decodesPartPageSample() throws {
        let page = try decode(PartPage.self, "1010250FR2")
        #expect(page.oem == "10102-50FR2")
        #expect(page.key == "1010250FR2")
        #expect(page.name == "ENGINE ASSEMBLY, BEAR REBUILT")
        #expect(page.offers.count == 1)
        #expect(page.diagrams.count == 8)
    }
}
