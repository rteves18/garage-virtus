import Foundation

/// A request to open a group on a specific schema, callout and part (from search or a part page).
/// `token` makes every request distinct, so asking for the same part twice still jumps there.
struct PartFocus: Equatable {
    let token = UUID()
    let groupID: String
    let schemaId: String?
    let pnc: String?
    let oem: String?
}
