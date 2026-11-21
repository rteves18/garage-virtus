import Foundation
import Testing
@testable import GarageVirtusKit

/// A throwaway directory per test.
final class TempSpace {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func makeFolder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A catalogue folder holding the KRPS13 group-101 fixture and the 10102-50FR2 part page.
    func makeCatalogue() throws -> URL {
        let catalogue = try makeFolder("catalogue")
        let group = catalogue.appendingPathComponent(
            "nissan/180sx/KRPS13/6976_1994-1998_TYPE-RX_MT_4WS/engine/101_Bearing-and-short-engine-assembly",
            isDirectory: true)
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        let fixture = try #require(Bundle.module.url(forResource: "schema-group", withExtension: "json", subdirectory: "Fixtures"))
        try FileManager.default.copyItem(at: fixture, to: group.appendingPathComponent("schema-group.json"))
        let parts = catalogue.appendingPathComponent("nissan/_parts/10", isDirectory: true)
        try FileManager.default.createDirectory(at: parts, withIntermediateDirectories: true)
        let partFixture = try #require(Bundle.module.url(forResource: "1010250FR2", withExtension: "json", subdirectory: "Fixtures"))
        try FileManager.default.copyItem(at: partFixture, to: parts.appendingPathComponent("1010250FR2.json"))
        return catalogue
    }

}

extension URL {
    var comparablePath: String { standardizedFileURL.resolvingSymlinksInPath().path }
}
