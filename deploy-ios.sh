#!/bin/bash
set -euo pipefail

ENV_FILE="$HOME/home/airship-piano.env"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

SCHEME="AirshipPiano-iOS"
PROJECT="AirshipPiano.xcodeproj"
CONFIG="${1:-Debug}"
BUILD_DIR="build/ios"

echo "Building Airship Piano for iOS ($CONFIG)..."

# Find connected iOS device
DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null | grep -E "connected|available" | grep -v "Watch\|iPad" | head -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9A-F]{8}-/) print $i}')

if [ -z "$DEVICE_ID" ]; then
    echo "Error: No available iPhone found. Make sure your iPhone is plugged in and unlocked."
    echo ""
    echo "Connected devices:"
    xcrun devicectl list devices 2>/dev/null | grep -v "^--"
    exit 1
fi

DEVICE_NAME=$(xcrun devicectl list devices 2>/dev/null | grep "$DEVICE_ID" | awk -F'   ' '{print $1}' | xargs)
echo "Found device: $DEVICE_NAME ($DEVICE_ID)"

# Regenerate Xcode project (in case project.yml changed)
if command -v xcodegen &>/dev/null; then
    xcodegen generate 2>&1 | grep -v "^$"
fi

# Build for device
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$BUILD_DIR" \
    -allowProvisioningUpdates \
    ${APPLE_CONNECT_PRIVATE_KEY_PATH:+-authenticationKeyPath "$APPLE_CONNECT_PRIVATE_KEY_PATH"} \
    ${APPLE_CONNECT_API_KEY:+-authenticationKeyID "$APPLE_CONNECT_API_KEY"} \
    ${APPLE_CONNECT_API_ISSUER_ID:+-authenticationKeyIssuerID "$APPLE_CONNECT_API_ISSUER_ID"} \
    build \
    2>&1 | tail -5

echo ""

# Find the built .app
APP_PATH=$(find "$BUILD_DIR" -name "*.app" -path "*${CONFIG}-iphoneos*" | head -1)

if [ -z "$APP_PATH" ]; then
    echo "Error: Could not find built .app bundle"
    exit 1
fi

echo "Installing $APP_PATH to $DEVICE_NAME..."

# Install on device
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" 2>&1

echo ""
echo "Done! Airship Piano is installed on $DEVICE_NAME."
echo "Open it on your iPhone to use."
