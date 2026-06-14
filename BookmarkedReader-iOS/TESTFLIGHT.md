# Shipping Bookmarked Reader to TestFlight

One-time setup in App Store Connect, then `./release.sh` builds, signs, and uploads.
Bundle ID: `com.swairshah.BookmarkedReader`.

## One-time setup

### 1. Register the App ID
developer.apple.com → Certificates, Identifiers & Profiles → **Identifiers** → **+** →
App IDs → App → Bundle ID = `com.swairshah.BookmarkedReader`.
(Automatic signing will create the distribution certificate and provisioning
profile for you on first run, so you don't need to make those by hand.)

### 2. Create the app record
App Store Connect → **Apps** → **+** → New App:
- Platform: iOS
- Name: `Bookmarked Reader`
- Bundle ID: `com.swairshah.BookmarkedReader`
- SKU: anything unique, e.g. `bookmarked-reader`

### 3. Sign into Xcode (for signing)
Xcode → **Settings → Accounts** → add `swairshah@gmail.com`, with team `8B9YURJS4G`
available. Automatic signing uses this account to create the distribution
certificate and provisioning profile during archive. (The app-specific password
below is only for the *upload* step — it doesn't drive signing.)

### 4. Upload credentials — pick one

**Option A — app-specific password (what you have):**
- `APPLE_EMAIL` = `swairshah@gmail.com`
- `APPLE_APP_PASSWORD` = your app-specific password (`xxxx-xxxx-xxxx-xxxx`, created at
  [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords)

**Option B — App Store Connect API key (alternative):**
App Store Connect → Users and Access → Integrations → App Store Connect API → **+**
(App Manager role). Download `AuthKey_XXXXXXXXXX.p8` (one-time) and note the Key ID +
Issuer ID, then:
```bash
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
```

Your Team ID (`8B9YURJS4G`) is in App Store Connect → Membership.

## Release a build

With the app-specific password (Option A):
```bash
APPLE_TEAM_ID=8B9YURJS4G \
APPLE_EMAIL=swairshah@gmail.com \
APPLE_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx \
./release.sh
```

Or with the API key (Option B):
```bash
APPLE_TEAM_ID=8B9YURJS4G \
ASC_KEY_ID=XXXXXXXXXX \
ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
./release.sh
```

The script:
1. Stamps the build number with a timestamp (so each upload is unique),
2. Archives Release for a generic iOS device with automatic signing,
3. Exports a signed App Store `.ipa`,
4. Validates and uploads it to App Store Connect.

Tip: export these in your shell profile so you can just run `./release.sh`. Running
with only `APPLE_TEAM_ID` set archives + exports the `.ipa` but skips the upload
(useful for a dry run). The password is read via `@env:` so it never appears in the
command line or process list.

## Install on your phone

1. After upload, wait ~5–15 min while App Store Connect processes the build
   (App Store Connect → your app → **TestFlight**).
2. Add yourself as an **Internal Tester**: TestFlight tab → Internal Testing →
   add your Apple ID. Internal testing needs **no beta review**, so it's instant.
3. Install **TestFlight** from the App Store on your iPhone, sign in with the same
   Apple ID, and the build appears there to install.

## Export compliance

On the first build, App Store Connect asks about encryption. This app only makes
standard HTTPS requests (the KaTeX CDN), which is exempt — answer **"No"** to
"Does your app use non-exempt encryption?" You can set this once per version, or
add `ITSAppUsesNonExemptEncryption = NO` to the app's Info settings to stop being
asked.

## Notes

- **Internal vs external testers:** internal (up to 100 people on your team) is
  instant. External testers (up to 10,000 via a public link) require a one-time
  beta review per version — only needed if you want to share beyond yourself.
- **Bumping the marketing version** (e.g. 1.0 → 1.1): change `MARKETING_VERSION`
  in the target build settings. The build number is handled automatically.
- **First archive is slow** (whole-module Release build + provisioning); later
  runs are faster.
