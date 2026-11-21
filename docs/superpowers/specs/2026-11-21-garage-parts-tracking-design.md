# Garage Virtus: tracking my parts (SwiftData)

## Intent
The catalogue tells Ryan what Nissan lists for the 1997 180SX (KRPS13) restoration. It doesn't tell him what he
actually has. This adds his own records: parts he owns (what he paid, where he got them, condition, where they're
stored, photos) and where each stands: in storage, waiting to install, installed. It also adds a list of parts he
doesn't have yet: **need** (required to finish the restoration) or **want** (an upgrade). The goal is to see what's
done and what's left, and what it has cost.

Later: an iOS app and a server. Not now, but the data must move there without a redesign.

## Goals
- Record parts in five statuses: **need**, **want**, **in storage**, **waiting to install**, **installed**.
- For owned parts (in storage / waiting / installed), keep cost, seller, purchase date, condition, storage location,
  photos and notes.
- Link a part to a catalogue OEM number when there is one, and allow parts with no catalogue entry (aftermarket,
  Yahoo Auctions, RHDJapan).
- In the diagram's parts panel, show each part's status and mark it in one step (right-click → Need / Want / Have…).
- A "My garage" area that lists parts by status, with counts and total spent.
- Any part number can have any quantity and any number of owned entries (Ryan hoards bundles and duplicates).
- Have vs need: for each needed part number, show how many he owns against how many he needs ("have 2 of 4, short 2").
- Data survives rebuilds, re-scrapes and app updates. Time Machine backs it up.

## Non-goals (this round)
- Server, iOS app, iCloud sync. The model is ready for them (stable ids, timestamps), but no sync code yet.
- Multiple cars in the UI. The data has a `Car`; one car (the 180SX) is created automatically.
- Maintenance logs, price tracking, CSV import/export, barcode scanning.

## Anti-goals
- Losing data. The store must never live inside the app bundle or the catalogue folder.
- Slowing down or destabilising catalogue browsing. No new layout tricks; keep to simple SwiftUI (see the crash
  fixes of 2026-11-21).
- A complicated editor. Entering a part should take seconds.

## Constraints
- macOS 14, Swift 6, SwiftUI, MVVM: models and data in `GarageVirtusKit`, view models and views in the app.
- App Sandbox on. The SwiftData store lives in the app's container (Application Support), the default for a
  sandboxed app.
- The catalogue stays read-only bundled JSON. The garage store is separate and links to it only by OEM key
  (`CatalogueStore.normalize`, e.g. `1010250FR2`).

## Approaches (Ryan picked SwiftData)
- **SwiftData (chosen).** Apple's native store on SQLite. Plain Swift models read directly by SwiftUI, photos as
  external files, the same code on iOS, iCloud sync available later. Model changes need care: versioned schema from
  day one.
- **SQLite via GRDB.** Hand-written tables that map closely onto a future server database, with very reliable
  migrations. One third-party dependency and more code.
- **JSON files.** One file per part plus a photos folder. Simplest, but filtering and totals are hand-written in
  memory, and it would likely be replaced before the server anyway.

## Design

**Data model (GarageVirtusKit, `Garage/`).** `VersionedSchema` `GarageSchemaV1` with a `SchemaMigrationPlan`.
- `Car`: `id: UUID`, `name` ("1997 Nissan 180SX Type X"), `frame` ("KRPS13"), `variantID` ("6976"), `createdAt`,
  `updatedAt`. `@Relationship(deleteRule: .cascade, inverse: \GaragePart.car) var parts: [GaragePart]`.
- `GaragePart`: one row per need/want, or per owned purchase or bundle, in any of the five statuses. **Need and want**
  rows: one per part number per car, with the quantity required. **Owned** rows (in storage / waiting / installed):
  any number per part number, each with its own quantity, cost, seller, condition, location and photos (bundles and
  duplicates are separate rows).
  - Identity: `id: UUID`, `createdAt`, `updatedAt`.
  - What: `name`, `oemNumber: String?` (as shown, `10102-50FR2`), `oemKey: String?` (normalized, for lookups),
    `quantity: Int` (default 1), `notes: String`.
  - Status: `statusRaw: String` stored, with a computed `status: PartStatus` (`need`, `want`, `inStorage`,
    `waitingToInstall`, `installed`). Stored as a plain string so predicates filter on real stored data.
  - Purchase (owned parts): `cost: Decimal?`, `currency: String` ("USD"), `seller: String?` (free text: "Yahoo
    Auctions", "RHDJapan", …), `sellerURL: String?`, `purchasedOn: Date?`, `conditionRaw: String?` with computed
    `condition: PartCondition?` (`new`, `usedGood`, `usedFair`, `needsRebuild`, `core`), `storageLocation: String?`.
  - Wish list: `targetPrice: Decimal?`, `linkURL: String?`.
  - Catalogue context for display: `groupCode: String?`, `pnc: String?` (where it was marked from).
  - `car: Car?`. `@Relationship(deleteRule: .cascade, inverse: \PartPhoto.part) var photos: [PartPhoto]`.
- `PartPhoto`: `id: UUID`, `@Attribute(.externalStorage) var imageData: Data`, `createdAt`, `part: GaragePart?`.
- No property named `description`. Enums are `String`-backed and `Codable`.

**Store (GarageVirtusKit).** `GarageStore`, `@MainActor`, wrapping a `ModelContext`. It's the single place for
writes (each followed by an explicit `save()`), so views stay simple and tests can use an in-memory container:
- `init(container: ModelContainer)`. `static func makeContainer(isStoredInMemoryOnly: Bool) throws -> ModelContainer`
  builds the container from `GarageSchemaV1` and the migration plan.
- `defaultCar() -> Car`: fetches the car, or creates the 180SX on first launch.
- `markWanted(oemNumber:name:status:quantity:groupCode:pnc:) -> GaragePart` for need/want: creates the need/want row
  for that OEM key, or updates its status and quantity (never two need/want rows for one part number).
- `addOwned(oemNumber:name:status:quantity:groupCode:pnc:) -> GaragePart`: always creates a new owned row (a new
  purchase or bundle), even if the part number is already owned.
- `markBought(_ need: GaragePart, quantity: Int) -> GaragePart`: creates an owned row (in storage) for `quantity` and
  leaves the need row in place, so coverage is computed rather than edited by hand.
- `add(name:status:) -> GaragePart` for parts with no OEM number. `setStatus(_:for:)`, `delete(_:)`,
  `addPhoto(_:to:)`, `removePhoto(_:)`.
- `parts(withOEMKey:) -> [GaragePart]` for the diagram badges. `summary() -> GarageSummary` (counts per status,
  total spent on owned parts).
- `coverage(forOEMKey:) -> Coverage` (`needed`, `owned`, `short = max(0, needed − owned)`). `owned` sums the quantity
  of owned rows (in storage, waiting, installed) with that key. `needed` is the need row's quantity, or 0.

**App.**
- The app creates the `ModelContainer` once (`.modelContainer(...)`) and a `GarageStore` passed through the
  environment.
- Sidebar: a **My garage** section above the catalogue with Need, Want, In storage, Waiting to install, Installed,
  each with a count. Selecting one shows that list in the detail column.
- Garage list (detail column): a `Table` filtered by status via `@Query`, with columns for name, part number,
  quantity, condition, cost, seller and location. The Need list adds a "Have" column ("2 of 4") and shows fully
  covered needs dimmed. A header shows the count and total spent. A ＋ button adds a part with no
  part number.
- Part editor: selecting a row opens a form in the right-hand panel, the same fixed-width panel the diagrams use:
  status, name, part number, quantity, purchase fields (shown for owned statuses), wish-list fields (for need/want),
  notes, and a photo strip. Photos are added by drag and drop or a Photos picker.
- Catalogue parts panel: each part row shows a small status badge when the part is tracked. Right-click offers
  Need, Want, Have (in storage), Waiting to install, Installed, and Remove. Clicking the badge opens the editor.
- View models: `GarageViewModel` (selected status, selected part, sheet state) in `GarageVirtus/ViewModels/`.
  Lists read through `@Query` in views, because SwiftData's `@Query` only works in views. Writes go through
  `GarageStore`.

**Tests.**
- Kit, in-memory container: marking need/want twice for one OEM updates rather than duplicates; adding owned rows for
  one OEM always creates new rows; markBought creates an owned row; coverage (none owned, partly covered, over-covered,
  installed counts as owned, other OEM numbers ignored);
  status changes; summary counts and total spent (owned only, sum of cost); delete cascades photos; the default
  car is created once.
- App: `GarageViewModel` selection behaviour.

**Done when.**
- Ryan can mark a part from a diagram, see it under My garage, fill in what he paid, where from, its condition,
  where it's stored and a photo, move it to waiting and then installed, and see the totals.
- The data is still there after rebuilding the app and re-running the Megazip converter.

## Calls made by Claude (Ryan can override)
- One `GaragePart` model with a status, rather than separate "owned" and "wish list" tables. Need/want are one row per
  part number; owned rows are per purchase or bundle.
- Installed parts count toward covering a need (they fill it).
- Statuses and condition values listed above. Condition is a fixed list, and the seller is free text.
- Photos inside the SwiftData store (external storage), not loose files.
- Only the 180SX car is created. The other three cars come later.
- Totals count owned parts only (in storage, waiting, installed). `cost` is the price paid for that row (the bundle
  or purchase as a whole), so total spent is the sum of `cost`, not cost × quantity.
- Photos are added by drag and drop and the Photos picker. A file-picker button needs the sandbox's user-selected
  file read permission, so it's left out unless wanted.
