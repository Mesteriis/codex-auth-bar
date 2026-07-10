#!/usr/bin/env bash
set -euo pipefail

VERSION="${1#v}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
KEYCHAIN="$RUNNER_TEMP/codex-auth-bar.keychain-db"
ARCHIVE="$DIST/CodexAuthBar.xcarchive"
DMG="$DIST/CodexAuthBar-$VERSION.dmg"

for name in DEVELOPER_ID_APPLICATION_P12_BASE64 DEVELOPER_ID_APPLICATION_P12_PASSWORD APPLE_API_KEY_P8_BASE64 APPLE_API_KEY_ID APPLE_API_ISSUER_ID KEYCHAIN_PASSWORD DEVELOPMENT_TEAM SIGNING_IDENTITY; do
  test -n "${!name:-}" || { echo "missing $name" >&2; exit 1; }
done

rm -rf "$DIST"
mkdir -p "$DIST"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
base64 -D <<<"$DEVELOPER_ID_APPLICATION_P12_BASE64" >"$RUNNER_TEMP/developer-id.p12"
security import "$RUNNER_TEMP/developer-id.p12" -k "$KEYCHAIN" -P "$DEVELOPER_ID_APPLICATION_P12_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

xcodebuild archive -project "$ROOT/CodexAuthBar.xcodeproj" -scheme CodexAuthBar \
  -configuration Release -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" MARKETING_VERSION="$VERSION"

APP="$ARCHIVE/Products/Applications/CodexAuthBar.app"
codesign --verify --deep --strict --verbose=2 "$APP"
ditto -c -k --keepParent "$APP" "$DIST/CodexAuthBar.zip"
base64 -D <<<"$APPLE_API_KEY_P8_BASE64" >"$RUNNER_TEMP/AuthKey_$APPLE_API_KEY_ID.p8"
xcrun notarytool submit "$DIST/CodexAuthBar.zip" --key "$RUNNER_TEMP/AuthKey_$APPLE_API_KEY_ID.p8" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID" --wait
xcrun stapler staple "$APP"

STAGE="$DIST/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Codex Auth Bar" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --force --sign "$SIGNING_IDENTITY" --keychain "$KEYCHAIN" "$DMG"
xcrun notarytool submit "$DMG" --key "$RUNNER_TEMP/AuthKey_$APPLE_API_KEY_ID.p8" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
shasum -a 256 "$DMG" >"$DMG.sha256"
