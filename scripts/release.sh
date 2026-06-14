#!/bin/bash
# Build, sign (Developer ID), notarize, and package Bookmarked.app as a DMG.
#
# Prerequisites:
#   - Developer ID Application certificate in the keychain
#   - APPLE_APP_PASSWORD (app-specific password) in ./.env or ~/.env
#   - create-dmg: brew install create-dmg
#
# Usage:
#   ./scripts/release.sh
#   ./scripts/release.sh --skip-notarize   # faster, for local testing (not distributable)
set -e
cd "$(dirname "$0")/.."

# Load credentials (repo .env first, then ~/.env).
[ -f .env ] && source .env
[ -f "$HOME/.env" ] && source "$HOME/.env"

APP_NAME="Bookmarked"
BUNDLE_ID="com.swair.bookmarked"
SIGNING_IDENTITY="Developer ID Application: Swair Rajesh Shah (8B9YURJS4G)"
TEAM_ID="8B9YURJS4G"
APPLE_ID="swairshah@gmail.com"
ENTITLEMENTS="Sources/BookmarkedApp/Bookmarked.entitlements"

APP_PATH=".build/$APP_NAME.app"
CLI_PATH="$APP_PATH/Contents/MacOS/bookmarkedctl"

SKIP_NOTARIZE=false
[ "${1:-}" = "--skip-notarize" ] && SKIP_NOTARIZE=true

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
echo -e "${GREEN}=== Bookmarked Release Build ===${NC}"

if [ "$SKIP_NOTARIZE" = false ] && [ -z "${APPLE_APP_PASSWORD:-}" ]; then
    echo -e "${RED}APPLE_APP_PASSWORD not set (.env or ~/.env). Or run with --skip-notarize.${NC}"
    exit 1
fi
if ! command -v create-dmg &>/dev/null; then
    echo -e "${YELLOW}Installing create-dmg...${NC}"; brew install create-dmg
fi

# --- 1. Build the .app (release) ----------------------------------------------
echo -e "${YELLOW}Building app...${NC}"
rm -rf dist; mkdir -p dist
./scripts/build-app.sh

# --- 2. Sign with Developer ID + hardened runtime -----------------------------
echo -e "${YELLOW}Signing...${NC}"
# SwiftPM's resource ".bundle" is a plain resource directory, not a signable
# CFBundle. It is sealed by the outer app signature.
[ -f "$CLI_PATH" ] && codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$CLI_PATH"
codesign --force --options runtime \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    "$APP_PATH"

echo -e "${YELLOW}Verifying signature...${NC}"
codesign --verify --verbose=2 "$APP_PATH"
spctl --assess --verbose=2 "$APP_PATH" || true

VERSION=$(defaults read "$(pwd)/$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)
DMG_PATH="dist/${APP_NAME}-${VERSION}.dmg"

# --- 3. Notarize the app ------------------------------------------------------
if [ "$SKIP_NOTARIZE" = false ]; then
    echo -e "${YELLOW}Notarizing app (a few minutes)...${NC}"
    ditto -c -k --keepParent "$APP_PATH" "dist/$APP_NAME.zip"
    xcrun notarytool submit "dist/$APP_NAME.zip" \
        --apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$TEAM_ID" --wait
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
    rm -f "dist/$APP_NAME.zip"
fi

# --- 4. Build, sign, notarize, staple the DMG ---------------------------------
echo -e "${YELLOW}Creating DMG...${NC}"
create-dmg \
    --volname "$APP_NAME" \
    --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
    --window-pos 200 120 --window-size 600 400 --icon-size 100 \
    --icon "$APP_NAME.app" 150 190 \
    --app-drop-link 450 185 \
    --hide-extension "$APP_NAME.app" \
    "$DMG_PATH" "$APP_PATH" 2>&1 || true

codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"

if [ "$SKIP_NOTARIZE" = false ]; then
    echo -e "${YELLOW}Notarizing DMG...${NC}"
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$TEAM_ID" --wait
    xcrun stapler staple "$DMG_PATH"
fi

echo ""
echo -e "${GREEN}=== Done ===${NC}"
echo -e "DMG: ${GREEN}$DMG_PATH${NC}"
shasum -a 256 "$DMG_PATH"
ls -lh "$DMG_PATH"
