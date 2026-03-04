#!/bin/bash
set -euo pipefail

APP_NAME="Just Play Piano"
BUNDLE_ID="com.billzajac.justplaypiano"
EXECUTABLE="PianoApp"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "Building $APP_NAME..."

# Build release binary
swift build -c release --disable-sandbox 2>&1

# Get the built executable path
EXEC_PATH=$(swift build -c release --show-bin-path)/$EXECUTABLE

# Create .app bundle structure
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

# Copy executable
cp "$EXEC_PATH" "$CONTENTS/MacOS/$EXECUTABLE"

# Create Info.plist
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Just Play Piano</string>
    <key>CFBundleDisplayName</key>
    <string>Just Play Piano</string>
    <key>CFBundleIdentifier</key>
    <string>com.billzajac.justplaypiano</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
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
    <key>NSMicrophoneUsageDescription</key>
    <string>Just Play Piano needs audio access to play piano sounds.</string>
</dict>
</plist>
PLIST

# Create entitlements (needed for audio + network)
cat > "$BUILD_DIR/entitlements.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign the app
codesign --force --deep --sign - --entitlements "$BUILD_DIR/entitlements.plist" "$APP_DIR"

echo ""
echo "Built: $APP_DIR"
echo ""

# Create DMG if hdiutil is available
DMG_PATH="$BUILD_DIR/JustPlayPiano.dmg"
rm -f "$DMG_PATH"

# Create a temporary directory for DMG contents
DMG_TMP="$BUILD_DIR/dmg-tmp"
rm -rf "$DMG_TMP"
mkdir -p "$DMG_TMP"
cp -R "$APP_DIR" "$DMG_TMP/"
ln -s /Applications "$DMG_TMP/Applications"

hdiutil create -volname "Just Play Piano" \
    -srcfolder "$DMG_TMP" \
    -ov -format UDZO \
    "$DMG_PATH" 2>&1

rm -rf "$DMG_TMP"

echo "DMG: $DMG_PATH"
