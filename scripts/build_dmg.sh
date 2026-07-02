#!/usr/bin/env bash
#
# Build a universal (arm64 + x86_64), Developer ID–signed, notarized Wakeup.app
# and package it into a distributable .dmg.
#
# Prerequisites (see RELEASING.md):
#   - Xcode installed and selected (xcode-select).
#   - A "Developer ID Application" certificate in your login keychain.
#   - A notarytool keychain profile OR the env vars below for notarization.
#
# Environment variables:
#   SIGN_IDENTITY   "Developer ID Application: Your Name (TEAMID)"  (required to sign)
#   TEAM_ID         Your Apple Developer Team ID                    (required to sign)
#   NOTARY_PROFILE  Name of a stored `notarytool` keychain profile (optional; enables notarization)
#                   Create with:
#                     xcrun notarytool store-credentials NOTARY_PROFILE \
#                       --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
#
# Usage:
#   SIGN_IDENTITY="Developer ID Application: ... (ABCDE12345)" TEAM_ID=ABCDE12345 \
#   NOTARY_PROFILE=wakeup-notary ./scripts/build_dmg.sh
#
# If SIGN_IDENTITY is unset, the app is built and packaged with an ad-hoc signature
# (works, but users must right-click → Open the first time).

set -euo pipefail

# ---- config ---------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$ROOT_DIR/Wakeup.xcodeproj"
SCHEME="Wakeup"
APP_NAME="Wakeup"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
TEAM_ID="${TEAM_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

# ---- read version from the project ---------------------------------------
VERSION="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')"
VERSION="${VERSION:-0.0.0}"
DMG_PATH="$BUILD_DIR/${APP_NAME}-${VERSION}.dmg"

echo "==> Building $APP_NAME $VERSION (universal)"

# ---- clean ----------------------------------------------------------------
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR" "$DMG_PATH"
mkdir -p "$BUILD_DIR"

# ---- archive (universal) --------------------------------------------------
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  | xcpretty 2>/dev/null || xcodebuild archive \
      -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
      -destination 'generic/platform=macOS' -archivePath "$ARCHIVE_PATH" \
      ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO

# ---- export the .app from the archive ------------------------------------
# We export the app bundle directly from the archive rather than using
# exportArchive so this works without a provisioning profile.
mkdir -p "$EXPORT_DIR"
cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$APP_PATH"

echo "==> Architectures:"
lipo -info "$APP_PATH/Contents/MacOS/$APP_NAME"

# ---- sign -----------------------------------------------------------------
if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "==> Signing with Developer ID: $SIGN_IDENTITY"
  codesign --force --deep --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$APP_PATH"
  codesign --verify --strict --verbose=2 "$APP_PATH"
else
  echo "==> No SIGN_IDENTITY set — applying ad-hoc signature"
  codesign --force --deep --sign - "$APP_PATH"
fi

# ---- build the DMG --------------------------------------------------------
echo "==> Creating DMG"
DMG_STAGING="$(mktemp -d)"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov -format UDZO \
  "$DMG_PATH"
rm -rf "$DMG_STAGING"

# ---- sign the DMG ---------------------------------------------------------
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
fi

# ---- notarize + staple ----------------------------------------------------
if [[ -n "$NOTARY_PROFILE" ]]; then
  echo "==> Notarizing (profile: $NOTARY_PROFILE)"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "==> Stapling"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
else
  echo "==> NOTARY_PROFILE not set — skipping notarization."
  echo "    The DMG is usable but users may see a Gatekeeper warning."
fi

echo ""
echo "✅ Done: $DMG_PATH"
