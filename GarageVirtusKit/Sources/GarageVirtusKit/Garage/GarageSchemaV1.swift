import Foundation
import SwiftData

/// Version 1 of the garage store. Later changes add GarageSchemaV2 and a migration stage.
public enum GarageSchemaV1: VersionedSchema {
    public static let versionIdentifier = SwiftData.Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] { [Car.self, GaragePart.self, PartPhoto.self] }

    /// One of Ryan's cars. The 180SX is created on first launch.
    @Model
    public final class Car {
        public var id: UUID
        public var name: String
        public var frame: String
        public var variantID: String
        public var createdAt: Date
        public var updatedAt: Date
        @Relationship(deleteRule: .cascade, inverse: \GaragePart.car)
        public var parts: [GaragePart] = []

        public init(name: String, frame: String, variantID: String) {
            id = UUID()
            self.name = name
            self.frame = frame
            self.variantID = variantID
            createdAt = .now
            updatedAt = .now
        }
    }

    /// One tracked part: a need or want (one per part number), or an owned purchase or bundle (any number).
    @Model
    public final class GaragePart {
        public var id: UUID
        public var createdAt: Date
        public var updatedAt: Date

        public var name: String
        /// As shown in the catalogue, e.g. "10102-50FR2". Nil for parts with no catalogue entry.
        public var oemNumber: String?
        /// `CatalogueStore.normalize(oemNumber)`, e.g. "1010250FR2", for lookups.
        public var oemKey: String?
        public var quantity: Int
        public var notes: String

        /// Stored as a string so predicates filter on real stored data. Use `status`.
        public var statusRaw: String

        /// Price paid for this row as a whole (the purchase or bundle).
        public var cost: Decimal?
        public var currency: String
        public var seller: String?
        public var sellerURL: String?
        public var purchasedOn: Date?
        /// Stored as a string. Use `condition`.
        public var conditionRaw: String?
        public var storageLocation: String?

        public var targetPrice: Decimal?
        public var linkURL: String?

        /// Where it was marked from in the catalogue.
        public var groupCode: String?
        public var pnc: String?

        public var car: Car?
        @Relationship(deleteRule: .cascade, inverse: \PartPhoto.part)
        public var photos: [PartPhoto] = []

        public init(name: String, oemNumber: String?, status: PartStatus, quantity: Int) {
            id = UUID()
            createdAt = .now
            updatedAt = .now
            self.name = name
            self.oemNumber = oemNumber
            oemKey = oemNumber.map(CatalogueStore.normalize)
            self.quantity = quantity
            notes = ""
            statusRaw = status.rawValue
            currency = "USD"
        }

        public var status: PartStatus {
            get { PartStatus(rawValue: statusRaw) ?? .need }
            set { statusRaw = newValue.rawValue }
        }

        public var condition: PartCondition? {
            get { conditionRaw.flatMap(PartCondition.init(rawValue:)) }
            set { conditionRaw = newValue?.rawValue }
        }
    }

    /// A photo of an owned part. SwiftData may keep the bytes in a file next to the store.
    @Model
    public final class PartPhoto {
        public var id: UUID
        @Attribute(.externalStorage) public var imageData: Data
        public var createdAt: Date
        public var part: GaragePart?

        public init(imageData: Data) {
            id = UUID()
            self.imageData = imageData
            createdAt = .now
        }
    }
}

public typealias Car = GarageSchemaV1.Car
public typealias GaragePart = GarageSchemaV1.GaragePart
public typealias PartPhoto = GarageSchemaV1.PartPhoto
