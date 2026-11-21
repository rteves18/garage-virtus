import Foundation
import SwiftData
import Testing
@testable import GarageVirtusKit

@MainActor
struct GarageStoreTests {
    let container: ModelContainer
    let store: GarageStore

    init() throws {
        container = try GarageStore.makeContainer(isStoredInMemoryOnly: true)
        store = GarageStore(container: container)
    }

    @Test func defaultCarIsCreatedOnce() {
        #expect(store.defaultCar().id == store.defaultCar().id)
        #expect(store.defaultCar().frame == "KRPS13")
    }

    @Test func markingNeedTwiceUpdatesOneRow() {
        store.markWanted(oemNumber: "10102-50FR2", name: "Engine assembly", status: .need, quantity: 1)
        let row = store.markWanted(oemNumber: "1010250fr2", name: "Engine assembly", status: .want, quantity: 2)
        #expect(store.parts(withOEMKey: "1010250FR2").count == 1)
        #expect(row.status == .want)
        #expect(row.quantity == 2)
    }

    @Test func addingOwnedTwiceCreatesTwoRows() {
        store.addOwned(oemNumber: "08911-6401A", name: "Nut-Hex", quantity: 10)
        store.addOwned(oemNumber: "08911-6401A", name: "Nut-Hex", quantity: 4)
        #expect(store.parts(withOEMKey: "089116401A").map(\.quantity).sorted() == [4, 10])
    }

    @Test func setStatusMovesOwnedPartToInstalled() {
        let part = store.addOwned(oemNumber: nil, name: "Seat")
        store.setStatus(.installed, for: part)
        #expect(part.status == .installed)
    }

    @Test func partsAreStoredWithOEMKey() {
        #expect(store.addOwned(oemNumber: "10102-50FR2", name: "Engine assembly").oemKey == "1010250FR2")
    }
}
