#!/bin/bash
set -euo pipefail

# Airship Piano — App Store Deploy Script
# Usage: ./deploy-appstore.sh [patch|minor|major|build]
#
# Builds, archives, and uploads both iOS and macOS to App Store Connect.
# After upload, submit for review at https://appstoreconnect.apple.com
# Credentials loaded from ~/home/airship-piano.env

ENV_FILE="$HOME/home/airship-piano.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: $ENV_FILE not found"
    echo "Create it with: APPLE_CONNECT_API_KEY, APPLE_CONNECT_API_ISSUER_ID,"
    echo "  APPLE_CONNECT_PRIVATE_KEY_PATH, APPLE_TEAM_ID"
    exit 1
fi
source "$ENV_FILE"

for var in APPLE_CONNECT_API_KEY APPLE_CONNECT_API_ISSUER_ID APPLE_CONNECT_PRIVATE_KEY_PATH APPLE_TEAM_ID; do
    if [ -z "${!var:-}" ]; then
        echo "Error: $var not set in $ENV_FILE"
        exit 1
    fi
done

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

PROJECT="AirshipPiano.xcodeproj"
INCREMENT="${1:-build}"

AUTH_FLAGS=(
    -allowProvisioningUpdates
    -authenticationKeyPath "$APPLE_CONNECT_PRIVATE_KEY_PATH"
    -authenticationKeyID "$APPLE_CONNECT_API_KEY"
    -authenticationKeyIssuerID "$APPLE_CONNECT_API_ISSUER_ID"
)

# ─── Step 1: Version Bumping ─────────────────────────────────────────────────

current_marketing=$(grep 'MARKETING_VERSION:' project.yml | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
current_build=$(grep 'CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')

IFS='.' read -r major minor patch <<< "$current_marketing"

case "$INCREMENT" in
    major)
        major=$((major + 1)); minor=0; patch=0; new_build=1 ;;
    minor)
        minor=$((minor + 1)); patch=0; new_build=1 ;;
    patch)
        patch=$((patch + 1)); new_build=1 ;;
    build)
        new_build=$((current_build + 1)) ;;
    *)
        echo "Usage: $0 [patch|minor|major|build]"
        exit 1 ;;
esac

new_marketing="${major}.${minor}.${patch}"

echo "Version: ${current_marketing}(${current_build}) -> ${new_marketing}(${new_build})"

# Update project.yml (both iOS and macOS targets)
sed -i '' "s/MARKETING_VERSION: .*/MARKETING_VERSION: \"${new_marketing}\"/" project.yml
sed -i '' "s/CURRENT_PROJECT_VERSION: .*/CURRENT_PROJECT_VERSION: \"${new_build}\"/" project.yml

# ─── Step 2: Regenerate Xcode Project ────────────────────────────────────────

echo "Regenerating Xcode project..."
if command -v xcodegen &>/dev/null; then
    xcodegen generate 2>&1 | grep -v "^$"
else
    echo "Error: xcodegen not found. Install with: brew install xcodegen"
    exit 1
fi

# Clean to ensure entitlements and settings are fresh
xcodebuild clean -project "$PROJECT" -scheme "AirshipPiano-iOS" -scheme "AirshipPiano-macOS" 2>&1 | tail -1

# ─── Step 3: Archive & Upload iOS ────────────────────────────────────────────

echo ""
echo "========== iOS =========="

IOS_ARCHIVE="build/AirshipPiano-iOS.xcarchive"
IOS_EXPORT="build/ios-export"

echo "Archiving iOS..."
rm -rf "$IOS_ARCHIVE" "$IOS_EXPORT"

xcodebuild archive \
    -project "$PROJECT" \
    -scheme "AirshipPiano-iOS" \
    -configuration Release \
    -archivePath "$IOS_ARCHIVE" \
    -destination "generic/platform=iOS" \
    "${AUTH_FLAGS[@]}" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    2>&1 | tail -5

if [ ! -d "$IOS_ARCHIVE" ]; then
    echo "Error: iOS archive failed"
    exit 1
fi

echo "Uploading iOS..."
xcodebuild -exportArchive \
    -archivePath "$IOS_ARCHIVE" \
    -exportPath "$IOS_EXPORT" \
    -exportOptionsPlist ExportOptions.plist \
    "${AUTH_FLAGS[@]}" \
    2>&1 | tail -10

echo "iOS upload complete."

# ─── Step 4: Archive & Upload macOS ──────────────────────────────────────────

echo ""
echo "========== macOS =========="

MACOS_ARCHIVE="build/AirshipPiano-macOS.xcarchive"
MACOS_EXPORT="build/macos-export"

echo "Archiving macOS..."
rm -rf "$MACOS_ARCHIVE" "$MACOS_EXPORT"

xcodebuild archive \
    -project "$PROJECT" \
    -scheme "AirshipPiano-macOS" \
    -configuration Release \
    -archivePath "$MACOS_ARCHIVE" \
    -destination "generic/platform=macOS" \
    "${AUTH_FLAGS[@]}" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    2>&1 | tail -5

if [ ! -d "$MACOS_ARCHIVE" ]; then
    echo "Error: macOS archive failed"
    exit 1
fi

echo "Uploading macOS..."
xcodebuild -exportArchive \
    -archivePath "$MACOS_ARCHIVE" \
    -exportPath "$MACOS_EXPORT" \
    -exportOptionsPlist ExportOptions.plist \
    "${AUTH_FLAGS[@]}" \
    2>&1 | tail -10

echo "macOS upload complete."

# ─── Done ────────────────────────────────────────────────────────────────────

echo ""
echo "=== SUCCESS ==="
echo "Airship Piano ${new_marketing}(${new_build}) uploaded for iOS + macOS!"
echo ""
echo "Next steps:"
echo "  1. Wait 5-15 minutes for Apple to process the builds"
echo "  2. Go to https://appstoreconnect.apple.com"
echo "  3. Select builds and submit for review"
