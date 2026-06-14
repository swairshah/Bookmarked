#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Releases both apps in one go:
#   - macOS: builds the Bookmarked app and relaunches it
#   - iOS:   archives + uploads BookmarkedReader to TestFlight
#
# Credentials are read from a gitignored .env (see .env.example), or from your
# shell environment. Flags:
#   --ios-only      only release the iOS app
#   --mac-only      only build/relaunch the macOS app
#   --no-relaunch   build the macOS app but don't relaunch it
#
# Usage: ./release-all.sh

# Load .env if present (KEY=value lines), exporting for the iOS sub-script.
if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091
    . ./.env
    set +a
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

DO_MAC=1; DO_IOS=1; RELAUNCH=1
for arg in "$@"; do
    case "$arg" in
        --ios-only) DO_MAC=0 ;;
        --mac-only) DO_IOS=0 ;;
        --no-relaunch) RELAUNCH=0 ;;
        *) echo -e "${YELLOW}Unknown option: $arg${NC}"; exit 1 ;;
    esac
done

# --- macOS ---------------------------------------------------------------------
if [ "$DO_MAC" = 1 ]; then
    echo -e "${BOLD}${GREEN}=== [1/2] macOS — build${NC}"
    # This is your local install, so default to the licensed "Reader" serif.
    # (The distributable DMG is built by scripts/release.sh, which ships Iowan Old Style.)
    READER_FONTS="${READER_FONTS:-1}" ./scripts/build-app.sh
    if [ "$RELAUNCH" = 1 ]; then
        echo -e "${YELLOW}Relaunching macOS app...${NC}"
        pkill -f "Bookmarked.app" 2>/dev/null || true
        pkill -f "MacOS/Bookmarked" 2>/dev/null || true
        sleep 0.5
        open .build/Bookmarked.app
        echo -e "${GREEN}macOS app relaunched.${NC}"
    fi
fi

# --- iOS / TestFlight ----------------------------------------------------------
if [ "$DO_IOS" = 1 ]; then
    echo -e "${BOLD}${GREEN}=== [2/2] iOS — archive + upload to TestFlight${NC}"
    if [ -z "${APPLE_TEAM_ID:-}" ]; then
        echo -e "${RED}Missing Apple credentials.${NC} Copy .env.example to .env and fill it in,"
        echo -e "or export APPLE_TEAM_ID / APPLE_EMAIL / APPLE_APP_PASSWORD in your shell."
        exit 1
    fi
    ( cd BookmarkedReader-iOS && ./release.sh )
fi

echo -e "${BOLD}${GREEN}=== All done.${NC}"
if [ "$DO_IOS" = 1 ]; then
    echo -e "iOS build is processing in App Store Connect → TestFlight (~5–15 min)."
fi
