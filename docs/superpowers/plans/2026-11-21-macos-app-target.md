# Garage Virtus macOS App Target Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the SwiftPM-executable catalogue viewer into a signed, sandboxed macOS app whose core lives in a testable local package.

**Architecture:** `GarageVirtus.xcodeproj` has one macOS app target whose sources are a synchronized folder `GarageVirtus/` (just `@main`, assets, entitlements). All models, the store and the views move to the local package `GarageVirtusKit/`, which the app links. Catalogue access goes through a security-scoped, read-only bookmark kept in UserDefaults.

**Tech Stack:** Swift 6.4 toolchain / Xcode 27.2, SwiftUI + Observation, macOS 14, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-21-macos-app-target-design.md`

## Global Constraints

- Bundle ID `com.rteves.GarageVirtus`. Deployment target macOS 14.0. Hardened runtime on. Automatic signing, "Sign to Run Locally" (`CODE_SIGN_IDENTITY = "-"`), no team.
- Entitlements exactly: `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-only`, `com.apple.security.files.bookmarks.app-scope`. No network entitlement.
- Swift 6 language mode in package and app. If the concurrency fixes grow past small ones, fall back to Swift 5 mode and note it in the README.
- No XcodeGen/Tuist. The project opens and builds with stock Xcode.
- `catalogue/` and `tools/` are not modified.
- Existing behaviour unchanged: sidebar, diagram, inspector, search, part details, ⌘O (Open Catalogue Folder…), ⌘R (Reload Catalogue).
- User naming rules: construct types with `init`, name methods for what they do, Boolean parameters read as assertions (`isX`).

## Review Focus

1. **Catalogue folder moved or deleted after it was chosen** → on launch the app shows the choose-folder screen (and the saved bookmark is cleared), not an empty sidebar or a crash. *Pinned in Task 2: `restoreReturnsNilAndForgetsWhenFolderIsGone`.*
2. **User picks the wrong folder (e.g. repo root instead of `catalogue/`)** → the detail area says no catalogue was found in that folder and offers to choose another, instead of a silent empty tree. *Pinned in Task 2: `wrongFolderShowsNoCatalogueFound` (store state `hasCatalogue == false` with a root set).*
3. **Choosing a second folder while one is open** → access to the first is released, the new one is remembered, and only the new tree shows. *Pinned in Task 2: `savingReplacesPreviousFolder`.*
4. **Cancel on the open panel at first launch** → stays on the choose-folder screen. No crash, nothing saved. *Manual check in Task 3, step 6.*
5. **Relaunch after choosing** → no prompt. The same folder opens with the same group count. *Manual check in Task 3, step 6.*

---

### Task 0: Baseline commit of the existing app

`GarageVirtus/`, `catalogue/`, `tools/` are untracked today. Commit them as-is so the moves in Task 1 show up as renames.

- [ ] **Step 1:** `git status` shows only `GarageVirtus/`, `catalogue/`, `tools/`, `docs/` untracked. Make sure `GarageVirtus/.swiftpm` and `.build` are ignored or excluded (the Xcode .gitignore covers `.build/`. Add `.swiftpm/` to `.gitignore` if it shows up).
- [ ] **Step 2:** `cd GarageVirtus && swift build` → `Build complete!` (proves the baseline builds).
- [ ] **Step 3: Commit**
```bash
git add .gitignore GarageVirtus catalogue tools docs
git commit -m "Add SwiftPM catalogue viewer, catalogue samples, Amayama scrapers, design + plan"
```

---

### Task 1: Move the code into the `GarageVirtusKit` package with tests

**Files:**
- Create: `GarageVirtusKit/Package.swift`
- Move (`git mv`): `GarageVirtus/Sources/GarageVirtus/{Models,Store,Views}` → `GarageVirtusKit/Sources/GarageVirtusKit/{Models,Store,Views}`
- Move: `GarageVirtus/Sources/GarageVirtus/GarageVirtusApp.swift` → `GarageVirtus/GarageVirtusApp.swift` (app target folder for Task 3. It isn't built by anything during this task)
- Delete: `GarageVirtus/Package.swift`, `GarageVirtus/.swiftpm/`, `GarageVirtus/Sources/`, and `GarageVirtus/README.md` (its content moves to the root README in Task 3)
- Create: `GarageVirtusKit/Tests/GarageVirtusKitTests/{CatalogueStoreParsingTests,DecodingTests}.swift`
- Create fixtures (copies): `GarageVirtusKit/Tests/GarageVirtusKitTests/Fixtures/schema-group.json` (from `catalogue/nissan/180sx/KRPS13/6976_1994-1998_TYPE-RX_MT_4WS/engine/101_Bearing-and-short-engine-assembly/schema-group.json`), `.../Fixtures/1010250FR2.json` (from `catalogue/nissan/_parts/10/1010250FR2.json`)

**Interfaces:**
- Produces (public, used by the app in Task 3): `public struct ContentView: View { public init() }`, `public final class CatalogueStore` with `public init()` and the methods listed in Task 2.
- Produces (nonisolated statics, used by tests): `CatalogueStore.normalize(_:) -> String`, `CatalogueStore.splitCodeName(_:) -> (String, String)`, `CatalogueStore.parseAmayamaPartURL(_:) -> (oem: String, schemaId: String?, pnc: String?)?`. Mark the last two `nonisolated` (normalize already is).
- Produces: `CatalogueStore.makeDecoder() -> JSONDecoder` (static, nonisolated, `.convertFromSnakeCase`). It replaces the two inline decoder setups in `load(_:)` and `partPage(for:)`, so tests decode exactly like the app.

- [ ] **Step 1: Write `GarageVirtusKit/Package.swift`.** `swift-tools-version:6.0`, platforms `.macOS(.v14)`, library product `GarageVirtusKit`, target `GarageVirtusKit`, test target `GarageVirtusKitTests` depending on it with `resources: [.copy("Fixtures")]`. Swift 6 is the default language mode for tools 6.0.

- [ ] **Step 2: Do the moves and deletions above, then copy the two fixtures.**

- [ ] **Step 3: Write the failing tests.**

`CatalogueStoreParsingTests.swift` (Swift Testing, pass and fail cases in separate tests, no branching flags):
```swift
@Test(arguments: [("10102-50FR2", "1010250FR2"), ("1010250fr2", "1010250FR2"), (" 10102 50fr2 ", "1010250FR2")])
func normalizeStripsPunctuationAndUppercases(input: String, expected: String) {
    #expect(CatalogueStore.normalize(input) == expected)
}

@Test func splitCodeNameReadsGroupFolder() {
    let (code, name) = CatalogueStore.splitCodeName("101_Bearing-and-short-engine-assembly")
    #expect(code == "101"); #expect(name == "Bearing and short engine assembly")
}
@Test func splitCodeNameReadsVariantFolder() {
    let (code, name) = CatalogueStore.splitCodeName("6976_1994-1998_TYPE-RX_MT_4WS")
    #expect(code == "6976"); #expect(name == "1994-1998 TYPE-RX MT 4WS")
}
@Test func splitCodeNameWithoutUnderscoreReturnsFolderTwice() {
    let (code, name) = CatalogueStore.splitCodeName("engine")
    #expect(code == "engine"); #expect(name == "engine")
}

@Test func parsesAmayamaPartURLWithSchemaAndCallout() throws {
    let parsed = try #require(CatalogueStore.parseAmayamaPartURL(
        "https://www.amayama.com/en/part/nissan/1010250fr2?sid=101B_001_1.R10102"))
    #expect(parsed.oem == "1010250fr2"); #expect(parsed.schemaId == "101B_001_1"); #expect(parsed.pnc == "R10102")
}
@Test func parsesAmayamaPartURLWithoutSid() throws {
    let parsed = try #require(CatalogueStore.parseAmayamaPartURL("https://www.amayama.com/en/part/nissan/1010250fr2"))
    #expect(parsed.oem == "1010250fr2"); #expect(parsed.schemaId == nil); #expect(parsed.pnc == nil)
}
@Test(arguments: ["https://example.com/en/part/nissan/1010250fr2", "10102-50FR2", "https://www.amayama.com/en/genuine-catalogs/nissan"])
func rejectsNonAmayamaPartURLs(input: String) {
    #expect(CatalogueStore.parseAmayamaPartURL(input) == nil)
}
```

`DecodingTests.swift` loads fixtures with `Bundle.module.url(forResource:withExtension:subdirectory: "Fixtures")` and `CatalogueStore.makeDecoder()`:
```swift
@Test func decodesSchemaGroupSample() throws {
    let file = try decode(SchemaGroupFile.self, "schema-group")
    #expect(file.vehicle.model == "180SX"); #expect(file.vehicle.frame == "KRPS13"); #expect(file.vehicle.variantId == "6976")
    #expect(file.group.code == "101"); #expect(file.schemas.count == 2)
    let schema = file.schemas[0]
    #expect(schema.id == "101B_001_0"); #expect(schema.image == "imgjp16/RS13/101B_001.png"); #expect(schema.callouts.count == 3)
    #expect(schema.callouts[0].pnc == "10102")
    #expect(schema.callouts[0].parts.map(\.oem) == ["10102-50F50", "10102-50F52", "10102-50FM2"])
}
@Test func decodesPartPageSample() throws {
    let page = try decode(PartPage.self, "1010250FR2")
    #expect(page.oem == "10102-50FR2"); #expect(page.key == "1010250FR2")
    #expect(page.name == "ENGINE ASSEMBLY, BEAR REBUILT"); #expect(page.offers.count == 1); #expect(page.diagrams.count == 8)
}
```
Tests use `@testable import GarageVirtusKit` so internal model types are visible.

- [ ] **Step 4:** `cd GarageVirtusKit && swift test` → fails to compile (`makeDecoder` missing, statics MainActor-isolated).

- [ ] **Step 5: Implement.** Add `makeDecoder()`, mark `splitCodeName` and `parseAmayamaPartURL` `nonisolated`, make `ContentView` and `CatalogueStore` (+ `init`, `reload()`, `chooseRoot()`) `public`. `ContentView` needs an explicit `public init() {}`. Fix any Swift 6 diagnostics (spec fallback rule applies).

- [ ] **Step 6:** `swift test` → all tests pass, and there are no warnings from `swift build 2>&1 | grep -i warning`.

- [ ] **Step 7: Commit**
```bash
git add -A GarageVirtus GarageVirtusKit
git commit -m "Move catalogue viewer into GarageVirtusKit package with parsing and decoding tests"
```

---

### Task 2: Sandbox-safe catalogue folder access

**Files:**
- Create: `GarageVirtusKit/Sources/GarageVirtusKit/Store/CatalogueFolderAccess.swift`
- Modify: `GarageVirtusKit/Sources/GarageVirtusKit/Store/CatalogueStore.swift` (init, `defaultRoot`, `chooseRoot`, `reload`)
- Modify: `GarageVirtusKit/Sources/GarageVirtusKit/Views/ContentView.swift` (empty states)
- Test: `GarageVirtusKit/Tests/GarageVirtusKitTests/CatalogueFolderAccessTests.swift`, `.../CatalogueStoreFolderTests.swift`

**Interfaces:**
- Produces:
```swift
/// Remembers the user-chosen catalogue folder as a read-only bookmark and holds its security scope open.
final class CatalogueFolderAccess {
    init(defaults: UserDefaults = .standard, bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
    /// Resolves the saved bookmark and starts access. Recreates a stale bookmark. Clears it and returns nil if it can't resolve or the folder is gone.
    func restore() -> URL?
    /// Stops access to any current folder, saves a bookmark for `url`, starts access to it.
    func remember(_ url: URL) throws
    func forget()
    var currentFolder: URL? { get }
}
```
  UserDefaults key `"catalogueBookmark"`. `deinit` stops access. Tests pass `bookmarkOptions: []` because the test process isn't sandboxed. The app uses the default.
- `CatalogueStore` changes (all public, `@MainActor`):
  - `public private(set) var root: URL?` (was non-optional)
  - `public var hasCatalogue: Bool` → `!frames.isEmpty`
  - `public init()` → uses `CatalogueFolderAccess()`, and `init(folderAccess: CatalogueFolderAccess)` (internal) for tests. Both call `reload()` with the restored root.
  - `public func chooseCatalogueFolder()` replaces `chooseRoot()`. It runs the `NSOpenPanel`, then calls `open(folder:)`.
  - `func open(folder: URL) throws` (internal, testable): `folderAccess.remember(folder)`, sets `root`, `reload()`.
  - `static var suggestedFolder: URL?`: the repo's `catalogue/` via `#filePath` (five `deleteLastPathComponent()` from `GarageVirtusKit/Sources/GarageVirtusKit/Store/CatalogueStore.swift`), returned only if it exists. Used only as the open panel's starting directory.
  - Remove `defaultRoot`, the `"catalogueRoot"` default, and the old path-string branch in `init`. `reload()` with `root == nil` clears frames/counts.
- Consumes: Task 1's public `CatalogueStore`/`ContentView`.

- [ ] **Step 1: Write the failing tests.** Each test makes a temp dir and a `UserDefaults(suiteName: UUID().uuidString)!`.
```swift
@Test func rememberedFolderIsRestored() throws {
    let access = CatalogueFolderAccess(defaults: defaults, bookmarkOptions: [])
    try access.remember(folder)
    let restored = CatalogueFolderAccess(defaults: defaults, bookmarkOptions: []).restore()
    #expect(restored?.standardizedFileURL.path == folder.standardizedFileURL.path)
}
@Test func restoreWithNothingSavedReturnsNil() { #expect(CatalogueFolderAccess(defaults: defaults, bookmarkOptions: []).restore() == nil) }
@Test func restoreReturnsNilAndForgetsWhenFolderIsGone() throws {
    try CatalogueFolderAccess(defaults: defaults, bookmarkOptions: []).remember(folder)
    try FileManager.default.removeItem(at: folder)
    #expect(CatalogueFolderAccess(defaults: defaults, bookmarkOptions: []).restore() == nil)
    #expect(defaults.data(forKey: "catalogueBookmark") == nil)
}
@Test func savingReplacesPreviousFolder() throws {
    let access = CatalogueFolderAccess(defaults: defaults, bookmarkOptions: [])
    try access.remember(folderA); try access.remember(folderB)
    #expect(access.currentFolder?.standardizedFileURL.path == folderB.standardizedFileURL.path)
    #expect(CatalogueFolderAccess(defaults: defaults, bookmarkOptions: []).restore()?.standardizedFileURL.path == folderB.standardizedFileURL.path)
}
```
`CatalogueStoreFolderTests.swift` (`@MainActor`). Build a temp catalogue by copying the Task 1 schema-group fixture into `<tmp>/nissan/180sx/KRPS13/6976_1994-1998_TYPE-RX_MT_4WS/engine/101_Bearing-and-short-engine-assembly/schema-group.json`:
```swift
@Test func noSavedFolderMeansNoRoot() { let store = CatalogueStore(folderAccess: access); #expect(store.root == nil); #expect(!store.hasCatalogue) }
@Test func openingCatalogueFolderLoadsTree() throws {
    let store = CatalogueStore(folderAccess: access); try store.open(folder: tmpCatalogue)
    #expect(store.hasCatalogue); #expect(store.scrapedCount == 1); #expect(store.frames.first?.title == "Nissan 180SX KRPS13")
}
@Test func wrongFolderShowsNoCatalogueFound() throws {
    let store = CatalogueStore(folderAccess: access); try store.open(folder: emptyDir)
    #expect(store.root != nil); #expect(!store.hasCatalogue)
}
@Test func reopenedStoreRestoresFolder() throws {
    try CatalogueStore(folderAccess: access).open(folder: tmpCatalogue)
    #expect(CatalogueStore(folderAccess: CatalogueFolderAccess(defaults: defaults, bookmarkOptions: [])).hasCatalogue)
}
```

- [ ] **Step 2:** `swift test` → fails to compile (`CatalogueFolderAccess`, `open(folder:)`, `hasCatalogue` missing).

- [ ] **Step 3: Implement `CatalogueFolderAccess`** with `URL.bookmarkData(options:includingResourceValuesForKeys:relativeTo:)` / `URL(resolvingBookmarkData:options:relativeTo:bookmarkDataIsStale:)`. Resolve options: `.withSecurityScope` only when `bookmarkOptions` contains it. Track whether `startAccessingSecurityScopedResource()` returned true, and stop only then.

- [ ] **Step 4: Implement the `CatalogueStore` changes** listed in Interfaces. The open panel message stays "Choose the garage-virtus/catalogue folder". `directoryURL = root ?? Self.suggestedFolder`. If `open(folder:)` throws, keep the previous root.

- [ ] **Step 5: Update `ContentView` detail empty states**, in this order:
  - `store.root == nil` → `ContentUnavailableView` titled "Choose your catalogue folder", system image `folder.badge.questionmark`, description "Garage Virtus reads diagrams and parts from your garage-virtus/catalogue folder.", with a **Choose Catalogue Folder…** button calling `store.chooseCatalogueFolder()`.
  - `!store.hasCatalogue` → "No catalogue found", system image `tray`, description "\(root.path) has no make/model/frame folders." plus the same button.
  - Otherwise the existing "Select a schema group" view (its `store.root.path` becomes optional-safe).

- [ ] **Step 6:** `swift test` → all pass, no warnings.

- [ ] **Step 7: Commit**
```bash
git add -A GarageVirtusKit
git commit -m "Remember catalogue folder with a security-scoped bookmark and add first-launch states"
```

---

### Task 3: Xcode project, sandboxed app target, README

**Files:**
- Create: `GarageVirtus.xcodeproj/project.pbxproj`, `GarageVirtus.xcodeproj/xcshareddata/xcschemes/GarageVirtus.xcscheme`
- Create: `GarageVirtus/GarageVirtus.entitlements`, `GarageVirtus/Assets.xcassets/{Contents.json, AppIcon.appiconset/Contents.json, AccentColor.colorset/Contents.json}`
- Modify: `GarageVirtus/GarageVirtusApp.swift`
- Modify: `README.md` (root, currently empty)

**Interfaces:**
- Consumes: `import GarageVirtusKit`, `CatalogueStore()`, `ContentView()`, `store.chooseCatalogueFolder()`, `store.reload()`.

- [ ] **Step 1: Update `GarageVirtusApp.swift`.** `import GarageVirtusKit`. Remove the `init()` with `setActivationPolicy` and the `.onAppear { NSApp.activate() }`. Rename the menu action to call `chooseCatalogueFolder()`. Keep the window title, `minWidth: 1000, minHeight: 640`, and both shortcuts.

- [ ] **Step 2: Write `project.pbxproj`** (`objectVersion = 77`, Xcode 16+ format), containing:
  - `PBXFileSystemSynchronizedRootGroup` with `path = GarageVirtus`, attached to the app target's `fileSystemSynchronizedGroups`. Add a `PBXFileSystemSynchronizedBuildFileExceptionSet` excluding `GarageVirtus.entitlements` from the target's membership.
  - `XCLocalSwiftPackageReference` with `relativePath = GarageVirtusKit` in the project's `packageReferences`, and an `XCSwiftPackageProductDependency` `productName = GarageVirtusKit` in the target's `packageProductDependencies` plus a Frameworks build phase entry.
  - A `PBXNativeTarget` "GarageVirtus" of type `com.apple.product-type.application`, with Sources/Frameworks/Resources phases.
  - Debug and Release target build settings: `PRODUCT_BUNDLE_IDENTIFIER = com.rteves.GarageVirtus`, `PRODUCT_NAME = "$(TARGET_NAME)"`, `MACOSX_DEPLOYMENT_TARGET = 14.0`, `SDKROOT = macosx`, `SWIFT_VERSION = 6.0`, `CODE_SIGN_STYLE = Automatic`, `CODE_SIGN_IDENTITY = "-"`, `CODE_SIGN_ENTITLEMENTS = GarageVirtus/GarageVirtus.entitlements`, `ENABLE_HARDENED_RUNTIME = YES`, `GENERATE_INFOPLIST_FILE = YES`, `INFOPLIST_KEY_CFBundleDisplayName = "Garage Virtus"`, `INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.productivity"`, `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`, `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor`, `MARKETING_VERSION = 0.1.0`, `CURRENT_PROJECT_VERSION = 1`, `COMBINE_HIDPI_IMAGES = YES`.

  Use unique 24-character uppercase hex object IDs. Check with `plutil -lint GarageVirtus.xcodeproj/project.pbxproj` → `OK`, and `xcodebuild -list -project GarageVirtus.xcodeproj` → lists target and scheme `GarageVirtus`.

- [ ] **Step 3: Write the shared scheme** "GarageVirtus": build and launch the app target, with the Test action including `GarageVirtusKitTests` from the local package. That makes `xcodebuild test -scheme GarageVirtus` run the package tests.

- [ ] **Step 4: Write the entitlements** (exactly the three keys in Global Constraints, all `<true/>`) and the asset catalog (empty AppIcon set listing the macOS sizes 16–512 @1x/@2x with no filenames, and a default AccentColor).

- [ ] **Step 5: Build, test, and check the signature**
```bash
xcodebuild -project GarageVirtus.xcodeproj -scheme GarageVirtus \
  -configuration Debug -derivedDataPath build build test 2>&1 \
  | tail -5
codesign -d --entitlements - \
  build/Build/Products/Debug/GarageVirtus.app
```
Expected: `** BUILD SUCCEEDED **` and `** TEST SUCCEEDED **`. The entitlements dump shows the three keys and nothing else. `codesign -dv` shows `flags=0x10000(runtime)`. Add `build/` to `.gitignore`.

- [ ] **Step 6: Manual launch check** (`open build/Build/Products/Debug/GarageVirtus.app`). Clear state first with `defaults delete com.rteves.GarageVirtus` (ignore "does not exist").
  1. First launch shows "Choose your catalogue folder". Click the button, then **Cancel**: still on the same screen (Review Focus 4).
  2. Choose the repo root: "No catalogue found" (Review Focus 2).
  3. ⌘O, choose `catalogue/`: the sidebar shows "Nissan 180SX KRPS13", and group 101's diagram and inspector work. Search `50FR2` finds the part.
  4. Quit and relaunch: it opens straight to the catalogue with no prompt (Review Focus 5).
  5. "View on Amayama" opens the browser (links work without a network entitlement).

- [ ] **Step 7: Write the root `README.md`.** Cover: what the app is (one line), open `GarageVirtus.xcodeproj` and ⌘R, first-launch folder prompt (choose `catalogue/`), ⌘O / ⌘R, `swift test` in `GarageVirtusKit/` or `xcodebuild test`, and the "Using it" and "Data contract" sections carried over from the old `GarageVirtus/README.md`. Mention the Swift 5 fallback if it was used.

- [ ] **Step 8: Commit**
```bash
git add -A .gitignore README.md GarageVirtus GarageVirtus.xcodeproj
git commit -m "Add sandboxed macOS app target linking GarageVirtusKit"
```
