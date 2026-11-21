# Garage Parts Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Ryan track his own parts (need, want, in storage, waiting to install, installed) with purchase details and photos, linked to catalogue part numbers, stored with SwiftData.

**Architecture:** SwiftData models and a `@MainActor` `GarageStore` (all writes, explicit saves) live in `GarageVirtusKit/Sources/GarageVirtusKit/Garage/`. The app owns one `ModelContainer`, injects `GarageStore` through the environment, lists parts with `@Query` in views, and edits through the store. Catalogue browsing is untouched except for status badges and a context menu in the parts panel.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, PhotosUI (PhotosPicker), Swift Testing, macOS 14.

**Spec:** `docs/superpowers/specs/2026-11-21-garage-parts-tracking-design.md`

## Global Constraints

- macOS 14 deployment target, Swift 6 language mode, MVVM: models and data in GarageVirtusKit, view models and views in the app.
- The garage store is never inside the app bundle or `catalogue/`. Use the default SwiftData location in the sandboxed container.
- `VersionedSchema` (`GarageSchemaV1`) and a `SchemaMigrationPlan` from day one.
- Every relationship has an explicit `deleteRule` and `inverse`. `@Relationship` goes on one side only.
- Enums are stored as `String` raw values (`statusRaw`, `conditionRaw`) with computed typed wrappers. Predicates use only stored properties.
- No model property named `description`.
- Every write calls `modelContext.save()`. Model objects never cross actors.
- Link to the catalogue only by OEM key: `CatalogueStore.normalize(_:)` (e.g. `"10102-50FR2"` → `"1010250FR2"`).
- `cost` is the price paid for the whole row (purchase or bundle). Total spent is the sum of non-nil `cost` over owned rows, in USD.
- Owned statuses: `inStorage`, `waitingToInstall`, `installed`. All three count toward covering a need.
- Keep layout simple. No `.inspector`, no `GeometryReader`-driven sizing, and keep split-column minimum sizes constant (lessons from 2026-11-21).
- User UI copy rule: no singular/plural branches, e.g. "Parts: 3", "Have 2 of 4".

## Review Focus

1. **Marking "Have" on a part that is already a need** creates a new owned row, keeps the need row, and shows the need as partly covered. *Pinned in Task 2: `markBoughtKeepsNeedAndCoversIt`.*
2. **Owning more than needed** shows "Have 5 of 4", with nothing short. *Pinned in Task 2: `overCoveredNeedIsNotShort`.*
3. **A custom part with no part number** appears in its status list and never affects coverage of other parts. *Pinned in Task 2: `partWithoutOEMIsIgnoredByCoverage`.*
4. **Deleting a part with photos** removes its photos too. *Pinned in Task 2: `deletingPartDeletesPhotos`.*
5. **Data survives relaunch and rebuild.** The store file is in the app container and is untouched by rebuilds. *Manual check in Task 5.*

---

### Task 1: SwiftData models, schema, container, and basic store writes

**Files:**
- Create: `GarageVirtusKit/Sources/GarageVirtusKit/Garage/GarageSchemaV1.swift` (enum `GarageSchemaV1: VersionedSchema` with nested `@Model` classes `Car`, `GaragePart`, `PartPhoto`; `typealias`es at file scope: `public typealias Car = GarageSchemaV1.Car`, etc.)
- Create: `GarageVirtusKit/Sources/GarageVirtusKit/Garage/PartStatus.swift` (`PartStatus`, `PartCondition`)
- Create: `GarageVirtusKit/Sources/GarageVirtusKit/Garage/GarageMigrationPlan.swift`
- Create: `GarageVirtusKit/Sources/GarageVirtusKit/Garage/GarageStore.swift`
- Test: `GarageVirtusKit/Tests/GarageVirtusKitTests/GarageStoreTests.swift`

**Interfaces (produces):**
```swift
public enum PartStatus: String, Codable, CaseIterable, Sendable {
    case need, want, inStorage, waitingToInstall, installed
    public var isOwned: Bool            // inStorage, waitingToInstall, installed
    public var title: String            // "Need", "Want", "In storage", "Waiting to install", "Installed"
}
public enum PartCondition: String, Codable, CaseIterable, Sendable {
    case new, usedGood, usedFair, needsRebuild, core
    public var title: String            // "New", "Used – good", "Used – fair", "Needs rebuild", "Core"
}
// GarageSchemaV1.Car: id UUID, name, frame, variantID, createdAt, updatedAt,
//   @Relationship(deleteRule: .cascade, inverse: \GaragePart.car) parts: [GaragePart]
// GarageSchemaV1.GaragePart: fields exactly as the spec's Data model section
//   (id, createdAt, updatedAt, name, oemNumber?, oemKey?, quantity=1, notes="", statusRaw, cost: Decimal?,
//    currency="USD", seller?, sellerURL?, purchasedOn?, conditionRaw?, storageLocation?, targetPrice: Decimal?,
//    linkURL?, groupCode?, pnc?, car: Car?, @Relationship(deleteRule: .cascade, inverse: \PartPhoto.part) photos)
//   plus computed `status: PartStatus` and `condition: PartCondition?` (get/set through the raw strings).
// GarageSchemaV1.PartPhoto: id, @Attribute(.externalStorage) imageData: Data, createdAt, part: GaragePart?

@MainActor @Observable public final class GarageStore {
    public init(container: ModelContainer)
    public static func makeContainer(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer
    public func defaultCar() -> Car                       // creates "1997 Nissan 180SX Type X", KRPS13, 6976 once
    @discardableResult public func markWanted(oemNumber: String?, name: String, status: PartStatus, quantity: Int = 1,
                                              groupCode: String? = nil, pnc: String? = nil) -> GaragePart
    @discardableResult public func addOwned(oemNumber: String?, name: String, status: PartStatus = .inStorage,
                                            quantity: Int = 1, groupCode: String? = nil, pnc: String? = nil) -> GaragePart
    public func setStatus(_ status: PartStatus, for part: GaragePart)
    public func delete(_ part: GaragePart)
    public func parts(withOEMKey key: String) -> [GaragePart]
    public func save()                                    // used by editors after field edits; touches updatedAt
}
```
`markWanted` requires `status` to be `.need` or `.want` (`precondition`). It finds the existing need/want row for that OEM key on the default car, or creates one, then sets its status and quantity. `addOwned` requires an owned status and always inserts.

- [ ] **Step 1: Write failing tests** in `GarageStoreTests` (a `@MainActor struct` whose `init()` makes an in-memory container and a store):
```swift
@Test func defaultCarIsCreatedOnce() { #expect(store.defaultCar().id == store.defaultCar().id); #expect(store.defaultCar().frame == "KRPS13") }
@Test func markingNeedTwiceUpdatesOneRow() {
    store.markWanted(oemNumber: "10102-50FR2", name: "Engine assembly", status: .need, quantity: 1)
    let row = store.markWanted(oemNumber: "1010250fr2", name: "Engine assembly", status: .want, quantity: 2)
    #expect(store.parts(withOEMKey: "1010250FR2").count == 1); #expect(row.status == .want); #expect(row.quantity == 2)
}
@Test func addingOwnedTwiceCreatesTwoRows() {
    store.addOwned(oemNumber: "08911-6401A", name: "Nut-Hex", quantity: 10)
    store.addOwned(oemNumber: "08911-6401A", name: "Nut-Hex", quantity: 4)
    #expect(store.parts(withOEMKey: "089116401A").map(\.quantity).sorted() == [4, 10])
}
@Test func setStatusMovesOwnedPartToInstalled() { let p = store.addOwned(oemNumber: nil, name: "Seat"); store.setStatus(.installed, for: p); #expect(p.status == .installed) }
@Test func partsAreStoredWithOEMKey() { #expect(store.addOwned(oemNumber: "10102-50FR2", name: "x").oemKey == "1010250FR2") }
```
- [ ] **Step 2:** `cd GarageVirtusKit && swift test --disable-sandbox` → fails to compile (types missing).
- [ ] **Step 3:** Implement the files above. `makeContainer` builds `ModelContainer(for: Schema(versionedSchema: GarageSchemaV1.self), migrationPlan: GarageMigrationPlan.self, configurations: ModelConfiguration(isStoredInMemoryOnly: isStoredInMemoryOnly))`. `GarageMigrationPlan.schemas = [GarageSchemaV1.self]`, `stages = []`.
- [ ] **Step 4:** `swift test --disable-sandbox` → all pass, no warnings.
- [ ] **Step 5: Commit** `git add GarageVirtusKit && git commit -m "Garage: SwiftData models, schema and store writes"`

---

### Task 2: Coverage, summary, buying a need, photos, delete

**Files:**
- Create: `GarageVirtusKit/Sources/GarageVirtusKit/Garage/GarageSummary.swift` (`Coverage`, `GarageSummary`)
- Modify: `GarageVirtusKit/Sources/GarageVirtusKit/Garage/GarageStore.swift`
- Test: `GarageVirtusKit/Tests/GarageVirtusKitTests/GarageStoreTests.swift`

**Interfaces:**
- Consumes: Task 1's `GarageStore`, `PartStatus`, models.
- Produces:
```swift
public struct Coverage: Equatable, Sendable { public let needed: Int; public let owned: Int; public var short: Int { max(0, needed - owned) } }
public struct GarageSummary: Equatable, Sendable { public let counts: [PartStatus: Int]; public let totalSpent: Decimal }
extension GarageStore {
    public func coverage(forOEMKey key: String) -> Coverage
    public func summary() -> GarageSummary                      // counts = number of rows per status; totalSpent = Σ cost of owned rows
    @discardableResult public func markBought(_ need: GaragePart, quantity: Int) -> GaragePart   // new inStorage row copying oemNumber, name, groupCode, pnc
    public func addPhoto(_ data: Data, to part: GaragePart)
    public func removePhoto(_ photo: PartPhoto)
}
```
Also make `coverage` available to views without a store: `public static func coverage(forOEMKey key: String, in parts: [GaragePart]) -> Coverage` (pure, used by `@Query` results). The instance method calls it.

- [ ] **Step 1: Write failing tests:**
```swift
@Test func noOwnedMeansFullyShort() { store.markWanted(oemNumber: "16600-1", name: "Injector", status: .need, quantity: 4)
    #expect(store.coverage(forOEMKey: "166001") == Coverage(needed: 4, owned: 0)) }
@Test func markBoughtKeepsNeedAndCoversIt() { let need = store.markWanted(oemNumber: "16600-1", name: "Injector", status: .need, quantity: 4)
    store.markBought(need, quantity: 2)
    #expect(need.status == .need); #expect(store.coverage(forOEMKey: "166001").short == 2) }
@Test func installedCountsAsOwned() { store.markWanted(oemNumber: "A-1", name: "a", status: .need, quantity: 1)
    store.addOwned(oemNumber: "A-1", name: "a", status: .installed); #expect(store.coverage(forOEMKey: "A1").short == 0) }
@Test func overCoveredNeedIsNotShort() { store.markWanted(oemNumber: "B-1", name: "b", status: .need, quantity: 4)
    store.addOwned(oemNumber: "B-1", name: "b", quantity: 5); #expect(store.coverage(forOEMKey: "B1") == Coverage(needed: 4, owned: 5)); #expect(store.coverage(forOEMKey: "B1").short == 0) }
@Test func partWithoutOEMIsIgnoredByCoverage() { store.markWanted(oemNumber: "C-1", name: "c", status: .need, quantity: 1)
    store.addOwned(oemNumber: nil, name: "custom", quantity: 3); #expect(store.coverage(forOEMKey: "C1").owned == 0) }
@Test func summaryCountsRowsAndSumsOwnedCost() {
    let a = store.addOwned(oemNumber: nil, name: "a"); a.cost = 80; let b = store.addOwned(oemNumber: nil, name: "b", status: .installed); b.cost = 20.5
    let w = store.markWanted(oemNumber: "W-1", name: "w", status: .want); w.targetPrice = 999; store.save()
    let s = store.summary(); #expect(s.totalSpent == Decimal(string: "100.5")); #expect(s.counts[.inStorage] == 1); #expect(s.counts[.want] == 1) }
@Test func deletingPartDeletesPhotos() { let p = store.addOwned(oemNumber: nil, name: "p"); store.addPhoto(Data([1, 2, 3]), to: p)
    store.delete(p); #expect(try container.mainContext.fetchCount(FetchDescriptor<PartPhoto>()) == 0) }
```
- [ ] **Step 2:** `swift test --disable-sandbox` → fails to compile.
- [ ] **Step 3:** Implement. `coverage`: `needed` = quantity of the need row (status `.need`) with that key, or 0; `owned` = Σ quantity of rows whose `status.isOwned` with that key.
- [ ] **Step 4:** All Kit tests pass.
- [ ] **Step 5: Commit** `git commit -am "Garage: coverage, summary, buying a need, photos"`

---

### Task 3: App wiring and My garage in the sidebar

**Files:**
- Modify: `GarageVirtus/GarageVirtusApp.swift` (create container with `GarageStore.makeContainer()`; `.modelContainer(container)`; `.environment(GarageStore(container:))`)
- Modify: `GarageVirtus/ViewModels/CatalogueViewModel.swift`
- Modify: `GarageVirtus/Views/SidebarView.swift`, `GarageVirtus/Views/ContentView.swift`
- Create: `GarageVirtus/Views/Garage/GarageListView.swift`
- Test: `GarageVirtusTests/CatalogueViewModelTests.swift`

**Interfaces:**
- Produces on `CatalogueViewModel`: `static func garageTag(_ status: PartStatus) -> String` (`"garage:" + status.rawValue`), `var selectedGarageStatus: PartStatus?` (parses `selection`).
- Produces `GarageListView(status: PartStatus)`.

- [ ] **Step 1: Failing tests:** `garageSelectionParsesStatus` (selection = garageTag(.need) → selectedGarageStatus == .need) and `groupSelectionIsNotGarage` (selection = a group id → nil).
- [ ] **Step 2:** `xcodebuild … test` → fails to compile.
- [ ] **Step 3:** Implement:
  - Sidebar: a "My garage" `Section` above the catalogue frames, one row per `PartStatus.allCases`, tagged `garageTag(status)`, label `status.title` plus a trailing count from `@Query var parts: [GaragePart]` (count per status computed in the view from the query result).
  - ContentView detail: if `selectedGarageStatus` is set, show `GarageListView(status:)`. Otherwise keep the existing logic. Keep the detail column's constant `.frame(minWidth: 520, …)`.
  - `GarageListView`: `@Query` filtered by `statusRaw == status.rawValue`, sorted by `name`. A `Table` with columns Name, Part number, Qty, Condition, Cost, Seller, Location (owned statuses) or Name, Part number, Qty, Have (`"\(owned) of \(needed)"` via `GarageStore.coverage(forOEMKey:in:)` over an unfiltered `@Query`), Target price (need/want). A header line with count and, for owned lists, total spent. A ＋ toolbar button adds a part with no part number (`addOwned` or `markWanted`, depending on the list's status).
- [ ] **Step 4:** Tests pass. Build has no warnings.
- [ ] **Step 5: Commit** `git commit -am "Garage: My garage sidebar section and lists"`

---

### Task 4: Part editor with photos

**Files:**
- Create: `GarageVirtus/ViewModels/GarageViewModel.swift`, `GarageVirtus/Views/Garage/PartEditorView.swift`, `GarageVirtus/Views/Garage/PhotoStrip.swift`
- Modify: `GarageVirtus/Views/Garage/GarageListView.swift`
- Test: `GarageVirtusTests/GarageViewModelTests.swift`

**Interfaces:**
- Produces: `@MainActor @Observable final class GarageViewModel { var selectedPartID: PersistentIdentifier?; func select(_ part: GaragePart); func clearSelection() }`.
- `PartEditorView(part: GaragePart)` shows the row's fields with `@Bindable`. Each edit commits through `GarageStore.save()` (on submit and on disappear).

- [ ] **Step 1: Failing tests:** `selectingPartStoresItsID` and `clearingSelectionForgetsPart` (in-memory container, saved part).
- [ ] **Step 2:** Run → fails.
- [ ] **Step 3:** Implement:
  - GarageListView: `HStack` of the Table and, when a part is selected, `Divider` + `PartEditorView` at a fixed `.frame(width: 380)`. This is the same pattern as the parts panel, with no `.inspector`.
  - Editor `Form`: Status picker (moving between owned statuses or need/want). Name, Part number, Qty (`Stepper`). For owned statuses: Cost, Seller, Seller link, Purchased (DatePicker), Condition picker, Location. For need/want: Target price, Link, plus a "Bought…" button that calls `markBought(quantity:)`. Then Notes and the PhotoStrip.
  - PhotoStrip: horizontal thumbnails (decoded with ImageIO → `CGImage` → `Image(decorative:)`, downsampled to 160 px), a remove button on each, `PhotosPicker` (`PhotosUI`, load as `Data`), and `.dropDestination(for: URL.self)` reading dropped image files.
- [ ] **Step 4:** Tests pass. Build has no warnings.
- [ ] **Step 5: Commit** `git commit -am "Garage: part editor with photos"`

---

### Task 5: Status badges and marking from the diagram's parts panel, then verify

**Files:**
- Modify: `GarageVirtus/Views/PartsInspector.swift` (PartRow, PartsInspector)
- Modify: `README.md` (a My garage section)

**Interfaces:**
- Consumes: `GarageStore.markWanted`, `addOwned`, `setStatus`, `delete`, `GarageStore.coverage(forOEMKey:in:)`, `CatalogueViewModel.garageTag`.

- [ ] **Step 1:** In `PartsInspector`, one `@Query var garageParts: [GaragePart]`. Build `[String: [GaragePart]]` by `oemKey` once per body and pass each `PartRow` its rows. Don't query per row.
- [ ] **Step 2:** PartRow badge after the price: none when untracked; "Need · have 2 of 4", "Want", or "Have 3" (sum of owned quantity) using `status.title` copy. Clicking it selects that status's garage list (`catalogue.selection = garageTag(...)`).
- [ ] **Step 3:** PartRow `.contextMenu`: "Need it", "Want it" (`markWanted`), "Have it" (`addOwned(status: .inStorage)`), "Waiting to install", "Installed" (`addOwned` with that status), and, when tracked, "Stop tracking" (deletes the need/want row only). All pass `groupCode`/`pnc` from the current callout and the catalogue part name.
- [ ] **Step 4: Verify (one pass, evidence first).**
  - `swift test --disable-sandbox` and `xcodebuild … build test` → all pass, no warnings.
  - Launch the built app via `open` (only ever kill processes under `garage-virtus/build/`). Open group 101, right-click `10102-50FR2` → Need it, open My garage → Need, check the row. Add a photo. Quit and relaunch: the row and photo are still there.
  - Open groups 101 and Rear suspension and confirm the main thread is idle with `sample`, with no layout loop.
- [ ] **Step 5:** Update the README (what My garage is and where data lives: the app container, backed up by Time Machine). Commit `git commit -am "Garage: status badges and marking from diagrams"`.
