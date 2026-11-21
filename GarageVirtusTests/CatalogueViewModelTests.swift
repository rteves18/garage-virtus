import Foundation
import GarageVirtusKit
import Testing
@testable import GarageVirtus

@MainActor
struct CatalogueViewModelTests {
    @Test func missingCatalogueSaysNoneFound() {
        #expect(CatalogueViewModel(store: CatalogueStore(folder: nil)).emptyState == .noCatalogue)
    }

    @Test func emptyCatalogueSaysNoneFound() throws {
        let catalogue = try TestCatalogue()
        let store = CatalogueStore(folder: try catalogue.makeEmptyFolder())
        #expect(CatalogueViewModel(store: store).emptyState == .noCatalogue)
    }

    @Test func loadedCatalogueShowsSummary() throws {
        let catalogue = try TestCatalogue()
        let model = CatalogueViewModel(store: catalogue.store)
        #expect(model.emptyState == .ready(summary: "1 of 1 groups scraped · \(catalogue.store.indexedPartCount) part numbers"))
    }

    @Test func defaultStoreReadsCatalogueBundledInApp() async throws {
        let bundled = try #require(Bundle.main.url(forResource: "catalogue", withExtension: nil))
        let model = CatalogueViewModel()
        #expect(model.store.root == bundled)
        await model.load()
        #expect(model.store.hasCatalogue)
    }

    @Test func catalogueShowsLoadingUntilLoaded() async throws {
        let model = CatalogueViewModel()
        #expect(model.emptyState == .loading)
        await model.load()
        #expect(model.emptyState != .loading)
    }

    @Test func searchFindsPartsByPartialNumber() throws {
        let model = CatalogueViewModel(store: try TestCatalogue().store)
        model.search = "50F5"
        #expect(model.partHits.isEmpty == false)
        #expect(model.partHits.allSatisfy { CatalogueStore.normalize($0.oem).contains("50F5") })
    }

    @Test func searchNarrowsSidebarGroups() throws {
        let catalogue = try TestCatalogue()
        let model = CatalogueViewModel(store: catalogue.store)
        let variant = try #require(catalogue.store.frames.first?.variants.first)
        model.search = "bearing"
        #expect(model.visibleCategories(for: variant).flatMap(\.groups).map(\.code) == ["101"])
        model.search = "gearbox"
        #expect(model.visibleCategories(for: variant).isEmpty)
    }

    @Test func unscrapedGroupsShowOnlyWhenAsked() throws {
        let catalogue = try TestCatalogue()
        let unscraped = catalogue.folder.appendingPathComponent(
            "nissan/180sx/KRPS13/6976_1994-1998_TYPE-RX_MT_4WS/engine/102_Cylinder-head", isDirectory: true)
        try FileManager.default.createDirectory(at: unscraped, withIntermediateDirectories: true)
        let store = CatalogueStore(folder: catalogue.folder)
        let model = CatalogueViewModel(store: store)
        let variant = try #require(store.frames.first?.variants.first)
        #expect(model.visibleCategories(for: variant).flatMap(\.groups).map(\.code) == ["101"])
        model.showUnscraped = true
        #expect(model.visibleCategories(for: variant).flatMap(\.groups).map(\.code) == ["101", "102"])
    }

    @Test func openingPartRefSelectsGroupAndSetsFocus() throws {
        let catalogue = try TestCatalogue()
        let model = CatalogueViewModel(store: catalogue.store)
        let ref = try #require(catalogue.store.refs(for: "10102-50FR2").first)
        model.open(ref)
        #expect(model.selection == ref.groupID)
        #expect(model.focus?.groupID == ref.groupID)
        #expect(model.focus?.pnc == "R10102")
        #expect(model.focus?.oem == "10102-50FR2")
    }

}
