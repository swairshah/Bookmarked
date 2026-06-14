# Bookmarked Reader (iOS)

A minimal, reading-first iOS companion to the Bookmarked macOS app. It does one
thing well: open the library and read. No capture, no editing, no in-app web
browser — the way Safari's reader mode is just for reading.

## Requirements

- Xcode 16 or later (the project uses a synchronized file group, `objectVersion 77`)
- iOS 17.0+ deployment target

## Open & run

```
open BookmarkedReader.xcodeproj
```

Pick an iPhone simulator and hit Run. It launches straight into the library,
seeded with `BookmarkedReader/Resources/sample-bookmarks.json` so there's
something to read on first launch.

## What it does

- **Library** — a searchable list of bookmarks. Each row shows the favicon (or a
  tinted kind glyph), the title, `Kind · Creator`, and the date — the same layout
  as the Mac sidebar. Search uses the same token-AND matching as the Mac app.
- **Reader** — tapping a bookmark opens it:
  - Captured pages (`readerHTML`) render in a `WKWebView` using the **exact same
    stylesheet and KaTeX setup** as the macOS reader, so an article looks identical
    on both. Math, code blocks, blockquotes, and images all carry over.
  - Everything else renders in a native SwiftUI text reader (the same `#`-heading /
    bullet / paragraph block model as the Mac app), which is the snappiest path.
  - A typography menu (`Aa`) switches face (Serif / Sans / Mono → New York / SF Pro /
    SF Mono) and text size; choices persist via `@AppStorage`.
- **Web stays in the browser** — web pages and repos get an "Open in Browser"
  action (and "Copy Link") instead of an embedded web view. Links tapped inside the
  reader also open in the system browser.
- **Notes are minimal** — read-only, tucked behind the overflow menu, and only shown
  when a bookmark actually has a note.

Intentionally **out of scope** (for now): capturing/adding bookmarks, deleting,
editing reader content or notes. This app only reads.

## The shared "database"

The Mac app stores its library as a JSON array of `BookmarkItem` at
`~/Library/Application Support/Bookmarked/bookmarks.json` (ISO-8601 dates, base64
`Data` for favicons). This app uses the **identical** model
(`Models/BookmarkItem.swift`) and decoding, so it reads that exact file format.

`BookmarkStore` looks for `bookmarks.json` in this order:

1. **App Group container** — set `BookmarkStore.appGroupID` once provisioning is set up
2. **App's Documents folder** — drop a real `bookmarks.json` export here to test
   against your actual library (Files app → On My iPhone → Bookmarked Reader)
3. **Bundled `sample-bookmarks.json`** — the seed data

### Pointing at real data quickly

Copy your Mac's `~/Library/Application Support/Bookmarked/bookmarks.json` into the
app's Documents directory (via Xcode's Devices window, the Files app, or a drag in
the simulator), then pull-to-refresh the list.

## Sync roadmap (later)

Because both apps share one schema, sync is a storage swap, not a rewrite:

- **iCloud / shared container** — write `bookmarks.json` into an App Group or the
  iCloud container; set `BookmarkStore.appGroupID` and the store reads it with no
  other changes. The macOS app would write to the same shared location.
- **CloudKit / file coordination** — if you outgrow a single JSON file, the
  `BookmarkItem` model is already `Codable` and stable, so a record-based store can
  map 1:1 onto it.

The store is read-only here by design, which keeps the eventual sync direction
(Mac writes, iOS reads) simple to reason about.

## Design system

UI is built on tokens/components from your `ios-native` DesignSystem package
(`DSColor`, `DSFont`, `DSSpacing`, `DSRadius`, `DSTag`, row backgrounds). They're
**vendored** into `BookmarkedReader/DesignSystem/` (verbatim) so the project opens
and runs with no external checkout.

To make the package the single source of truth instead, delete
`BookmarkedReader/DesignSystem/` and add the local package as a dependency:

1. File → Add Package Dependencies… → Add Local… →
   `/Users/swair/work/UX/design-systems/ios-native`
2. Add the `DesignSystem` product to the app target
3. `import DesignSystem` and make the vendored types `public` references

## Project layout

```
BookmarkedReader/
├── App/            BookmarkedReaderApp.swift
├── Models/         BookmarkItem.swift, BookmarkKind.swift   (shared schema)
├── Store/          BookmarkStore.swift                      (read-only loader)
├── Library/        LibraryView.swift, BookmarkRow.swift
├── Reader/         ReaderScreen, ReaderHTMLView (WKWebView), ReaderTextView, ReaderFontPreferences
├── DesignSystem/   DSTokens.swift, DSComponents.swift       (vendored)
├── Resources/      sample-bookmarks.json
└── Assets.xcassets AppIcon, AccentColor
```
