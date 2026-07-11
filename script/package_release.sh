#!/usr/bin/env bash
set -euo pipefail

VERSION="${1#v}"
MARKETING_VERSION="${VERSION%%-*}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
RUNNER_TEMP="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
KEYCHAIN="$RUNNER_TEMP/codex-auth-bar-${GITHUB_RUN_ID:-$$}.keychain-db"
ARCHIVE="$DIST/CodexAuthBar.xcarchive"
DMG="$DIST/CodexAuthBar-$VERSION.dmg"
P12="$RUNNER_TEMP/developer-id.p12"
NOTARY_KEY=""
ORIGINAL_KEYCHAINS=()

while IFS= read -r keychain; do
  [[ -n "$keychain" ]] && ORIGINAL_KEYCHAINS+=("$keychain")
done < <(security list-keychains -d user | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')

cleanup() {
  if ((${#ORIGINAL_KEYCHAINS[@]})); then
    security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" >/dev/null 2>&1 || true
  fi
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  rm -f "$P12"
  if [[ -n "$NOTARY_KEY" ]]; then rm -f "$NOTARY_KEY"; fi
}
trap cleanup EXIT

for name in DEVELOPER_ID_APPLICATION_P12_BASE64 DEVELOPER_ID_APPLICATION_P12_PASSWORD APPLE_API_KEY_P8_BASE64 APPLE_API_KEY_ID APPLE_API_ISSUER_ID KEYCHAIN_PASSWORD DEVELOPMENT_TEAM SIGNING_IDENTITY; do
  test -n "${!name:-}" || { echo "missing $name" >&2; exit 1; }
done
NOTARY_KEY="$RUNNER_TEMP/AuthKey_$APPLE_API_KEY_ID.p8"

rm -rf "$DIST"
mkdir -p "$DIST"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security list-keychains -d user -s "$KEYCHAIN" "${ORIGINAL_KEYCHAINS[@]}"
base64 -D <<<"$DEVELOPER_ID_APPLICATION_P12_BASE64" >"$P12"
security import "$P12" -k "$KEYCHAIN" -P "$DEVELOPER_ID_APPLICATION_P12_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

xcodebuild archive -project "$ROOT/CodexAuthBar.xcodeproj" -scheme CodexAuthBar \
  -configuration Release -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" MARKETING_VERSION="$MARKETING_VERSION"

APP="$ARCHIVE/Products/Applications/CodexAuthBar.app"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/CodexAuthBar")"
test "$ARCHS" = "x86_64 arm64" || test "$ARCHS" = "arm64 x86_64"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --verbose=4 "$APP" 2>&1 | grep -q 'flags=.*runtime'
ditto -c -k --keepParent "$APP" "$DIST/CodexAuthBar.zip"
base64 -D <<<"$APPLE_API_KEY_P8_BASE64" >"$NOTARY_KEY"
xcrun notarytool submit "$DIST/CodexAuthBar.zip" --key "$NOTARY_KEY" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

STAGE="$DIST/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Codex Auth Bar" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --force --sign "$SIGNING_IDENTITY" --keychain "$KEYCHAIN" "$DMG"
xcrun notarytool submit "$DMG" --key "$NOTARY_KEY" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
shasum -a 256 "$DMG" >"$DMG.sha256"
