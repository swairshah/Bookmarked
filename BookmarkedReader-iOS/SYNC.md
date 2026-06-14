# Sync — file-per-bookmark over iCloud

The Mac app (writer) and the iOS app (reader) share one iCloud container and
exchange **one JSON file per bookmark**, so only changed items move — adding an
article syncs one small file, not the whole library.

## How it works

- **Container:** `iCloud.com.swairshah.Bookmarked`, shared by both apps (the
  container ID is independent of each app's bundle ID).
- **Layout:** `<container>/Documents/Bookmarks/<uuid>.json` — each file is one
  `BookmarkItem` in the same Codable schema both apps already use (ISO-8601 dates).
- **Per-user:** there is no server and no shared data between people. Each user's
  files live in *their* private iCloud; Apple syncs them across that user's
  devices and keeps everyone isolated. Install both apps + be signed into iCloud →
  your data appears on both.
- **macOS (writer):** on launch and on every change, the app writes/updates the
  changed `<uuid>.json` files and deletes files for removed bookmarks
  (`ICloudMirror`). It writes only when a file's contents actually changed.
- **iOS (reader):** watches `Documents/Bookmarks/*.json` with `NSMetadataQuery`
  (`ICloudBookmarkSync`), downloads and decodes what's there, and updates the
  library live. Until iCloud has delivered ≥1 item it shows the bundled snapshot,
  then iCloud becomes the source of truth.

## One-time setup

### iOS App ID — enable iCloud
The iOS target already ships `BookmarkedReader.entitlements` requesting the
container. In the Apple Developer portal:

1. Identifiers → `com.swairshah.BookmarkedReader` → enable **iCloud** (CloudKit /
   iCloud Documents).
2. Create the container **`iCloud.com.swairshah.Bookmarked`** and assign it to the App ID.

Then `./release.sh` (automatic signing) provisions it. If the archive fails on
the iCloud entitlement, it's because the container/capability isn't enabled yet —
do the two steps above and re-run. Installing the iOS app is what **creates** the
container for a user's iCloud account.

### macOS app — nothing to sign
Bookmarked is a non-sandboxed menu-bar app (Accessibility + Apple Events for
capture), and the App Sandbox that iCloud's entitled API pairs with would break
capture. So the Mac app instead writes directly into the container's on-disk
location:

```
~/Library/Mobile Documents/iCloud~com~swairshah~Bookmarked/Documents/Bookmarks/
```

A non-sandboxed app can write there, and the iCloud daemon syncs those files. This
works once the container exists on the Mac — which happens automatically after the
iOS app (entitled) has created it for the same iCloud account and iCloud Drive is
enabled on the Mac. No entitlement or `build-app.sh` signing change is required.

## Testing end to end

1. Enable iCloud + create the container (above); `./release.sh`; install the iOS
   app on a device signed into your iCloud. Launch it once so the container is
   created.
2. On the Mac (same iCloud account, iCloud Drive on), run the Bookmarked app. It
   writes one file per bookmark into the path above.
3. Watch them appear: `ls ~/Library/Mobile\ Documents/iCloud~com~swairshah~Bookmarked/Documents/Bookmarks/`
   (or the iCloud Drive section of Finder).
4. The iOS library updates within seconds-to-minutes; pull-to-refresh forces a
   re-read.

## Local-network (peer-to-peer) sync

In addition to iCloud, the apps sync directly over the local network via
**Multipeer Connectivity** — no cloud, no account, data never leaves your devices.

- Service type `bkmkd-sync` (declared in each app's `NSBonjourServices`).
- The **Mac advertises** and is the source of truth (`PeerSync` in the macOS app).
  The **iOS app browses**, connects, and sends a manifest of what it has
  (`{id, updatedAt}`); the Mac replies with only the records the phone is missing
  or has stale, plus ids to delete. It re-pushes when the Mac library changes
  while connected. One-way (Mac → iOS) today, since iOS is read-only.
- Both devices must be on the same Wi-Fi with both apps open. On first run iOS
  prompts for **Local Network** permission — allow it.

**Pairing (so only your own devices sync).** Discovery + transport encryption
isn't enough to know *who* a peer is, so devices authenticate with a shared
**pairing code**. The Mac generates one on first launch and logs it
(`Bookmarked sync pairing code: ABC123`) — read it from Console / the terminal.
In the iOS app, tap the Wi-Fi button (top-right of the library) and enter that
code. Devices broadcast only a hash of the code for discovery; the code itself is
proven via an HMAC challenge over the encrypted session, so a different user (or a
stranger on the same Wi-Fi) with a different code exchanges nothing. No code set →
sync is off.

Testing: install the iOS build on a real device (Multipeer is unreliable in the
Simulator), pair with the Mac's code, open both apps on the same Wi-Fi, and the
phone mirrors the Mac's library within a few seconds. Multiple devices (iPhone +
iPad + Mac) all sharing the code all sync, with the Mac as hub. It complements
iCloud — whichever delivers an update first wins by `updatedAt`.

## Limitations / next steps

- **One writer.** macOS writes, iOS reads — no merge conflicts. If iOS should
  write later, add conflict handling (last-writer-wins by `updatedAt`) or move to
  CloudKit.
- **Content travels with each file.** `readerHTML`/`contentText` are inside each
  `<uuid>.json`, so a heavy article is one heavier file (still only synced when it
  changes). If libraries get large, split metadata from content into a separate
  `<uuid>.content.json` fetched lazily.
- **Delete-to-zero.** Once iCloud is the source, an empty container shows an empty
  library (correct). Before the first sync, the bundled snapshot shows instead.
- **Latency.** iCloud Drive propagation is typically seconds but not guaranteed
  instant; CloudKit + push would be needed for real-time.
