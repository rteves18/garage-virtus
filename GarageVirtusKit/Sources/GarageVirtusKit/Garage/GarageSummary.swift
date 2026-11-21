import Foundation

/// How many of a needed part number Ryan has against how many he needs.
public struct Coverage: Equatable, Sendable {
    public let needed: Int
    public let owned: Int

    public init(needed: Int, owned: Int) {
        self.needed = needed
        self.owned = owned
    }

    public var short: Int { max(0, needed - owned) }
}

/// Rows per status and what owned parts have cost.
public struct GarageSummary: Equatable, Sendable {
    public let counts: [PartStatus: Int]
    /// Sum of `cost` over owned rows (each row's cost is what was paid for that purchase or bundle).
    public let totalSpent: Decimal
}
