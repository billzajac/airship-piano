#!/bin/bash
set -euo pipefail

APP_NAME="Airship Piano"
EXECUTABLE="PianoApp"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
VERSION="${VERSION:-1.0.0}"

echo "Building $APP_NAME v$VERSION..."

# Build release binary
swift build -c release 2>&1

# Get the built executable path
EXEC_PATH=".build/release/$EXECUTABLE"

# Create .app bundle structure
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

# Copy executable and icon
cp "$EXEC_PATH" "$CONTENTS/MacOS/$EXECUTABLE"
cp Resources/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"

# Create Info.plist
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Airship Piano</string>
    <key>CFBundleDisplayName</key>
    <string>Airship Piano</string>
    <key>CFBundleIdentifier</key>
    <string>com.billzajac.airshippiano</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>PianoApp</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.music</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

# Create entitlements
cat > "$BUILD_DIR/entitlements.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign the app
codesign --force --deep --sign - --entitlements "$BUILD_DIR/entitlements.plist" "$APP_DIR"

echo ""
echo "Built: $APP_DIR"
echo ""

# Create DMG with baked-in Finder layout
# Uses HFS+ (not APFS) so .DS_Store works reliably with Finder.
# Layout is set via osascript at BUILD time — the blink happens here,
# not when the user opens the DMG.
DMG_PATH="$BUILD_DIR/AirshipPiano.dmg"
DMG_TMP="$BUILD_DIR/dmg-tmp"
DMG_RW="$BUILD_DIR/rw.dmg"
VOLNAME="Airship Piano"

# Force-unmount any stale volume with our name
hdiutil detach "/Volumes/$VOLNAME" -force 2>/dev/null || true
rm -f "$DMG_PATH" "$DMG_RW"
rm -rf "$DMG_TMP"
mkdir -p "$DMG_TMP"
cp -R "$APP_DIR" "$DMG_TMP/"

# Create read-write HFS+ DMG
hdiutil create -volname "$VOLNAME" \
    -srcfolder "$DMG_TMP" \
    -ov -format UDRW \
    -fs HFS+ \
    -size 10m \
    "$DMG_RW" 2>&1

# Mount and let Finder bake in the layout
DEVICE=$(hdiutil attach "$DMG_RW" 2>&1 | grep "/Volumes/" | head -1 | cut -f1 | tr -d '[:space:]')

sleep 2

echo "Configuring DMG layout..."
osascript << APPLESCRIPT
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 740, 500}
        set viewOptions to the icon view options of container window
        set icon size of viewOptions to 128
        set arrangement of viewOptions to not arranged
        make new alias file at container window to POSIX file "/Applications" with properties {name:"Applications"}
        delay 1
        set position of item "$APP_NAME.app" of container window to {140, 190}
        set position of item "Applications" of container window to {400, 190}
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# Wait for .DS_Store to be flushed
sync
sleep 2

# Set the Applications folder icon on the alias
swift - "/Volumes/$VOLNAME/Applications" << 'ICONSWIFT'
import AppKit
import Foundation
let target = CommandLine.arguments[1]
let icon = NSWorkspace.shared.icon(forFile: "/Applications")
icon.size = NSSize(width: 512, height: 512)
NSWorkspace.shared.setIcon(icon, forFile: target)
ICONSWIFT

# Clean up metadata
rm -rf "/Volumes/$VOLNAME/.fseventsd" "/Volumes/$VOLNAME/.Trashes"

# Unmount
hdiutil detach "$DEVICE" 2>&1

# Convert to compressed read-only DMG (this is what gets distributed)
hdiutil convert "$DMG_RW" -format UDZO -o "$DMG_PATH" 2>&1
rm -f "$DMG_RW"
rm -rf "$DMG_TMP"

# Set custom icon on the DMG file itself
fileicon set "$DMG_PATH" Resources/AppIcon.icns

echo "DMG: $DMG_PATH"
