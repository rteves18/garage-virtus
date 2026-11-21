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

    @Test func noOwnedMeansFullyShort() {
        store.markWanted(oemNumber: "16600-1", name: "Injector", status: .need, quantity: 4)
        #expect(store.coverage(forOEMKey: "166001") == Coverage(needed: 4, owned: 0))
    }

    @Test func markBoughtKeepsNeedAndCoversIt() {
        let need = store.markWanted(oemNumber: "16600-1", name: "Injector", status: .need, quantity: 4)
        let bought = store.markBought(need, quantity: 2)
        #expect(need.status == .need)
        #expect(bought.status == .inStorage)
        #expect(bought.oemNumber == "16600-1")
        #expect(store.coverage(forOEMKey: "166001").short == 2)
    }

    @Test func installedCountsAsOwned() {
        store.markWanted(oemNumber: "A-1", name: "a", status: .need, quantity: 1)
        store.addOwned(oemNumber: "A-1", name: "a", status: .installed)
        #expect(store.coverage(forOEMKey: "A1").short == 0)
    }

    @Test func overCoveredNeedIsNotShort() {
        store.markWanted(oemNumber: "B-1", name: "b", status: .need, quantity: 4)
        store.addOwned(oemNumber: "B-1", name: "b", quantity: 5)
        #expect(store.coverage(forOEMKey: "B1") == Coverage(needed: 4, owned: 5))
        #expect(store.coverage(forOEMKey: "B1").short == 0)
    }

    @Test func partWithoutOEMIsIgnoredByCoverage() {
        store.markWanted(oemNumber: "C-1", name: "c", status: .need, quantity: 1)
        store.addOwned(oemNumber: nil, name: "custom", quantity: 3)
        #expect(store.coverage(forOEMKey: "C1").owned == 0)
    }

    @Test func summaryCountsRowsAndSumsOwnedCost() {
        let a = store.addOwned(oemNumber: nil, name: "a")
        a.cost = 80
        let b = store.addOwned(oemNumber: nil, name: "b", status: .installed)
        b.cost = Decimal(string: "20.5")
        let w = store.markWanted(oemNumber: "W-1", name: "w", status: .want)
        w.targetPrice = 999
        store.save()
        let summary = store.summary()
        #expect(summary.totalSpent == Decimal(string: "100.5"))
        #expect(summary.counts[.inStorage] == 1)
        #expect(summary.counts[.want] == 1)
    }

    @Test func deletingPartDeletesPhotos() throws {
        let part = store.addOwned(oemNumber: nil, name: "p")
        store.addPhoto(Data([1, 2, 3]), to: part)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<PartPhoto>()) == 1)
        store.delete(part)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<PartPhoto>()) == 0)
    }

    @Test func addedCarsAreListedByCreation() {
        let first = store.defaultCar()
        let s2000 = store.addCar(name: "2005 Honda S2000", frame: "AP2", variantID: "")
        #expect(store.cars().map(\.id) == [first.id, s2000.id])
    }

    @Test func newPartsBelongToTheCurrentCar() {
        let s2000 = store.addCar(name: "2005 Honda S2000", frame: "AP2", variantID: "")
        store.currentCar = s2000
        #expect(store.addOwned(oemNumber: nil, name: "Soft top").car?.id == s2000.id)
        #expect(store.markWanted(oemNumber: "X-1", name: "x", status: .need).car?.id == s2000.id)
    }

    @Test func needsAreTrackedPerCar() {
        store.markWanted(oemNumber: "X-1", name: "x", status: .need, quantity: 1)
        store.currentCar = store.addCar(name: "4Runner", frame: "UZN215", variantID: "")
        store.markWanted(oemNumber: "X-1", name: "x", status: .need, quantity: 3)
        #expect(store.parts(withOEMKey: "X1").count == 2)
    }

    @Test func deletingCarDeletesItsParts() throws {
        let car = store.addCar(name: "Model 3", frame: "", variantID: "")
        store.currentCar = car
        store.addOwned(oemNumber: nil, name: "Floor mats")
        store.delete(car)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<GaragePart>()) == 0)
        #expect(store.currentCar?.id == store.defaultCar().id)
    }
}
