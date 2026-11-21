import Foundation
import GarageVirtusKit
import Observation

/// Selection state for a My garage list: which part's editor is open.
@MainActor
@Observable
final class GarageViewModel {
    /// The selected part's `id` (the table's row identity).
    var selectedPartID: UUID?

    func select(_ part: GaragePart) {
        selectedPartID = part.id
    }

    func clearSelection() {
        selectedPartID = nil
    }
}
