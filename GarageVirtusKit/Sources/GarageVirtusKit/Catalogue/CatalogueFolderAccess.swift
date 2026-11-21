import Foundation

/// Remembers the user-chosen catalogue folder as a read-only bookmark and holds its security scope open,
/// so the sandboxed app can read it again after relaunch.
final class CatalogueFolderAccess {
    private static let bookmarkKey = "catalogueBookmark"

    private let defaults: UserDefaults
    private let bookmarkOptions: URL.BookmarkCreationOptions
    private var isAccessingCurrentFolder = false

    private(set) var currentFolder: URL?

    /// Tests pass `bookmarkOptions: []` because a non-sandboxed test process can't use security scope.
    init(
        defaults: UserDefaults = .standard,
        bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
    ) {
        self.defaults = defaults
        self.bookmarkOptions = bookmarkOptions
    }

    deinit {
        stopAccessing()
    }

    /// Resolves the saved bookmark and starts access. Recreates a stale bookmark.
    /// Clears it and returns nil if it can't resolve or the folder is gone.
    func restore() -> URL? {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: resolutionOptions,
                                 relativeTo: nil, bookmarkDataIsStale: &isStale),
              Self.isExistingFolder(url) else {
            forget()
            return nil
        }
        startAccessing(url)
        if isStale, let fresh = try? bookmarkData(for: url) {
            defaults.set(fresh, forKey: Self.bookmarkKey)
        }
        return url
    }

    /// Stops access to any current folder, saves a bookmark for `url`, starts access to it.
    func remember(_ url: URL) throws {
        let data = try bookmarkData(for: url)
        stopAccessing()
        defaults.set(data, forKey: Self.bookmarkKey)
        startAccessing(url)
    }

    func forget() {
        stopAccessing()
        defaults.removeObject(forKey: Self.bookmarkKey)
    }

    // MARK: helpers

    private var resolutionOptions: URL.BookmarkResolutionOptions {
        bookmarkOptions.contains(.withSecurityScope) ? [.withSecurityScope] : []
    }

    private func bookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func startAccessing(_ url: URL) {
        isAccessingCurrentFolder = url.startAccessingSecurityScopedResource()
        currentFolder = url
    }

    private func stopAccessing() {
        if isAccessingCurrentFolder { currentFolder?.stopAccessingSecurityScopedResource() }
        isAccessingCurrentFolder = false
        currentFolder = nil
    }

    private static func isExistingFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
