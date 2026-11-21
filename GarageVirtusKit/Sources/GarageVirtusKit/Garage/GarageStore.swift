import Foundation
import Observation
import SwiftData

/// All writes to Ryan's garage records go through here, each followed by an explicit save.
@MainActor
@Observable
public final class GarageStore {
    @ObservationIgnored public let container: ModelContainer
    /// The car new parts are recorded against. Nil means the first car (the 180SX).
    public var currentCar: Car?
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

    /// Ryan's cars, oldest first.
    public func cars() -> [Car] {
        _ = defaultCar()
        return (try? context.fetch(FetchDescriptor<Car>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    @discardableResult
    public func addCar(name: String, frame: String, variantID: String) -> Car {
        _ = defaultCar()
        let car = Car(name: name, frame: frame, variantID: variantID)
        context.insert(car)
        save()
        return car
    }

    /// Deletes a car and every part recorded for it. The first remaining car becomes current.
    public func delete(_ car: Car) {
        if currentCar?.id == car.id { currentCar = nil }
        context.delete(car)
        save()
        currentCar = cars().first
    }

    /// The car parts are recorded against now.
    public var activeCar: Car { currentCar ?? defaultCar() }

    /// Records a part Ryan needs or wants. A part number has at most one need/want row; marking it again updates it.
    @discardableResult
    public func markWanted(oemNumber: String?, name: String, status: PartStatus, quantity: Int = 1,
                           groupCode: String? = nil, pnc: String? = nil) -> GaragePart {
        precondition(!status.isOwned, "markWanted takes .need or .want")
        let existing = oemNumber.flatMap { number in
            let carID = activeCar.id
            return parts(withOEMKey: CatalogueStore.normalize(number)).first { !$0.status.isOwned && $0.car?.id == carID }
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

    /// Records buying `quantity` of a needed or wanted part: a new owned row in storage. The need row stays, so
    /// coverage shows how much is still short.
    @discardableResult
    public func markBought(_ need: GaragePart, quantity: Int) -> GaragePart {
        addOwned(oemNumber: need.oemNumber, name: need.name, status: .inStorage, quantity: quantity,
                 groupCode: need.groupCode, pnc: need.pnc)
    }

    public func addPhoto(_ data: Data, to part: GaragePart) {
        let photo = PartPhoto(imageData: data)
        context.insert(photo)
        photo.part = part
        save(touching: part)
    }

    public func removePhoto(_ photo: PartPhoto) {
        context.delete(photo)
        save()
    }

    public func coverage(forOEMKey key: String) -> Coverage {
        Self.coverage(forOEMKey: key, in: parts(withOEMKey: key))
    }

    /// Coverage computed from rows already fetched (e.g. a view's `@Query`).
    public static func coverage(forOEMKey key: String, in parts: [GaragePart]) -> Coverage {
        let rows = parts.filter { $0.oemKey == key }
        let needed = rows.first { $0.status == .need }?.quantity ?? 0
        let owned = rows.filter(\.status.isOwned).reduce(0) { $0 + $1.quantity }
        return Coverage(needed: needed, owned: owned)
    }

    public func summary() -> GarageSummary {
        let rows = (try? context.fetch(FetchDescriptor<GaragePart>())) ?? []
        let counts = Dictionary(grouping: rows, by: \.status).mapValues(\.count)
        let spent = rows.filter(\.status.isOwned).compactMap(\.cost).reduce(Decimal.zero, +)
        return GarageSummary(counts: counts, totalSpent: spent)
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
        part.car = activeCar
        return part
    }
}
