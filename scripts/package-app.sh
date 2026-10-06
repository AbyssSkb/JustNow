#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/JustNow.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCHIVE="$DIST/JustNow-$VERSION-universal"
STAGE="$(mktemp -d "$DIST/.package-app.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

codesign --verify --strict --verbose=2 "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGE/JustNow.zip"
mkdir -p "$STAGE/volume"
ditto "$APP" "$STAGE/volume/JustNow.app"
ln -s /Applications "$STAGE/volume/Applications"
hdiutil create -quiet -volname JustNow -srcfolder "$STAGE/volume" -format UDZO "$STAGE/JustNow.dmg"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$STAGE/JustNow.dmg"
  codesign --verify --strict --verbose=2 "$STAGE/JustNow.dmg"
fi
mv -f "$STAGE/JustNow.zip" "$ARCHIVE.zip"
mv -f "$STAGE/JustNow.dmg" "$ARCHIVE.dmg"
(
  cd "$DIST"
  shasum -a 256 "JustNow-$VERSION-universal.zip" "JustNow-$VERSION-universal.dmg" > "JustNow-$VERSION-SHA256.txt"
)
printf 'Packaged %s.{zip,dmg}\n' "$ARCHIVE"
