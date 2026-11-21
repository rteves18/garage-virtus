import Foundation
import GarageVirtusKit
import Testing
@testable import GarageVirtus

@MainActor
struct GroupDetailViewModelTests {
    let catalogue: TestCatalogue
    let model: GroupDetailViewModel

    init() throws {
        catalogue = try TestCatalogue()
        model = GroupDetailViewModel(group: try catalogue.group, store: catalogue.store)
        model.load()
    }

    private func focus(schemaId: String?, pnc: String?, oem: String?, groupID: String? = nil) throws -> PartFocus {
        PartFocus(groupID: try groupID ?? catalogue.group.id, schemaId: schemaId, pnc: pnc, oem: oem)
    }

    @Test func loadReadsSchemas() {
        #expect(model.file?.schemas.count == 2)
        #expect(model.schema?.id == "101B_001_0")
        #expect(model.title == "101 · Bearing and short engine assembly")
    }

    @Test func focusPicksSchemaCalloutAndPart() throws {
        model.showInspector = false
        model.apply(try focus(schemaId: "101B_001_1", pnc: "R10102", oem: "10102-50FR2"))
        #expect(model.schemaIndex == 1)
        #expect(model.selectedPNC == "R10102")
        #expect(model.highlightedOEM == "10102-50FR2")
        #expect(model.showInspector)
    }

    @Test func focusForAnotherGroupIsIgnored() throws {
        model.apply(try focus(schemaId: "101B_001_1", pnc: "R10102", oem: "10102-50FR2", groupID: "/elsewhere"))
        #expect(model.schemaIndex == 0)
        #expect(model.selectedPNC == nil)
    }

    @Test func changingSchemaKeepsCalloutItAlsoHas() {
        model.selectedPNC = "10103"
        model.schemaIndex = 1
        #expect(model.selectedPNC == "10103")
    }

    @Test func changingSchemaClearsCalloutItDoesNotHave() {
        model.selectedPNC = "NOT-ON-SCHEMA"
        model.schemaIndex = 1
        #expect(model.selectedPNC == nil)
    }

    @Test func selectingCalloutWithoutHighlightedPartClearsHighlight() throws {
        model.apply(try focus(schemaId: "101B_001_0", pnc: "R10102", oem: "10102-50FR2"))
        model.selectedPNC = "10103"
        #expect(model.highlightedOEM == nil)
    }

    @Test func selectingCalloutWithHighlightedPartKeepsHighlight() throws {
        model.apply(try focus(schemaId: "101B_001_0", pnc: "10102", oem: "10102-50FM2"))
        model.selectedPNC = "R10102"   // also lists 10102-50FM2, as a replacement
        #expect(model.highlightedOEM == "10102-50FM2")
    }

    @Test func selectingCalloutOpensInspector() {
        model.showInspector = false
        model.selectedPNC = "10102"
        #expect(model.showInspector)
    }

    @Test func vehicleSummaryNamesModelAndFrame() {
        #expect(model.vehicleSummary.hasPrefix("180SX KRPS13"))
    }


    @Test func labelDescribesEngineAndPeriod() throws {
        let schema = try #require(model.file?.schemas.last)
        #expect(model.label(for: schema) == "Schema 2 · SR20DET · 1994-01 – 1998-12")
    }



    @Test func selectingCalloutOnAnotherSchemaMakesItCurrent() {
        model.selectCallout("R10102", inSchemaAt: 1)
        #expect(model.schemaIndex == 1)
        #expect(model.selectedPNC == "R10102")
    }

    @Test func scrollingToSchemaMakesItCurrent() {
        model.currentSchemaID = "101B_001_1"
        #expect(model.schemaIndex == 1)
        #expect(model.currentSchemaID == "101B_001_1")
    }

    @Test func scrollingToUnknownSchemaKeepsCurrent() {
        model.currentSchemaID = "not-a-schema"
        #expect(model.schemaIndex == 0)
    }

    @Test func calloutIsHighlightedOnlyOnCurrentSchema() {
        model.selectCallout("10102", inSchemaAt: 1)
        #expect(model.isSelected("10102", inSchemaAt: 1))
        #expect(model.isSelected("10102", inSchemaAt: 0) == false)
    }

    @Test func yearWindowsComeFromSchemaDateRanges() {
        #expect(model.yearWindows.map(\.title) == ["01.1991 – 01.1994", "01.1994 – 12.1998"])
    }

    @Test func noYearWindowShowsEverySchema() {
        #expect(model.visibleSchemas.map(\.schema.id) == ["101B_001_0", "101B_001_1"])
    }

    @Test func yearWindowShowsOnlyOverlappingSchemas() throws {
        let window = try #require(model.yearWindows.last)
        model.selectedYearWindow = window
        #expect(model.visibleSchemas.map(\.schema.id) == ["101B_001_1"])
        #expect(model.visibleSchemas.map(\.index) == [1])
    }

    @Test func yearWindowMovesCurrentSchemaIntoView() throws {
        let window = try #require(model.yearWindows.last)
        model.selectedYearWindow = window
        #expect(model.schemaIndex == 1)
    }

    @Test func buildMonthPicksWindowContainingIt() {
        model.selectYearWindow(containing: "1995-03")
        #expect(model.selectedYearWindow?.title == "01.1994 – 12.1998")
    }

    @Test func buildMonthOutsideEveryWindowShowsAllYears() {
        model.selectYearWindow(containing: "1985-01")
        #expect(model.selectedYearWindow == nil)
    }

    @Test func jumpToHiddenSchemaShowsAllYears() throws {
        let window = try #require(model.yearWindows.last)
        model.selectedYearWindow = window
        model.apply(try focus(schemaId: "101B_001_0", pnc: "10102", oem: "10102-50F50"))
        #expect(model.selectedYearWindow == nil)
        #expect(model.schemaIndex == 0)
    }
}
