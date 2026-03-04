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

# Create DMG with baked-in layout (no Finder scripting, no blinking)
DMG_PATH="$BUILD_DIR/AirshipPiano.dmg"
DMG_TMP="$BUILD_DIR/dmg-tmp"
DMG_RW="$BUILD_DIR/rw.dmg"
VOLNAME="Airship Piano"

rm -f "$DMG_PATH" "$DMG_RW"
rm -rf "$DMG_TMP"
mkdir -p "$DMG_TMP"
cp -R "$APP_DIR" "$DMG_TMP/"
ln -s /Applications "$DMG_TMP/Applications"

# Create a read-write DMG, set layout via .DS_Store, then convert to compressed
hdiutil create -volname "$VOLNAME" \
    -srcfolder "$DMG_TMP" \
    -ov -format UDRW \
    -size 10m \
    "$DMG_RW" 2>&1

# Mount the RW image and bake in the Finder layout
DEVICE=$(hdiutil attach "$DMG_RW" -mountpoint "/Volumes/$VOLNAME" -nobrowse 2>&1 | head -1 | awk '{print $1}')
MOUNT_DIR="/Volumes/$VOLNAME"

# Write .DS_Store with icon positions and window settings using Python
python3 - "$MOUNT_DIR" "$APP_NAME" << 'PYDS'
import struct, sys, os

mount = sys.argv[1]
app_name = sys.argv[2] + ".app"

# Minimal .DS_Store that sets:
# - Window size 540x380, icon size 128, icon view
# - App icon at (140, 190), Applications alias at (400, 190)
# This is a pre-built binary .DS_Store blob

# Use the ds_store Python library if available, otherwise write a basic one
try:
    from ds_store import DSStore
    with DSStore.open(os.path.join(mount, ".DS_Store"), "w+") as d:
        d["."]["bwsp"] = {
            "ShowStatusBar": False,
            "WindowBounds": "{{200, 120}, {540, 380}}",
            "ShowPathbar": False,
            "ShowToolbar": False,
            "ShowTabView": False,
            "ShowSidebar": False,
        }
        d["."]["icvp"] = {
            "viewOptionsVersion": 1,
            "backgroundType": 0,
            "backgroundColorRed": 1.0,
            "backgroundColorGreen": 1.0,
            "backgroundColorBlue": 1.0,
            "gridOffsetX": 0.0,
            "gridOffsetY": 0.0,
            "gridSpacing": 100.0,
            "iconSize": 128.0,
            "textSize": 13.0,
            "labelOnBottom": True,
            "showItemInfo": False,
            "showIconPreview": True,
            "arrangeBy": "none",
        }
        d[app_name]["Iloc"] = (140, 190)
        d["Applications"]["Iloc"] = (400, 190)
    print("DS_Store written via ds_store library")
except ImportError:
    # Fallback: use Finder via osascript but with -nobrowse so no visible window
    import subprocess
    subprocess.run(["osascript", "-e", f'''
        tell application "Finder"
            tell disk "{os.path.basename(mount)}"
                open
                set current view of container window to icon view
                set toolbar visible of container window to false
                set statusbar visible of container window to false
                set the bounds of container window to {{200, 120, 740, 500}}
                set viewOptions to the icon view options of container window
                set icon size of viewOptions to 128
                set arrangement of viewOptions to not arranged
                set position of item "{app_name}" of container window to {{140, 190}}
                set position of item "Applications" of container window to {{400, 190}}
                close
            end tell
        end tell
    '''], check=False)
    # Wait for .DS_Store to be written
    import time
    time.sleep(1)
    print("DS_Store written via Finder (fallback)")
PYDS

# Remove .fseventsd and Trashes
rm -rf "$MOUNT_DIR/.fseventsd" "$MOUNT_DIR/.Trashes"

# Unmount
sync
sleep 1
hdiutil detach "$DEVICE" -force 2>&1

# Convert to compressed read-only DMG
hdiutil convert "$DMG_RW" -format UDZO -o "$DMG_PATH" 2>&1
rm -f "$DMG_RW"
rm -rf "$DMG_TMP"

echo "DMG: $DMG_PATH"
