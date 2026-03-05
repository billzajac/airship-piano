# iOS App Store Deployment Plan — Airship Piano

## Goal
Single CLI command that builds, uploads to App Store Connect. Submit for review via web UI.

## Prerequisites (One-Time Manual Steps)

These must be done before the script works:

1. **Register the bundle ID** `com.billzajac.airshippiano` under team NNE5EA54L2 (Tensor Group LLC)
   - Go to https://developer.apple.com/account/resources/identifiers
   - Or let Xcode automatic signing create it on first archive attempt

2. **Create the app in App Store Connect**
   - Go to https://appstoreconnect.apple.com → My Apps → (+)
   - App name: "Airship Piano"
   - Bundle ID: `com.billzajac.airshippiano`
   - SKU: `airshippiano`
   - Primary language: English (U.S.)

3. **Verify App Store Connect API key exists**
   - Key: `5L3D89XR64` at `~/private_keys/AuthKey_5L3D89XR64.p8`
   - Issuer: `69a6de8b-eee2-47e3-e053-5b8c7c11a4d1`

4. **Env file** already created at `~/home/airship-piano.env` (NOT in repo)

5. **App Store metadata** (screenshots, description, etc.)
   - Must be filled in at App Store Connect before first submission for review
   - Can be done after the first build upload

## What's Been Done

- [x] Updated `project.yml` team ID from `FT574Q62GF` to `NNE5EA54L2`
- [x] Created `ExportOptions.plist` (no secrets — safe for repo)
- [x] Created `~/home/airship-piano.env` with API credentials (outside repo)
- [x] Created `deploy-appstore.sh` — the main deploy script
- [x] Updated `.gitignore` to exclude archives, IPAs, and env files

## Usage

```bash
./deploy-appstore.sh [patch|minor|major|build]
```

Default is `build` (increments build number only, keeps marketing version).

### What it does

1. Loads credentials from `~/home/airship-piano.env`
2. Bumps version in `project.yml` (both iOS and macOS targets)
3. Regenerates Xcode project via `xcodegen generate`
4. Archives via `xcodebuild archive` with API key auth flags
5. Exports IPA and uploads to App Store Connect via `xcodebuild -exportArchive`
   - Uses `destination: upload` in ExportOptions.plist for automatic upload
   - Auth handled via `-authenticationKey*` flags (no cached Xcode session needed)
6. Prints success and link to App Store Connect for review submission

### After upload
1. Wait 5-15 minutes for Apple to process the build
2. Go to https://appstoreconnect.apple.com
3. Select the build under the app version and submit for review

## Architecture

```
deploy-appstore.sh           ← Main script (~80 lines bash)
ExportOptions.plist           ← Export config (in repo, no secrets)
~/home/airship-piano.env      ← Credentials (outside repo)
```

Key design decisions:
- **Pure bash** — no Python dependency needed
- **`xcodebuild -exportArchive` with `destination: upload`** — Apple's recommended replacement for deprecated `xcrun altool`
- **`-authenticationKey*` flags** on both archive and exportArchive — enables headless CI/CD without cached Xcode sessions
- **Manual review submission** — automating via App Store Connect REST API adds JWT/polling complexity for a 30-second manual task
- **Credentials in ~/home/** — never in the git repo
