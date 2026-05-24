#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="0.1.0"
swift build -c release --product Bookmarked

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
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"
echo "built: $APP_DIR"
