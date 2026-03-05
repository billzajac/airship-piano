#!/bin/bash
set -euo pipefail

# ============================================================================
# Airship Piano — Google Play Store Deploy
#
# FIRST-TIME SETUP (do these once):
#
# 1. Renew/create Google Play Developer account ($25):
#    https://play.google.com/console
#
# 2. Create the app listing in Play Console:
#    - App name: Airship Piano
#    - Package: com.windupairships.airshippiano
#    - Fill in store listing, content rating, pricing (free)
#
# 3. Create a Google Cloud service account for API uploads:
#    a) Go to https://console.cloud.google.com
#    b) Create or select a project
#    c) Enable "Google Play Android Developer API"
#    d) Create a service account (IAM > Service Accounts > Create)
#    e) Create a JSON key and save to: ~/home/google-play-service-account.json
#    f) In Play Console: Setup > API access > Link the Google Cloud project
#    g) Grant the service account "Release manager" permission for your app
#
# 4. Install google-play CLI tool:
#    pip install google-play-cli
#    — OR use the googleapis Python client directly (this script uses curl + oauth)
#
# After setup, this script will build, upload, and submit to internal track.
# ============================================================================

cd "$(dirname "$0")"

PROPS_FILE="$HOME/home/airship-piano-android.properties"
SERVICE_ACCOUNT_KEY="$HOME/home/google-play-service-account.json"
PACKAGE_NAME="com.windupairships.airshippiano"
TRACK="internal"  # internal, alpha, beta, production

# Check prerequisites
if [ ! -f "$PROPS_FILE" ]; then
    echo "Error: $PROPS_FILE not found"
    echo "Create it with: storeFile, storePassword, keyAlias, keyPassword"
    exit 1
fi

if [ ! -f "$SERVICE_ACCOUNT_KEY" ]; then
    echo "Error: $SERVICE_ACCOUNT_KEY not found"
    echo ""
    echo "Follow the setup instructions at the top of this script to create"
    echo "a Google Cloud service account and download the JSON key."
    exit 1
fi

# Check for Python (needed for JWT token generation)
if ! command -v python3 &>/dev/null; then
    echo "Error: python3 required for API authentication"
    exit 1
fi

# Step 1: Build release AAB
echo "==> Building release AAB..."
./gradlew :app:bundleRelease 2>&1 | tail -5

AAB_PATH="app/build/outputs/bundle/release/app-release.aab"
if [ ! -f "$AAB_PATH" ]; then
    echo "Error: AAB not found at $AAB_PATH"
    exit 1
fi

AAB_SIZE=$(ls -lh "$AAB_PATH" | awk '{print $5}')
echo "    Built: $AAB_PATH ($AAB_SIZE)"

# Step 2: Get OAuth2 access token from service account
echo ""
echo "==> Authenticating with Google Play API..."

ACCESS_TOKEN=$(python3 - "$SERVICE_ACCOUNT_KEY" << 'PYEOF'
import json, sys, time, urllib.request, urllib.parse
from hashlib import sha256
import hmac, base64, struct

key_file = sys.argv[1]
with open(key_file) as f:
    sa = json.load(f)

# Build JWT
header = base64.urlsafe_b64encode(json.dumps({"alg": "RS256", "typ": "JWT"}).encode()).rstrip(b"=")
now = int(time.time())
claims = {
    "iss": sa["client_email"],
    "scope": "https://www.googleapis.com/auth/androidpublisher",
    "aud": "https://oauth2.googleapis.com/token",
    "iat": now,
    "exp": now + 3600
}
payload = base64.urlsafe_b64encode(json.dumps(claims).encode()).rstrip(b"=")
sign_input = header + b"." + payload

# Sign with RSA-SHA256
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

private_key = serialization.load_pem_private_key(sa["private_key"].encode(), password=None)
signature = private_key.sign(sign_input, padding.PKCS1v15(), hashes.SHA256())
sig_b64 = base64.urlsafe_b64encode(signature).rstrip(b"=")

jwt_token = (sign_input + b"." + sig_b64).decode()

# Exchange JWT for access token
data = urllib.parse.urlencode({
    "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
    "assertion": jwt_token
}).encode()
req = urllib.request.Request("https://oauth2.googleapis.com/token", data=data, method="POST")
resp = urllib.request.urlopen(req)
token = json.loads(resp.read())["access_token"]
print(token)
PYEOF
)

if [ -z "$ACCESS_TOKEN" ]; then
    echo "Error: Failed to get access token"
    exit 1
fi
echo "    Authenticated."

API_BASE="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$PACKAGE_NAME"

# Step 3: Create a new edit
echo ""
echo "==> Creating new edit..."

EDIT_ID=$(curl -s -X POST \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{}' \
    "$API_BASE/edits" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

echo "    Edit ID: $EDIT_ID"

# Step 4: Upload the AAB
echo ""
echo "==> Uploading AAB to $TRACK track..."

UPLOAD_RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$AAB_PATH" \
    "$API_BASE/edits/$EDIT_ID/bundles?uploadType=media")

VERSION_CODE=$(echo "$UPLOAD_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['versionCode'])")
echo "    Uploaded version code: $VERSION_CODE"

# Step 5: Assign to track
echo ""
echo "==> Assigning to $TRACK track..."

curl -s -X PUT \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"releases\": [{\"versionCodes\": [\"$VERSION_CODE\"], \"status\": \"completed\"}]}" \
    "$API_BASE/edits/$EDIT_ID/tracks/$TRACK" > /dev/null

# Step 6: Commit the edit
echo "==> Committing edit..."

curl -s -X POST \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    "$API_BASE/edits/$EDIT_ID:commit" > /dev/null

echo ""
echo "==> Done! Version $VERSION_CODE submitted to $TRACK track."
echo "    View at: https://play.google.com/console"
echo ""
echo "    To promote to production, change TRACK=\"production\" in this script"
echo "    or promote from Play Console."
