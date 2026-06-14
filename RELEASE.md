# Releasing Bookmarked (macOS)

Public macOS distribution is **Developer ID + notarization**, shipped as a DMG via
your Homebrew tap. (Not the Mac App Store — the sandbox it requires would break
the Accessibility / Apple Events capture.)

## 1. Bump the version

Edit `scripts/build-app.sh` → `VERSION="x.y.z"` (sets `CFBundleShortVersionString`).

## 2. Build, sign, notarize, package

```bash
./scripts/release.sh
```

This builds the release `.app`, signs it with `Developer ID Application: Swair
Rajesh Shah (8B9YURJS4G)` under the hardened runtime with
`Sources/BookmarkedApp/Bookmarked.entitlements`, notarizes with `notarytool`,
staples, and produces `dist/Bookmarked-VERSION.dmg` (also signed + notarized +
stapled). It prints the DMG's SHA-256.

Requires `APPLE_APP_PASSWORD` in `./.env` or `~/.env`, and `create-dmg`
(`brew install create-dmg`). Use `--skip-notarize` for a quick local test build.

Verify:
```bash
xcrun stapler validate dist/Bookmarked-VERSION.dmg
spctl --assess --type install --verbose=2 dist/Bookmarked-VERSION.dmg
```

## 3. Tag and publish a GitHub release

```bash
git tag -a vVERSION -m "Release vVERSION" && git push origin main vVERSION
gh release create vVERSION dist/Bookmarked-VERSION.dmg \
  --title "Bookmarked vVERSION" --notes "Release notes"
```

## 4. Update the Homebrew cask

```bash
shasum -a 256 dist/Bookmarked-VERSION.dmg   # also printed by release.sh
# Edit ~/work/projects/homebrew-tap/Casks/bookmarked.rb: bump version + sha256.
cd ~/work/projects/homebrew-tap
git commit -am "Update bookmarked to VERSION" && git push
```

Users then install with `brew install --cask swairshah/tap/bookmarked`.

## Notes / follow-ups

- **Repo URL:** the cask points at `github.com/swairshah/bookmarked` — adjust if
  the repo name differs.
- **iCloud sync for Mac-only users:** the Mac app currently writes to the iCloud
  container's on-disk path, which exists once the entitled iOS app has created it
  on that account. For someone who uses *only* the Mac app, give it its own iCloud
  entitlement + a Developer-ID provisioning profile carrying the
  `iCloud.com.swairshah.Bookmarked` container, then sign with that profile. That's
  a follow-up to wire into `release.sh`.
- **iOS** is distributed separately via the App Store / TestFlight (see TESTFLIGHT.md),
  not Homebrew.
