# Garage Virtus

A macOS app for browsing the 1997 Nissan 180SX (KRPS13) parts catalogue scraped from Amayama: exploded diagrams
with clickable callouts, every OEM part per callout, and part-number search. Built for a full restoration.

## Run

Open `GarageVirtus.xcodeproj` in Xcode (27+) and press ⌘R. Requires macOS 14+.

The app loads the catalogue automatically: every build copies this repo's `catalogue/` folder into the app,
and the app reads that copy (read-only, sandboxed). After scraping more groups, build and run again (⌘R in Xcode).

## My garage

Track your own parts alongside the catalogue. Statuses: **Need**, **Want**, **In storage**, **Waiting to install**, and **Installed**.

- **Right-click a part** in a diagram's parts panel to mark it: Need it, Want it, Have it, Waiting to install, or Installed. A badge then shows where the part stands, e.g. "Need · have 2 of 4". Click the badge to open the list.
- **My garage in the sidebar** lists parts by status, with counts and total spent. Select a row to edit what you paid, the seller, condition, storage location, notes, and photos (add from Photos or drop image files).
- **Quantities:** need/want is one row per part number, with the quantity you need. Owned parts are one row per purchase or bundle, so duplicates are fine. "Have X of Y" compares them, and installed parts count as owned.
- **Storage:** data is kept with SwiftData in the app's container (`~/Library/Containers/com.rteves.GarageVirtus/Data/Library/Application Support/default.store`), separate from the bundled catalogue. Rebuilds and re-scrapes never touch it, and Time Machine backs it up.

## Cars

The car picker at the top of **My garage** in the sidebar switches cars. The app remembers your choice. **Manage cars** (the car icon) adds, renames, or deletes cars. Deleting a car deletes its parts. Lists, badges, and the overview always show the current car. **Overview** shows counts per status, total spent, and the needs still short.

## Ask AI

In a schema group, turn on **Ask AI** in the toolbar to chat with Claude (`claude-opus-5-5`) about the diagrams on screen. For example: "What hardware do I need?" or "Which of these are discontinued?"

- **Lists and totals:** when Claude builds a parts list, the app prices it from the catalogue and shows the total, so totals are never made up. **Add all to Need** records the list in My garage.
- **What Claude sees:** the visible schemas (the current year window), their parts, prices, and what you have or need for the current car.
- **Setup:** add your Anthropic API key in **Settings (⌘,)**. It's stored in your Keychain. Each question is a paid API request.

## Project layout (Model / ViewModel / View)

```
GarageVirtus/            macOS app target
  ViewModels/            @Observable view models: CatalogueViewModel, GroupDetailViewModel
  Views/                 SwiftUI views (render view-model state, forward actions)
GarageVirtusTests/       view-model tests (Swift Testing)
GarageVirtusKit/         Swift package: catalogue models, loading, search (shared with a future iOS app)
catalogue/               scraped data (see catalogue/README.md)
tools/amayama/           browser scrapers that write catalogue/
```

## Tests

```sh
xcodebuild -project GarageVirtus.xcodeproj -scheme GarageVirtus \
  -destination 'platform=macOS' test          # view-model tests (or ⌘U in Xcode)
cd GarageVirtusKit && swift test              # Kit tests
```

## Using it

- **Sidebar:** variants → categories → schema groups. Only scraped groups show by default; toggle
  **Show unscraped** to see the full folder tree.
- **Diagram:** click a callout label to select it. Hover shows the callout name. Pinch or ⌘+ / ⌘- / ⌘0 to zoom.
  Click empty space to clear the selection.
- **Inspector:** every callout on the schema with its OEM numbers, applicability, period, qty, price/status and
  replacements. Selecting on the diagram scrolls and highlights here; hovering or clicking a card highlights the diagram.
- **Search:** the sidebar field takes a group code/name, an OEM number in any form (`10102-50FR2`, `1010250fr2`,
  partial `50FR`), or a pasted Amayama part link (`…/part/nissan/1010250fr2?sid=101B_001_1.R10102`). Part hits open
  the right variant, schema and callout and highlight the part in yellow.
- **Part details:** the ⓘ next to an OEM number shows where that number is used across the catalogue, what it
  replaces and what replaces it, with jump links.
- **Schemas:** pages with more than one schema get a segmented picker in the header.

## Data contract

`catalogue/<make>/<model>/<frame>/<variant>/<category>/<group>/schema-group.json` (written by
`tools/amayama/scrape_page.js`) and diagrams in `catalogue/<make>/<model>/<frame>/_images/`.
Models live in `GarageVirtusKit/Sources/GarageVirtusKit/Models/`.
