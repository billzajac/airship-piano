#!/bin/bash
set -euo pipefail

APP_NAME="Just Play Piano"
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
    <string>Just Play Piano</string>
    <key>CFBundleDisplayName</key>
    <string>Just Play Piano</string>
    <key>CFBundleIdentifier</key>
    <string>com.billzajac.justplaypiano</string>
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

# Create DMG with proper layout
DMG_PATH="$BUILD_DIR/JustPlayPiano.dmg"
rm -f "$DMG_PATH"

if command -v create-dmg &> /dev/null; then
    create-dmg \
        --volname "Just Play Piano" \
        --window-pos 200 120 \
        --window-size 540 380 \
        --icon-size 128 \
        --icon "$APP_NAME.app" 140 190 \
        --app-drop-link 400 190 \
        --no-internet-enable \
        "$DMG_PATH" \
        "$APP_DIR" 2>&1
else
    echo "Note: install create-dmg (brew install create-dmg) for a polished DMG layout"
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
fi

echo "DMG: $DMG_PATH"
