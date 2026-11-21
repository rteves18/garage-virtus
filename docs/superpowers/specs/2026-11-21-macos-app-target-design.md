# Garage Virtus: SwiftPM executable → sandboxed macOS app

## Intent
Garage Virtus is a SwiftUI catalogue viewer for the 1997 180SX (KRPS13) restoration. Today it's a SwiftPM
`executableTarget` that fakes being an app (`setActivationPolicy(.regular)`) and finds `catalogue/` via
`#filePath`. Turn it into a proper macOS app (bundle, icon, entitlements, signing) laid out so an iOS app can
share the core later.

## Goals
- `GarageVirtus.xcodeproj` with a macOS app target that builds, signs (run locally) and launches from Xcode.
- App Sandbox on. The catalogue folder is chosen by the user once and remembered with a security-scoped bookmark.
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
- **A. Xcode app + local package `GarageVirtusKit` (chosen).** Thin app target; models, store and views live in
  the package. Shares cleanly with iOS later and makes the code testable with `swift test`. Costs a little
  structure and `public` on the few types the app touches.
- **B. Xcode app only.** Move sources into the app target, delete `Package.swift`. Simplest today, but the split
  has to happen anyway for iOS.
- **Dropped: XcodeGen/Tuist.** Not installed. Xcode 27's synchronized folders already avoid project-file churn.

Ryan picked **A with sandbox on**.

## Design
**Layout**
```
GarageVirtus.xcodeproj            app project (synchronized folder for GarageVirtus/)
GarageVirtus/                     app target: GarageVirtusApp.swift, Assets.xcassets (AppIcon, AccentColor),
                                  GarageVirtus.entitlements
GarageVirtusKit/                  local Swift package
  Package.swift                   macOS 14, library product GarageVirtusKit
  Sources/GarageVirtusKit/        Models/, Store/, Views/ (moved from GarageVirtus/Sources/GarageVirtus)
  Tests/GarageVirtusKitTests/     Swift Testing
catalogue/, tools/                unchanged
```
- The app target holds only `@main` + scene/commands. `ContentView`, `CatalogueStore` and the methods the
  commands call become `public`. Everything else stays internal.
- Remove the `setActivationPolicy` / `NSApp.activate` workaround.

**Sandbox and catalogue access**
- Entitlements: `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-only`,
  `com.apple.security.files.bookmarks.app-scope`. No network entitlement: links open in the browser.
- `CatalogueStore` stores a security-scoped bookmark (read-only) of the chosen folder in UserDefaults, resolves it
  at launch, and calls `startAccessingSecurityScopedResource` (stopping the previous one when the folder changes).
  A stale bookmark is recreated, and an unresolvable one clears the saved folder.
- Remove the `#filePath` default and the old path-string default.
- With no folder chosen, the detail area shows "Choose your catalogue folder" with a **Choose Catalogue Folder…**
  button (same as ⌘O). The open panel starts in the repo's `catalogue/` when that folder exists.

**Build settings (builder's calls, listed here)**
- Bundle ID `com.rteves.GarageVirtus`, macOS 14.0 deployment target, hardened runtime, automatic signing with
  "Sign to Run Locally" until a personal team is set.
- Swift 6 language mode in the package and the app. Fix any concurrency diagnostics this raises. If that grows
  past small fixes, stay on Swift 5 mode and note it.
- AppIcon is an empty placeholder set. Art comes later.

**Tests (GarageVirtusKitTests)**
- `normalize`, `splitCodeName` (group and variant folders), `parseAmayamaPartURL` (with/without `sid`, non-Amayama URL).
- Decoding the checked-in `schema-group.json` and `_parts/10/1010250FR2.json` samples (copied as test fixtures).

**Done when**
- `xcodebuild -scheme GarageVirtus build` and `swift test` in `GarageVirtusKit/` pass.
- The app launches as a signed, sandboxed bundle, asks for the catalogue folder, browses the KRPS13 group,
  and remembers the folder after relaunch.
- README updated (open `GarageVirtus.xcodeproj`, first-launch folder prompt).
