#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="0.1.1"

# Font flavor: set READER_FONTS=1 to build the LOCAL/personal app that defaults to
# the licensed "Reader" serif (install it once via Font Book). Unset (the default,
# as used by scripts/release.sh) ships the built-in "Iowan Old Style" serif.
SWIFT_FLAGS=()
if [ -n "${READER_FONTS:-}" ]; then
    SWIFT_FLAGS=(-Xswiftc -DREADER_FONTS)
    echo "Font flavor: LOCAL (Reader serif — READER_FONTS set)"
else
    echo "Font flavor: SHIPPING (Iowan Old Style serif)"
fi

swift build -c release --product Bookmarked ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}

BINARY_PATH=".build/release"
APP_DIR=".build/Bookmarked.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BINARY_PATH/Bookmarked" "$APP_DIR/Contents/MacOS/Bookmarked"

if [ -d "$BINARY_PATH/Bookmarked_Bookmarked.bundle" ]; then
    cp -R "$BINARY_PATH/Bookmarked_Bookmarked.bundle" "$APP_DIR/Contents/Resources/"
fi

if [ -f "Resources/icons/AppIcon.icns" ]; then
    cp "Resources/icons/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Bookmarked</string>
    <key>CFBundleIdentifier</key>
    <string>com.swair.bookmarked</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Bookmarked</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.swair.bookmarked</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>bookmarked</string>
            </array>
        </dict>
    </array>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Bookmarked reads the current browser tab so it can save and index the page you asked to capture.</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>Bookmarked uses Accessibility to detect the frontmost app for the global capture shortcut.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Bookmarked syncs your library with your iPhone/iPad over the local network.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_bkmkd-sync._tcp</string>
        <string>_bkmkd-sync._udp</string>
    </array>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

swift build -c release --product bookmarked ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}
cp "$BINARY_PATH/bookmarked" "$APP_DIR/Contents/MacOS/bookmarkedctl"

echo "built: $APP_DIR"
echo "built: $BINARY_PATH/bookmarked"
