# Task 4: MVVM split — interface contract

Spec: `docs/superpowers/specs/2026-11-21-macos-app-target-design.md` (Layout section is binding).
Repo: `/Users/rteves/Documents/dev/personal/garage-virtus`, branch `macos-app-target`. Swift 6 language mode, macOS 14.
Behaviour must not change: sidebar, diagram, inspector, search, part details popover, ⌘O, ⌘R, first-launch states.

## File ownership (agents run in parallel on one working tree; touch ONLY your files)
| Agent | Owns |
|---|---|
| kit | `GarageVirtusKit/**` |
| viewmodels | `GarageVirtus/ViewModels/**`, `GarageVirtusTests/**`, `GarageVirtus.xcodeproj/**` |
| views | `GarageVirtus/Views/**`, `GarageVirtus/GarageVirtusApp.swift` |

Nobody commits. The integrator (main session) builds, fixes seams, and commits.
SwiftPM in this environment needs `--disable-sandbox` (`swift test --disable-sandbox`).

## A. Kit public API (`GarageVirtusKit`, no SwiftUI import anywhere in the Kit)

Files: `Sources/GarageVirtusKit/Models/{SchemaGroupFile,PartPage,CatalogueTree,PartRef,PartUsage}.swift`,
`Sources/GarageVirtusKit/Catalogue/{CatalogueStore,CatalogueFolderAccess}.swift`.

- Every model type and every stored property is `public` (`SchemaGroupFile`, `Source`, `Vehicle`, `GroupInfo`, `ImageInfo`,
  `Period` + `display`, `Schema`, `Callout` + `displayName` + `contains(oem:)`, `Hotspot`, `HotspotRect`, `Part` + `matches(_:)`,
  `Replacement`, `Price`, `PartPage` and nested types). Conformances stay (`Codable`, `Identifiable`, `Hashable`, `Sendable` where trivially true).
- `CatalogueTree.swift`: `FrameNode`, `VariantNode`, `CategoryNode`, `GroupNode` (moved out of CatalogueStore.swift, public, same fields).
- `PartRef.swift`: `PartRef` (public, same fields, `Identifiable, Hashable`).
- `PartUsage.swift`:
  ```swift
  public struct PartUsage {
      public let usedIn: [PartRef]                  // refs where replacementOf == nil
      public let replaces: [String]                 // sorted unique replacementOf values
      public let page: PartPage?                    // scraped part page, if any
      public let elsewhere: [PartPage.DiagramRef]   // page.diagrams not matching any usedIn "\(variantId)|\(groupCode)"
  }
  ```
  Logic is exactly what `PartDetailView.details` computes today (see GarageVirtus/Views/PartsInspector.swift).
- `CatalogueStore` — `@MainActor @Observable public final class`:
  - `public convenience init()`; `public init(folderAccess: CatalogueFolderAccess)`
  - `public private(set) var root: URL?`, `frames: [FrameNode]`, `totalCount: Int`, `scrapedCount: Int`, `indexedPartCount: Int`
  - `public var hasCatalogue: Bool`
  - `public func open(folder: URL) throws`, `public func reload()`
  - `public func group(id: String) -> GroupNode?`
  - `public func searchParts(_ query: String) -> [PartRef]`, `public func refs(for oem: String) -> [PartRef]`
  - `public func usage(of oem: String) -> PartUsage`
  - `public func load(_ group: GroupNode) throws -> SchemaGroupFile`
  - `public func image(named path: String, for group: GroupNode) -> NSImage?` (AppKit import allowed for NSImage)
  - `public func partPage(for oem: String) -> PartPage?`
  - `public static var suggestedFolder: URL?` (note: `#filePath` now lives in `Catalogue/`, same depth → still 5 levels up)
  - `public nonisolated static func normalize(_:)`; `splitCodeName`, `parseAmayamaPartURL`, `makeDecoder` stay nonisolated (internal ok)
  - REMOVED from the Kit: `focus`, `PartFocus`, `open(_ ref:)`, `chooseCatalogueFolder()` / NSOpenPanel.
- `CatalogueFolderAccess` — `public final class`, `public init(defaults:bookmarkOptions:)` (same defaults), `restore()`, `remember(_:)`, `forget()`, `currentFolder` public.
- Tests (`swift test --disable-sandbox`): keep all 17 passing; add `PartUsageTests` (usedIn excludes replacement refs; replaces sorted+unique;
  elsewhere excludes local variant/group pairs, using the `1010250FR2.json` fixture's `diagrams` + the schema-group fixture; page nil when no part file).

## B. App view models (`GarageVirtus/ViewModels/`, `@MainActor @Observable final class`, `import GarageVirtusKit`)

`PartFocus.swift`
```swift
struct PartFocus: Equatable { let token = UUID(); let groupID: String; let schemaId: String?; let pnc: String?; let oem: String? }
```

`CatalogueViewModel.swift`
- `init(store: CatalogueStore = CatalogueStore())`; `let store: CatalogueStore`
- `var selection: String?`, `var search = ""`, `var showUnscraped = false`, `private(set) var focus: PartFocus?`
- `var partHits: [PartRef]` → `store.searchParts(search)`
- `struct VisibleCategory: Identifiable { let category: CategoryNode; let groups: [GroupNode]; var id: String }`
- `func visibleCategories(for variant: VariantNode) -> [VisibleCategory]` (logic moved from SidebarView: scraped-or-showUnscraped AND code/name matches search)
- `var isSidebarEmpty: Bool` → `store.scrapedCount == 0 && !showUnscraped`
- `enum EmptyState: Equatable { case chooseFolder; case noCatalogue(path: String); case ready(summary: String) }`, `var emptyState: EmptyState`
  - summary text exactly: `"\(scrapedCount) of \(totalCount) groups scraped · \(indexedPartCount) part numbers\n\(root.path)"`
- `func chooseCatalogueFolder()` — NSOpenPanel (message "Choose the garage-virtus/catalogue folder", `directoryURL = store.root ?? CatalogueStore.suggestedFolder`), then `openFolder(_:)`
- `func openFolder(_ url: URL)` — `try store.open(folder:)`; on failure keep previous root, clear `selection`only on success
- `func open(_ ref: PartRef)` — sets `focus` and `selection = ref.groupID`
- `func reload()` — `store.reload()`

`GroupDetailViewModel.swift`
- `init(group: GroupNode, store: CatalogueStore)`; `let group`
- `private(set) var file: SchemaGroupFile?`, `private(set) var loadError: String?`
- `var schemaIndex = 0` — didSet: clear `selectedPNC` if it isn't a callout on the new schema
- `var selectedPNC: String?` — didSet: non-nil → `showInspector = true`; if `highlightedOEM` is set and the new callout doesn't contain it → clear it
- `var hoveredPNC: String?`, `var highlightedOEM: String?`, `var showInspector = true`, `var showHotspots = true`
- `var schema: Schema?` (clamped index), `var image: NSImage?`, `var imageSize: CGSize` (image info → NSImage size → 1280×640)
- `var title: String` → `"\(group.code) · \(group.name)"`, `var vehicleSummary: String` (header line incl. period), `func label(for: Schema) -> String`
- `var isScraped: Bool`
- `func load()` — if scraped: decode via store, set `file` or `loadError`
- `func apply(_ focus: PartFocus?)` — only when `focus.groupID == group.id` and file loaded: set schemaIndex, selectedPNC, highlightedOEM (in that order), showInspector = true

Tests: new Xcode unit-test target `GarageVirtusTests` (Swift Testing, hosted by the app, `@testable import GarageVirtus`, `import GarageVirtusKit`),
fixtures in `GarageVirtusTests/Fixtures/` (copy of the schema-group fixture), stores built with
`CatalogueStore(folderAccess: CatalogueFolderAccess(defaults: <temp suite>, bookmarkOptions: []))` over a temp catalogue.
Cover: each EmptyState case; partHits for "50F5"; visibleCategories respects showUnscraped + search; open(ref) sets selection+focus;
GroupDetailViewModel: apply(focus) picks schema/callout/highlight, focus for another group is ignored, schemaIndex change clears a foreign callout,
selecting a callout that lacks the highlighted OEM clears it, selecting one that contains it keeps it.
Add target to `project.pbxproj` (synchronized folder, unit-test bundle, TEST_HOST/BUNDLE_LOADER = app, target dependency on the app) and to the shared
scheme's Testables. Verify: `xcodebuild -project GarageVirtus.xcodeproj -scheme GarageVirtus -destination 'platform=macOS' -derivedDataPath build test`
(only possible once kit + views land — write it so it compiles against this contract).

## C. Views (`GarageVirtus/Views/`)
- Views render view-model state and forward actions. No catalogue logic in views. Pure visual state (hover, zoom, "copied" tick, popover shown) may stay `@State`.
- `GarageVirtusApp`: `@State private var model = CatalogueViewModel()`; `.environment(model)`; commands call `model.chooseCatalogueFolder()` / `model.reload()`.
- `ContentView` reads `CatalogueViewModel` from the environment; switches on `emptyState`; `GroupDetailView(model: GroupDetailViewModel(group:store:))` created per group
  (`@State` in a wrapper keyed by group id, so it's not recreated every render); forwards `model.focus` changes to `apply(_:)`.
- `SidebarView` uses `model.partHits`, `model.visibleCategories(for:)`, `model.isSidebarEmpty`, `model.open(_:)`; keeps its `collapsed` set as view state.
- `GroupDetailView` / `PartsInspector` bind to `GroupDetailViewModel` (`@Bindable`). `PartsInspector` keeps its scroll-only `selectedFromInspector` flag.
- `PartDetailView` uses `store.usage(of:)`; jump buttons call `CatalogueViewModel.open(_:)`.
- Drop `public` from everything (app target).
