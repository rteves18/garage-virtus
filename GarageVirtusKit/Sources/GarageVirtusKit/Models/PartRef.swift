import Foundation

/// One place an OEM number appears in the catalogue.
public struct PartRef: Identifiable, Hashable, Sendable {
    public var id: String { "\(site)|\(groupID)|\(schemaId)|\(pnc)|\(oem)|\(replacementOf ?? "")" }
    /// The source site this listing comes from, e.g. "amayama".
    public let site: String
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
    /// The site's catalogue price for this listing.
    public let price: Price
    /// The part's page on that site, if the catalogue links one.
    public let partURL: String?
}
