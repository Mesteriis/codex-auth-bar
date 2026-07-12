#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-v0.1.0-alpha.1}"
VERSION="${TAG#v}"
MARKETING_VERSION="${VERSION%%-*}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$ROOT/build/unsigned-preview"
DIST="$ROOT/dist"
APP="$DERIVED/Build/Products/Release/CodexAuthBar.app"
WIDGET="$APP/Contents/PlugIns/CodexAuthWidget.appex"
STAGE="$ROOT/build/unsigned-preview-dmg"
ZIP="$DIST/CodexAuthBar-$VERSION-unsigned.zip"
DMG="$DIST/CodexAuthBar-$VERSION-unsigned.dmg"

[[ "$VERSION" == *-alpha.* ]] || {
  echo "unsigned preview version must contain -alpha." >&2
  exit 2
}

rm -rf "$DERIVED" "$STAGE" "$ZIP" "$ZIP.sha256" "$DMG" "$DMG.sha256"
mkdir -p "$DIST" "$STAGE"

xcodebuild build \
  -project "$ROOT/CodexAuthBar.xcodeproj" \
  -scheme CodexAuthBar \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$MARKETING_VERSION"

test -d "$APP"
test -d "$WIDGET"

# Ad-hoc signing makes the nested bundle structurally valid for local testing.
# It does not provide Developer ID trust and is not notarization.
codesign --force --sign - \
  --entitlements "$ROOT/src/Entitlements/CodexAuthWidget.local.entitlements" \
  "$WIDGET"
codesign --force --sign - \
  --entitlements "$ROOT/src/Entitlements/CodexAuthBar.entitlements" \
  "$APP"

for binary in "$APP/Contents/MacOS/CodexAuthBar" "$WIDGET/Contents/MacOS/CodexAuthWidget"; do
  archs="$(lipo -archs "$binary")"
  [[ "$archs" == 'arm64 x86_64' || "$archs" == 'x86_64 arm64' ]]
done

codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -q 'Signature=adhoc'
codesign -dv --verbose=4 "$WIDGET" 2>&1 | grep -q 'Signature=adhoc'

ditto -c -k --keepParent "$APP" "$ZIP"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create \
  -volname "Codex Auth Bar — Unsigned Preview" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

hdiutil verify "$DMG"
unzip -tq "$ZIP"
shasum -a 256 "$DMG" >"$DMG.sha256"
shasum -a 256 "$ZIP" >"$ZIP.sha256"

printf 'Unsigned preview created:\n%s\n%s\n' "$DMG" "$ZIP"
