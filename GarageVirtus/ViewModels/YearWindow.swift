import GarageVirtusKit

/// A span of production months ("YYYY-MM", start inclusive, end exclusive) between the points where a group's
/// schemas change. Used to filter schemas to one build period.
struct YearWindow: Hashable, Identifiable {
    let from: String
    let to: String

    var id: String { "\(from)|\(to)" }

    /// "01.1994 – 08.1996"
    var title: String { "\(Self.display(from)) – \(Self.display(to))" }

    /// True when `period` covers part of this window. Periods only touching at a boundary month don't overlap,
    /// because the boundary is where one schema replaces the other.
    func overlaps(_ period: Period) -> Bool {
        let start = period.from ?? Self.earliest
        let end = period.to ?? Self.latest
        return start < to && from < end
    }

    func contains(month: String) -> Bool {
        from <= month && month < to
    }

    /// Windows between every start and end month in `periods`, keeping only those some period covers.
    static func windows(for periods: [Period]) -> [YearWindow] {
        let bounds = Set(periods.flatMap { [$0.from ?? earliest, $0.to ?? latest] }).sorted()
        return zip(bounds, bounds.dropFirst())
            .map { YearWindow(from: $0, to: $1) }
            .filter { window in periods.contains(where: window.overlaps) }
    }

    private static let earliest = "0000-00"
    private static let latest = "9999-99"

    /// "1994-01" -> "01.1994"
    private static func display(_ month: String) -> String {
        let parts = month.split(separator: "-")
        guard parts.count == 2 else { return month }
        return "\(parts[1]).\(parts[0])"
    }
}
