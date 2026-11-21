# Garage Virtus: SwiftPM executable → sandboxed macOS app

## Intent
Garage Virtus is a SwiftUI catalogue viewer for the 1997 180SX (KRPS13) restoration. Today it's a SwiftPM
`executableTarget` that fakes being an app (`setActivationPolicy(.regular)`) and finds `catalogue/` via
`#filePath`. Turn it into a proper macOS app (bundle, icon, entitlements, signing) laid out so an iOS app can
share the core later.

## Goals
- `GarageVirtus.xcodeproj` with a macOS app target that builds, signs (run locally) and launches from Xcode.
- App Sandbox on. The catalogue loads automatically from a copy bundled into the app at build time.
- Existing behaviour unchanged: sidebar, diagram, inspector, search, part details, ⌘O / ⌘R.
- Core code in a local package so a future iOS target can depend on it, with unit tests.

## Non-goals
- iOS target, new features, scraper (`tools/`) or catalogue format changes.
- App Store / notarized distribution (set up later with asc-signing-setup / asc-notarization).
- Splitting AppKit-only code (NSImage, NSOpenPanel) out of the package. That waits for the iOS work.

## Anti-goals
- Any regression in browsing/searching the catalogue.
- Requiring extra tools (XcodeGen, Tuist) to open or build the project.

## Approaches
- **A. Xcode app + local package `GarageVirtusKit` (chosen).** Data in the package, views and view models in the
  app (revised from "views in the package" once it was clear the AppKit views won't be shared with iOS). Shares cleanly with iOS later and makes the code testable with `swift test`. Costs a little
  structure and `public` on the few types the app touches.
- **B. Xcode app only.** Move sources into the app target, delete `Package.swift`. Simplest today, but the split
  has to happen anyway for iOS.
- **Dropped: XcodeGen/Tuist.** Not installed. Xcode 27's synchronized folders already avoid project-file churn.

Ryan picked **A with sandbox on**.

## Design
**Layout (Model / ViewModel / View; revised 2026-11-21, Ryan picked "views in app, data in Kit")**
```
GarageVirtus.xcodeproj              app project (synchronized folders), shared scheme
GarageVirtus/                       app target
  GarageVirtusApp.swift             @main, scene, commands
  ViewModels/                       @Observable @MainActor UI state + logic
    CatalogueViewModel.swift        owns CatalogueStore; selection, search text, showUnscraped, focus,
                                    part hits, visible sidebar tree, empty state, open panel (NSOpenPanel)
    GroupDetailViewModel.swift      loads a group; schema index, selected/hovered callout, highlighted OEM,
                                    inspector/hotspot toggles; the focus and selection rules now in GroupDetailView
  Views/                            SwiftUI only: render view-model state, forward user actions
    ContentView, SidebarView, GroupDetailView, DiagramView, PartsInspector (+ PartDetailView),
    CopyableOEM                     (pure UI state like hover, zoom, "copied" tick may stay in views)
  Assets.xcassets, GarageVirtus.entitlements
GarageVirtusTests/                  Xcode unit-test target (Swift Testing), view-model tests
GarageVirtusKit/                    local Swift package: models and data only, no SwiftUI
  Sources/GarageVirtusKit/
    Models/                         SchemaGroupFile, PartPage, catalogue tree (FrameNode…GroupNode), PartRef,
                                    PartUsage
    Catalogue/                      CatalogueStore (tree, index, search, refs, load, images, part pages,
                                    open(folder:), reload), CatalogueFolderAccess
  Tests/GarageVirtusKitTests/       swift test
catalogue/, tools/                  unchanged
```
- The Kit has no SwiftUI and no UI state. `PartFocus`, `open(_ ref:)`, and the open panel move out of
  `CatalogueStore` into `CatalogueViewModel`. Kit types and members the app uses are `public`.
- "Where is this part used / what does it replace / which other Amayama pages list it", computed inside
  `PartDetailView` today, becomes a Kit query, `CatalogueStore.usage(of:) -> PartUsage`, so it's tested
  with `swift test`.
- Remove the `setActivationPolicy` / `NSApp.activate` workaround.

**Sandbox and catalogue access** (revised 2026-11-21: Ryan wants no folder picking, everything loads automatically)
- The repo's `catalogue/` is a folder reference in the app target's Resources, so every build copies it into
  `GarageVirtus.app/Contents/Resources/catalogue`. `CatalogueViewModel` opens `CatalogueStore(folder:)` on that copy.
- Entitlements: `com.apple.security.app-sandbox` only. The app reads its own bundle, so no file-access entitlements.
- No open panel, no bookmarks, no ⌘O / ⌘R commands. New scrapes appear after the next build.
- If the bundled folder is missing or has no make/model/frame folders, the detail area says so and tells you to
  scrape a group and build again.
- Later the JSON folder tree is replaced by a database. `CatalogueStore` is the seam for that.

**Build settings (builder's calls, listed here)**
- Bundle ID `com.rteves.GarageVirtus`, macOS 14.0 deployment target, hardened runtime, automatic signing with
  "Sign to Run Locally" until a personal team is set.
- Swift 6 language mode in the package and the app. Fix any concurrency diagnostics this raises. If that grows
  past small fixes, stay on Swift 5 mode and note it.
- AppIcon is an empty placeholder set. Art comes later.

**Tests**
- Kit (`swift test`): folder access, store loading, `usage(of:)`, plus `normalize`, `splitCodeName` (group and variant folders), `parseAmayamaPartURL` (with/without `sid`, non-Amayama URL).
- Decoding the checked-in `schema-group.json` and `_parts/10/1010250FR2.json` samples (copied as test fixtures).
- App (`xcodebuild test`): `CatalogueViewModel` (empty states, search hits, sidebar filtering, focus → selection)
  and `GroupDetailViewModel` (focus picks schema and callout, changing schema clears a callout not on it,
  selecting another callout clears a highlight it doesn't contain).

**Done when**
- `xcodebuild -scheme GarageVirtus build test` and `swift test` in `GarageVirtusKit/` pass.
- The app launches as a signed, sandboxed bundle, asks for the catalogue folder, browses the KRPS13 group,
  and remembers the folder after relaunch.
- README updated (open `GarageVirtus.xcodeproj`, first-launch folder prompt).
