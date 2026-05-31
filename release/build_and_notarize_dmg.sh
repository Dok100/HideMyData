#!/bin/bash

set -euo pipefail

PROJECT="Inkognito.xcodeproj"
SCHEME="Inkognito"
CONFIGURATION="Release"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-inkognito-notary}"
VOLUME_NAME="${VOLUME_NAME:-Inkognito}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/output/release"
ARCHIVE_PATH="$OUTPUT_DIR/Inkognito.xcarchive"
EXPORT_PATH="$OUTPUT_DIR/export"
NOTARY_DIR="$OUTPUT_DIR/notary"
DMG_DIR="$OUTPUT_DIR/dmg"
EXPORT_OPTIONS_PLIST="$ROOT_DIR/release/export-options/developer-id.plist"

DEFAULT_VERSION="$(rg -n --no-filename 'MARKETING_VERSION = ' "$ROOT_DIR/$PROJECT/project.pbxproj" | head -n 1 | sed -E 's/.*MARKETING_VERSION = ([^;]+);/\1/')"
VERSION="${1:-$DEFAULT_VERSION}"

if [ -z "$VERSION" ]; then
  echo "Could not determine MARKETING_VERSION. Pass the version explicitly, for example:" >&2
  echo "  bash release/build_and_notarize_dmg.sh 0.3.0" >&2
  exit 1
fi

APP_PATH="$EXPORT_PATH/Inkognito.app"
APP_ZIP_PATH="$NOTARY_DIR/Inkognito-app.zip"
DMG_PATH="$DMG_DIR/Inkognito-$VERSION.dmg"

echo "Release version: $VERSION"
echo "Keychain profile: $KEYCHAIN_PROFILE"
echo "Archive path: $ARCHIVE_PATH"
echo "DMG path: $DMG_PATH"

mkdir -p "$OUTPUT_DIR" "$NOTARY_DIR" "$DMG_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
rm -f "$APP_ZIP_PATH" "$DMG_PATH"

echo
echo "1. Archive app"
xcodebuild \
  -project "$ROOT_DIR/$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  archive

echo
echo "2. Export Developer ID app"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  -exportPath "$EXPORT_PATH"

echo
echo "3. Verify exported app signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo
echo "4. Zip app for notarization"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP_PATH"

echo
echo "5. Submit app zip for notarization"
xcrun notarytool submit "$APP_ZIP_PATH" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

echo
echo "6. Staple notarization ticket to app"
xcrun stapler staple "$APP_PATH"

echo
echo "7. Validate stapled app"
spctl --assess --type execute --verbose "$APP_PATH"

echo
echo "8. Build DMG from stapled app"
bash "$ROOT_DIR/scripts/build_release_dmg.sh" "$APP_PATH" "$DMG_PATH" "$VOLUME_NAME"

echo
echo "9. Submit DMG for notarization"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

echo
echo "10. Staple notarization ticket to DMG"
xcrun stapler staple "$DMG_PATH"

echo
echo "11. Validate stapled DMG"
xcrun stapler validate "$DMG_PATH"

echo
echo "Done."
echo "Exported app: $APP_PATH"
echo "Final DMG: $DMG_PATH"
