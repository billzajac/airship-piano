#!/bin/bash
set -euo pipefail

# Airship Piano — App Store Deploy Script
# Usage: ./deploy-appstore.sh [patch|minor|major|build]
#
# Builds, archives, exports IPA, and uploads to App Store Connect.
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

SCHEME="AirshipPiano-iOS"
PROJECT="AirshipPiano.xcodeproj"
ARCHIVE_PATH="build/AirshipPiano.xcarchive"
EXPORT_PATH="build/ipa"
INCREMENT="${1:-build}"

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

# ─── Step 3: Archive ─────────────────────────────────────────────────────────

echo "Archiving for App Store..."
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=iOS" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$APPLE_CONNECT_PRIVATE_KEY_PATH" \
    -authenticationKeyID "$APPLE_CONNECT_API_KEY" \
    -authenticationKeyIssuerID "$APPLE_CONNECT_API_ISSUER_ID" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    2>&1 | tail -20

if [ ! -d "$ARCHIVE_PATH" ]; then
    echo "Error: Archive failed"
    exit 1
fi

echo "Archive created: $ARCHIVE_PATH"

# ─── Step 4: Export IPA & Upload to App Store Connect ─────────────────────────

echo "Exporting IPA and uploading to App Store Connect..."

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist ExportOptions.plist \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$APPLE_CONNECT_PRIVATE_KEY_PATH" \
    -authenticationKeyID "$APPLE_CONNECT_API_KEY" \
    -authenticationKeyIssuerID "$APPLE_CONNECT_API_ISSUER_ID" \
    2>&1 | tail -20

echo ""
echo "=== SUCCESS ==="
echo "Airship Piano ${new_marketing}(${new_build}) uploaded to App Store Connect!"
echo ""
echo "Next steps:"
echo "  1. Wait 5-15 minutes for Apple to process the build"
echo "  2. Go to https://appstoreconnect.apple.com"
echo "  3. Select the build and submit for review"
