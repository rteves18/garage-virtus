import Foundation

/// Everything the catalogue knows about one OEM number: where it's used, what it supersedes,
/// its scraped Amayama part page, and other Amayama pages listing it that aren't in this catalogue.
public struct PartUsage {
    /// Callouts that list this number directly (not as a replacement).
    public let usedIn: [PartRef]
    /// Part numbers this number replaces, sorted and unique.
    public let replaces: [String]
    /// The scraped Amayama part page, if one exists in `_parts/`.
    public let page: PartPage?
    /// Diagrams on Amayama listing this number whose variant and group aren't among `usedIn`.
    public let elsewhere: [PartPage.DiagramRef]
}
