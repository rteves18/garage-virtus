import Foundation
import SwiftData
import Testing
@testable import GarageVirtusKit

/// The MCP server's tools, run against a temporary catalogue (group 101 fixture) and an in-memory garage.
@MainActor
struct GarageToolsTests {
    let space: TempSpace
    let garage: GarageStore
    let tools: GarageTools

    init() throws {
        space = try TempSpace()
        garage = GarageStore(container: try GarageStore.makeContainer(isStoredInMemoryOnly: true))
        tools = GarageTools(catalogue: CatalogueStore(folder: try space.makeCatalogue()), garage: garage)
    }

    private func json(_ text: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    @Test func searchFindsPartAndItsGroup() throws {
        let result = try json(tools.searchParts(query: "10102-50FR2"))
        let hits = try #require(result["results"] as? [[String: Any]])
        #expect(hits.first?["group_code"] as? String == "101")
        #expect(hits.first?["pnc"] as? String == "R10102")
    }

    @Test func listGroupsMarksScrapedGroups() throws {
        let groups = try #require(try json(tools.listGroups(category: nil))["groups"] as? [[String: Any]])
        #expect(groups.map { $0["code"] as? String } == ["101"])
        #expect(groups.first?["scraped"] as? Bool == true)
    }

    @Test func sectionWithYearKeepsOnlyMatchingDiagrams() throws {
        let section = try json(tools.section(groupCode: "101", year: "1995"))
        let schemas = try #require(section["diagrams"] as? [[String: Any]])
        #expect(schemas.map { $0["id"] as? String } == ["101B_001_1"])
    }

    @Test func sectionWithoutYearKeepsEveryDiagram() throws {
        let schemas = try #require(try json(tools.section(groupCode: "101", year: nil))["diagrams"] as? [[String: Any]])
        #expect(schemas.count == 2)
    }

    @Test func sectionShowsGarageCoverage() throws {
        garage.markWanted(oemNumber: "10102-50FR2", name: "engine assembly", status: .need, quantity: 2)
        let text = try tools.section(groupCode: "101", year: "1997")
        #expect(text.contains("\"need\" : 2"))
    }

    @Test func unknownGroupIsAnError() {
        #expect(throws: GarageTools.Failure.unknownGroup("999")) { try tools.section(groupCode: "999", year: nil) }
    }

    @Test func partsListIsPricedFromTheCatalogue() throws {
        let list = try json(tools.buildPartsList(title: "Engine", items: [.init(oem: "10102-50FR2", quantity: 2, reason: nil)]))
        #expect(list["total"] as? String == "7479.1")
        #expect((list["lines"] as? [[String: Any]])?.first?["name"] as? String == "engine assembly, bear rebuilt")
    }

    @Test func addingToGarageRecordsNeedsForTheCurrentCar() throws {
        let result = try json(tools.addToGarage(items: [.init(oem: "10102-50FR2", quantity: 1, reason: nil)], status: .need))
        #expect(result["added"] as? Int == 1)
        let rows = garage.parts(withOEMKey: "1010250FR2")
        #expect(rows.first?.status == .need)
        #expect(rows.first?.name == "engine assembly, bear rebuilt")
    }

    @Test func addingOwnedStatusIsRejected() {
        #expect(throws: GarageTools.Failure.statusNotAllowed("installed")) {
            try tools.addToGarage(items: [], status: .installed)
        }
    }

    @Test func garageStatusCountsAndShortNeeds() throws {
        garage.markWanted(oemNumber: "10102-50FR2", name: "engine", status: .need, quantity: 2)
        garage.addOwned(oemNumber: "10102-50FR2", name: "engine", quantity: 1)
        let status = try json(tools.garageStatus())
        #expect((status["counts"] as? [String: Int])?["need"] == 1)
        let short = try #require(status["still_short"] as? [[String: Any]])
        #expect(short.first?["short"] as? Int == 1)
    }
}
