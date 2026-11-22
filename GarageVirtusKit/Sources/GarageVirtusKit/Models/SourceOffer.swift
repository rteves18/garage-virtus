import Foundation

/// One source site's listing for an OEM number: its catalogue price, its part page (if scraped) and a link.
/// `CatalogueStore.offers(for:)` returns these primary first, so the first is what the app shows by default
/// and the rest are alternatives.
public struct SourceOffer: Identifiable {
    public var id: String { site }
    /// "amayama", "megazip", …
    public let site: String
    /// The site's catalogue price/status for this number (from the diagram listings).
    public let price: Price?
    /// The site's scraped part page, if any (offers, stock, delivery, notices).
    public let page: PartPage?
    /// The part's page on the site.
    public let url: String?

    /// "amayama" -> "Amayama".
    public var siteName: String { site.capitalized }

    /// Lowest offer price on the part page, else the catalogue price.
    public var bestAmount: Double? {
        page?.offers.compactMap(\.price).min() ?? price?.amount
    }
}
