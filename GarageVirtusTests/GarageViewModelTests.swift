import Foundation
import GarageVirtusKit
import SwiftData
import Testing
@testable import GarageVirtus

@MainActor
struct GarageViewModelTests {
    let store: GarageStore
    let model = GarageViewModel()

    init() throws {
        store = GarageStore(container: try GarageStore.makeContainer(isStoredInMemoryOnly: true))
    }

    @Test func selectingPartStoresItsID() {
        let part = store.addOwned(oemNumber: nil, name: "Seat")
        model.select(part)
        #expect(model.selectedPartID == part.id)
    }

    @Test func clearingSelectionForgetsPart() {
        model.select(store.addOwned(oemNumber: nil, name: "Seat"))
        model.clearSelection()
        #expect(model.selectedPartID == nil)
    }
}
