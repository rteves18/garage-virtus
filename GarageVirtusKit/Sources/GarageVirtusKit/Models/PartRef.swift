import Foundation

/// One place an OEM number appears in the catalogue.
public struct PartRef: Identifiable, Hashable, Sendable {
    public var id: String { "\(groupID)|\(schemaId)|\(pnc)|\(oem)|\(replacementOf ?? "")" }
    public let oem: String
    public let groupID: String
    public let groupCode: String
    public let groupName: String
    public let variantId: String
    public let variantTitle: String
    public let schemaId: String
    public let schemaIndex: Int
    public let pnc: String
    public let calloutName: String
    /// Set when this OEM is listed as a replacement for another part number.
    public let replacementOf: String?
    public let priceText: String
}
