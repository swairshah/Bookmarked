#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="BookmarkedReader"
SCHEME="BookmarkedReader"
PROJECT="BookmarkedReader.xcodeproj"
BUNDLE_ID="com.swairshah.BookmarkedReader"
DERIVED="build"
APP_PATH="$DERIVED/Build/Products/Debug-iphonesimulator/$APP_NAME.app"

# Which simulator to use. Override: DEVICE="iPhone 16 Pro" ./run.sh
# or pass as first arg:            ./run.sh "iPhone 15"
DEVICE="${1:-${DEVICE:-iPhone 16}}"
# CONSOLE=1 attaches the app's stdout/stderr to this terminal.
CONSOLE="${CONSOLE:-0}"
# Your real library, as written by the Mac app. Override with REAL_DB=/path/...
REAL_DB="${REAL_DB:-$HOME/Library/Application Support/Bookmarked/bookmarks.json}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
echo -e "${GREEN}=== $APP_NAME — Simulator Build & Run ===${NC}"

# --- Resolve a simulator UDID --------------------------------------------------
udid_for() { xcrun simctl list devices available | grep -E "$1 \(" | head -1 | grep -oE '[0-9A-F-]{36}' || true; }
UDID="$(udid_for "$DEVICE")"
if [ -z "$UDID" ]; then
    echo -e "${YELLOW}'$DEVICE' not found — falling back to first available iPhone.${NC}"
    UDID="$(xcrun simctl list devices available | grep -E 'iPhone' | head -1 | grep -oE '[0-9A-F-]{36}' || true)"
fi
if [ -z "$UDID" ]; then
    echo -e "${RED}No iOS Simulator runtime found. Install one in Xcode → Settings → Components.${NC}"
    exit 1
fi
echo -e "Simulator: ${GREEN}$DEVICE${NC} ($UDID)"

# --- Build (no signing needed for the simulator) -------------------------------
echo -e "${YELLOW}Building...${NC}"
rm -rf "$APP_PATH"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO \
    build

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Build failed — $APP_PATH not produced.${NC}"
    exit 1
fi

# --- Boot the simulator and bring it to the front ------------------------------
echo -e "${YELLOW}Booting simulator...${NC}"
xcrun simctl bootstatus "$UDID" -b   # boots if needed, then waits until ready
open -a Simulator --args -CurrentDeviceUDID "$UDID" || open -a Simulator

# --- Install -------------------------------------------------------------------
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
echo -e "${YELLOW}Installing...${NC}"
xcrun simctl install "$UDID" "$APP_PATH"

# --- Load your real library (the Mac app's bookmarks.json) ---------------------
# Copies it into the installed app's Documents, where the store looks before the
# bundled sample. Comment this block out to use the bundled sample instead.
if [ -f "$REAL_DB" ]; then
    DATA_DIR="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)"
    if [ -z "${DATA_DIR:-}" ]; then
        xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true   # creates the container
        sleep 1
        xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
        DATA_DIR="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)"
    fi
    if [ -n "${DATA_DIR:-}" ]; then
        mkdir -p "$DATA_DIR/Documents"
        cp "$REAL_DB" "$DATA_DIR/Documents/bookmarks.json"
        COUNT="$(/usr/bin/python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$REAL_DB" 2>/dev/null || echo "?")"
        echo -e "${GREEN}Loaded your library ($COUNT bookmarks):${NC} $REAL_DB"
    else
        echo -e "${YELLOW}Could not locate the app data container; falling back to bundled sample.${NC}"
    fi
else
    echo -e "${YELLOW}No Mac library at:${NC} $REAL_DB"
    echo -e "${YELLOW}Using the bundled sample. Override with REAL_DB=/path/to/bookmarks.json ./run.sh${NC}"
fi

echo -e "${GREEN}Launching $APP_NAME...${NC}"
if [ "$CONSOLE" = "1" ]; then
    xcrun simctl launch --console-pty "$UDID" "$BUNDLE_ID"
else
    xcrun simctl launch "$UDID" "$BUNDLE_ID"
    echo ""
    echo -e "Stream logs: ${YELLOW}xcrun simctl spawn $UDID log stream --level debug --predicate 'processImagePath CONTAINS \"$APP_NAME\"'${NC}"
    echo -e "Stop:        ${YELLOW}xcrun simctl terminate $UDID $BUNDLE_ID${NC}"
fi
