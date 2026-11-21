# Garage Virtus

A macOS app for browsing the 1997 Nissan 180SX (KRPS13) parts catalogue scraped from Amayama: exploded diagrams
with clickable callouts, every OEM part per callout, and part-number search. Built for a full restoration.

## Run

Open `GarageVirtus.xcodeproj` in Xcode (27+) and press ⌘R. Requires macOS 14+.

The app loads the catalogue automatically: every build copies this repo's `catalogue/` folder into the app,
and the app reads that copy (read-only, sandboxed). After scraping more groups, build and run again (⌘R in Xcode).

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
