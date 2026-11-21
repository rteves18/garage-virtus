# Garage Virtus – macOS catalogue viewer

A SwiftUI app that browses `../catalogue/` and replicates the Amayama EPC experience:
diagram with clickable callouts, and an inspector listing every OEM part for the selected callout.

## Run

```sh
cd GarageVirtus
swift run            # builds and launches the app
# or
open Package.swift   # opens in Xcode → ⌘R
```

Requires macOS 14+ (Xcode 15.3+ / Swift 5.10).

The app reads `<repo>/catalogue` by default. Use **File → Open Catalogue Folder… (⌘O)** to point it elsewhere,
and **File → Reload Catalogue (⌘R)** after scraping more groups.

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
Models live in `Sources/GarageVirtus/Models/SchemaGroupFile.swift`.
