import Foundation
import SwiftData
import Testing
@testable import GarageVirtusKit

/// get_section / search_parts / build_parts_list across sources: group 101 has amayama.json (real prices) and
/// megazip.json (10102-50FR2 priced at 1.00, so the two are easy to tell apart).
@MainActor
struct GarageToolsSourceTests {
    let space: TempSpace
    let tools: GarageTools

    init() throws {
        space = try TempSpace()
        let catalogue = try space.makeCatalogue()
        let group = catalogue.appendingPathComponent(
            "nissan/180sx/KRPS13/6976_1994-1998_TYPE-RX_MT_4WS/engine/101_Bearing-and-short-engine-assembly")
        let legacy = group.appendingPathComponent("schema-group.json")
        let original = try JSONSerialization.jsonObject(with: Data(contentsOf: legacy)) as! [String: Any]
        try Self.write(original, site: "amayama", to: group.appendingPathComponent("amayama.json"), priceFR2: nil)
        try Self.write(original, site: "megazip", to: group.appendingPathComponent("megazip.json"), priceFR2: 1.0)
        try FileManager.default.removeItem(at: legacy)
        let garage = GarageStore(container: try GarageStore.makeContainer(isStoredInMemoryOnly: true))
        tools = GarageTools(catalogue: CatalogueStore(folder: catalogue), garage: garage)
    }

    /// Writes a copy of the group file as `site`, optionally repricing every 10102-50FR2 listing.
    static func write(_ original: [String: Any], site: String, to url: URL, priceFR2: Double?) throws {
        var file = original
        var source = file["source"] as! [String: Any]
        source["site"] = site
        file["source"] = source
        if let priceFR2 {
            file = reprice(file, oem: "10102-50FR2", amount: priceFR2) as! [String: Any]
        }
        try JSONSerialization.data(withJSONObject: file).write(to: url)
    }

    static func reprice(_ value: Any, oem: String, amount: Double) -> Any {
        if var object = value as? [String: Any] {
            if object["oem"] as? String == oem, var price = object["price"] as? [String: Any] {
                price["amount"] = amount
                price["status"] = "Available"
                object["price"] = price
            }
            return object.mapValues { reprice($0, oem: oem, amount: amount) }
        }
        if let array = value as? [Any] { return array.map { reprice($0, oem: oem, amount: amount) } }
        return value
    }

    private func json(_ text: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    @Test func sectionDefaultsToPrimarySource() throws {
        let section = try json(tools.section(groupCode: "101", year: nil, source: nil))
        #expect(section["source"] as? String == "amayama")
        #expect(section["available_sources"] as? [String] == ["amayama", "megazip"])
    }

    @Test func sectionShowsRequestedSource() throws {
        let section = try json(tools.section(groupCode: "101", year: nil, source: "megazip"))
        #expect(section["source"] as? String == "megazip")
        #expect(try tools.section(groupCode: "101", year: nil, source: "megazip").contains("\"price\" : 1"))
    }

    @Test func unknownSourceIsAnError() {
        #expect(throws: GarageTools.Failure.unknownSource("rockauto", available: ["amayama", "megazip"])) {
            try tools.section(groupCode: "101", year: nil, source: "rockauto")
        }
    }

    @Test func searchListsEachSourceForAPart() throws {
        let hits = try #require(try json(tools.searchParts(query: "10102-50FR2"))["results"] as? [[String: Any]])
        #expect(Set(hits.compactMap { $0["source"] as? String }) == ["amayama", "megazip"])
    }

    @Test func partsListDefaultsToPrimaryPrices() throws {
        let list = try json(tools.buildPartsList(title: "x", items: [.init(oem: "10102-50FR2", quantity: 2, reason: nil)], source: nil))
        #expect(list["total"] as? String == "7479.1")
        #expect(list["source"] as? String == "amayama")
    }

    @Test func partsListUsesRequestedSourcePrices() throws {
        let list = try json(tools.buildPartsList(title: "x", items: [.init(oem: "10102-50FR2", quantity: 2, reason: nil)], source: "megazip"))
        #expect(list["total"] as? String == "2")
        #expect(list["source"] as? String == "megazip")
    }
}
