import Foundation
import Observation
import SwiftData

/// All writes to Ryan's garage records go through here, each followed by an explicit save.
@MainActor
@Observable
public final class GarageStore {
    @ObservationIgnored public let container: ModelContainer
    @ObservationIgnored private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    /// A container for the garage store: on disk in the app's container, or in memory for tests and previews.
    public static func makeContainer(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        try ModelContainer(for: SwiftData.Schema(versionedSchema: GarageSchemaV1.self),
                           migrationPlan: GarageMigrationPlan.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: isStoredInMemoryOnly))
    }

    /// The car parts are recorded against: the 180SX, created on first use.
    public func defaultCar() -> Car {
        if let car = try? context.fetch(FetchDescriptor<Car>(sortBy: [SortDescriptor(\.createdAt)])).first {
            return car
        }
        let car = Car(name: "1997 Nissan 180SX Type X", frame: "KRPS13", variantID: "6976")
        context.insert(car)
        save()
        return car
    }

    /// Records a part Ryan needs or wants. A part number has at most one need/want row; marking it again updates it.
    @discardableResult
    public func markWanted(oemNumber: String?, name: String, status: PartStatus, quantity: Int = 1,
                           groupCode: String? = nil, pnc: String? = nil) -> GaragePart {
        precondition(!status.isOwned, "markWanted takes .need or .want")
        let existing = oemNumber.flatMap { number in
            parts(withOEMKey: CatalogueStore.normalize(number)).first { !$0.status.isOwned }
        }
        let part = existing ?? insertPart(name: name, oemNumber: oemNumber, status: status, quantity: quantity,
                                          groupCode: groupCode, pnc: pnc)
        part.status = status
        part.quantity = quantity
        save(touching: part)
        return part
    }

    /// Records a part Ryan owns: always a new row (a new purchase or bundle), even for a part number he already has.
    @discardableResult
    public func addOwned(oemNumber: String?, name: String, status: PartStatus = .inStorage, quantity: Int = 1,
                         groupCode: String? = nil, pnc: String? = nil) -> GaragePart {
        precondition(status.isOwned, "addOwned takes an owned status")
        let part = insertPart(name: name, oemNumber: oemNumber, status: status, quantity: quantity,
                              groupCode: groupCode, pnc: pnc)
        save(touching: part)
        return part
    }

    public func setStatus(_ status: PartStatus, for part: GaragePart) {
        part.status = status
        save(touching: part)
    }

    public func delete(_ part: GaragePart) {
        context.delete(part)
        save()
    }

    /// Every row recorded for a part number (normalized key, e.g. "1010250FR2").
    public func parts(withOEMKey key: String) -> [GaragePart] {
        let descriptor = FetchDescriptor<GaragePart>(predicate: #Predicate { $0.oemKey == key },
                                                     sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Saves pending edits (editors call this after changing fields).
    public func save() {
        try? context.save()
    }

    public func save(touching part: GaragePart) {
        part.updatedAt = .now
        save()
    }

    private func insertPart(name: String, oemNumber: String?, status: PartStatus, quantity: Int,
                            groupCode: String?, pnc: String?) -> GaragePart {
        let part = GaragePart(name: name, oemNumber: oemNumber, status: status, quantity: quantity)
        part.groupCode = groupCode
        part.pnc = pnc
        context.insert(part)
        part.car = defaultCar()
        return part
    }
}
