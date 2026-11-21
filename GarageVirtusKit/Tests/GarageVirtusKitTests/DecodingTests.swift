import CoreGraphics
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

    @Test(arguments: [("amayama", "Amayama"), ("megazip", "Megazip")])
    func sourceNamesTheSiteForLinks(site: String, expected: String) {
        #expect(Source(site: site, url: "https://example.com", scrapedAt: nil).siteName == expected)
    }

    @Test(arguments: [(0.62, 0.23, "10102"), (0.62, 0.26, "R10102"), (0.25, 0.37, "10103")])
    func pointInsideHotspotFindsCallout(x: Double, y: Double, pnc: String) throws {
        let schema = try decode(SchemaGroupFile.self, "schema-group").schemas[0]
        #expect(schema.callout(at: CGPoint(x: x, y: y))?.pnc == pnc)
    }

    @Test func pointJustOutsideHotspotWithinToleranceFindsCallout() throws {
        let schema = try decode(SchemaGroupFile.self, "schema-group").schemas[0]
        #expect(schema.callout(at: CGPoint(x: 0.2290, y: 0.37), tolerance: 0.002)?.pnc == "10103")
    }

    @Test func pointAwayFromHotspotsFindsNothing() throws {
        let schema = try decode(SchemaGroupFile.self, "schema-group").schemas[0]
        #expect(schema.callout(at: CGPoint(x: 0.9, y: 0.9)) == nil)
    }

    private func callout(pnc: String, oems: [String]) throws -> Callout {
        let parts = oems.map { #"{"oem": "\#($0)", "applies": [], "details": {}, "price": {"currency": "USD"}, "replacements": []}"# }
        let json = #"{"pnc": "\#(pnc)", "hotspots": [], "parts": [\#(parts.joined(separator: ","))]}"#
        return try CatalogueStore.makeDecoder().decode(Callout.self, from: Data(json.utf8))
    }

    @Test func labelMatchingEveryPartNumberIsRedundant() throws {
        #expect(try callout(pnc: "089116401A", oems: ["08911-6401A"]).isLabelledByPartNumber)
    }

    @Test(arguments: [("10102", ["10102-50F50", "10102-50F52"]), ("089116401A", ["08911-6401A", "08911-6401B"])])
    func labelDifferentFromAnyPartNumberIsKept(pnc: String, oems: [String]) throws {
        #expect(try callout(pnc: pnc, oems: oems).isLabelledByPartNumber == false)
    }
}
