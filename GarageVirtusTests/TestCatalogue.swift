import Foundation
import GarageVirtusKit
import Testing

private final class BundleToken {}

/// A temp catalogue holding the KRPS13 group-101 fixture, plus a store over it with throwaway defaults.
@MainActor
final class TestCatalogue {
    static let groupPath = "nissan/180sx/KRPS13/6976_1994-1998_TYPE-RX_MT_4WS/engine/101_Bearing-and-short-engine-assembly"

    let root: URL
    let folder: URL
    let store: CatalogueStore
    private let defaults: UserDefaults
    private let suiteName = "GarageVirtusTests.\(UUID().uuidString)"

    /// - Parameter isOpened: false leaves the store with no folder chosen.
    init(isOpened: Bool = true) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        folder = root.appendingPathComponent("catalogue", isDirectory: true)
        let group = folder.appendingPathComponent(Self.groupPath, isDirectory: true)
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        let fixture = try #require(Bundle(for: BundleToken.self).url(forResource: "schema-group", withExtension: "json"))
        try FileManager.default.copyItem(at: fixture, to: group.appendingPathComponent("schema-group.json"))
        defaults = try #require(UserDefaults(suiteName: suiteName))
        store = CatalogueStore(folderAccess: CatalogueFolderAccess(defaults: defaults, bookmarkOptions: []))
        if isOpened { try store.open(folder: folder) }
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    func makeEmptyFolder() throws -> URL {
        let url = root.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    var group: GroupNode {
        get throws { try #require(store.group(id: folder.appendingPathComponent(Self.groupPath).path)) }
    }
}
