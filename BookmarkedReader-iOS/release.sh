#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="BookmarkedReader"
SCHEME="BookmarkedReader"
PROJECT="BookmarkedReader.xcodeproj"
BUNDLE_ID="com.swairshah.BookmarkedReader"

BUILD_DIR="build/release"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
IPA="$EXPORT_DIR/$APP_NAME.ipa"
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"

# --- Configuration (env vars) --------------------------------------------------
# Signing/archive uses automatic signing via your Apple ID in Xcode → Settings →
# Accounts (team $TEAM_ID). Upload uses ONE of:
#   A) App-specific password:  APPLE_EMAIL + APPLE_APP_PASSWORD   (what you have)
#   B) App Store Connect API key: ASC_KEY_ID + ASC_ISSUER_ID
#      (.p8 at ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8)
TEAM_ID="${TEAM_ID:-${APPLE_TEAM_ID:-}}"
REAL_DB="${REAL_DB:-$HOME/Library/Application Support/Bookmarked/bookmarks.json}"
APPLE_EMAIL="${APPLE_EMAIL:-}"
APPLE_APP_PASSWORD="${APPLE_APP_PASSWORD:-}"
ASC_KEY_ID="${ASC_KEY_ID:-}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
echo -e "${GREEN}=== $APP_NAME — TestFlight Release ===${NC}"

if [ -z "$TEAM_ID" ]; then
    echo -e "${RED}Team ID not set.${NC} Run with APPLE_TEAM_ID=8B9YURJS4G (or TEAM_ID=...)."
    exit 1
fi

# Decide upload method
UPLOAD_METHOD="none"
if [ -n "$APPLE_EMAIL" ] && [ -n "$APPLE_APP_PASSWORD" ]; then
    UPLOAD_METHOD="password"
    export APPLE_APP_PASSWORD            # so altool's "@env:" reference can read it
elif [ -n "$ASC_KEY_ID" ] && [ -n "$ASC_ISSUER_ID" ] && [ -f "$KEY_PATH" ]; then
    UPLOAD_METHOD="apikey"
fi

BUILD_NUMBER="$(date +%Y%m%d%H%M)"
echo -e "Team: ${GREEN}$TEAM_ID${NC}   Build: ${GREEN}$BUILD_NUMBER${NC}   Upload: ${GREEN}$UPLOAD_METHOD${NC}"
if [ "$UPLOAD_METHOD" = "none" ]; then
    echo -e "${YELLOW}No upload credentials — will archive + export only.${NC}"
    echo -e "${YELLOW}Set APPLE_EMAIL + APPLE_APP_PASSWORD (or the ASC_* API key) to upload.${NC}"
fi

# xcodebuild auth args: only the API key can drive provisioning headlessly.
# With the password method, automatic signing uses your Xcode-stored Apple ID.
AUTH_ARGS=()
if [ "$UPLOAD_METHOD" = "apikey" ]; then
    AUTH_ARGS=(-authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

rm -rf "$ARCHIVE" "$EXPORT_DIR"
mkdir -p "$BUILD_DIR"

# Bundle a snapshot of your real library so it shows on a physical device
# (the Simulator-only Documents copy in run.sh doesn't apply to TestFlight builds).
if [ -f "$REAL_DB" ]; then
    cp "$REAL_DB" "BookmarkedReader/Resources/bookmarks.json"
    echo -e "${GREEN}Bundled your library into the build:${NC} $REAL_DB"
else
    echo -e "${YELLOW}No library at $REAL_DB — this build will ship the bundled sample.${NC}"
fi

# --- 1. Archive (Release, signed for a generic iOS device) ---------------------
echo -e "${YELLOW}Archiving...${NC}"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    archive

# --- 2. Export a signed .ipa ---------------------------------------------------
cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>export</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
    <key>uploadSymbols</key><true/>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo -e "${YELLOW}Exporting .ipa...${NC}"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_PLIST" \
    -allowProvisioningUpdates \
    ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}

if [ ! -f "$IPA" ]; then
    IPA="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' | head -1)"
fi
if [ -z "${IPA:-}" ] || [ ! -f "$IPA" ]; then
    echo -e "${RED}Export failed — no .ipa produced.${NC}"
    exit 1
fi
echo -e "${GREEN}Exported:${NC} $IPA"

if [ "$UPLOAD_METHOD" = "none" ]; then
    echo -e "${YELLOW}Done (no upload). Drag the .ipa into Transporter, or set credentials and re-run.${NC}"
    exit 0
fi

# --- 3. Upload to App Store Connect / TestFlight -------------------------------
if [ "$UPLOAD_METHOD" = "password" ]; then
    UP_ARGS=(-u "$APPLE_EMAIL" -p "@env:APPLE_APP_PASSWORD")
else
    UP_ARGS=(--apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID")
fi

echo -e "${YELLOW}Validating...${NC}"
xcrun altool --validate-app -t ios -f "$IPA" "${UP_ARGS[@]}"

echo -e "${YELLOW}Uploading to TestFlight...${NC}"
xcrun altool --upload-app -t ios -f "$IPA" "${UP_ARGS[@]}"

echo -e "${GREEN}Done.${NC} Build $BUILD_NUMBER uploaded."
echo -e "It appears in App Store Connect → TestFlight after ~5–15 min of processing."
echo -e "Add yourself as an Internal Tester, then install via the TestFlight app."
