import Foundation
@testable import GarageVirtusKit

/// A throwaway directory and UserDefaults suite per test.
final class TempSpace {
    let root: URL
    let defaults: UserDefaults
    private let suiteName = "GarageVirtusKitTests.\(UUID().uuidString)"

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func makeFolder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A catalogue folder holding the KRPS13 group-101 fixture.
    func makeCatalogue() throws -> URL {
        let catalogue = try makeFolder("catalogue")
        let group = catalogue.appendingPathComponent(
            "nissan/180sx/KRPS13/6976_1994-1998_TYPE-RX_MT_4WS/engine/101_Bearing-and-short-engine-assembly",
            isDirectory: true)
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        let fixture = Bundle.module.url(forResource: "schema-group", withExtension: "json", subdirectory: "Fixtures")!
        try FileManager.default.copyItem(at: fixture, to: group.appendingPathComponent("schema-group.json"))
        return catalogue
    }

    func makeAccess() -> CatalogueFolderAccess {
        CatalogueFolderAccess(defaults: defaults, bookmarkOptions: [])
    }
}

extension URL {
    var comparablePath: String { standardizedFileURL.resolvingSymlinksInPath().path }
}
