#!/bin/bash
set -euo pipefail

: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool Keychain profile}"
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application identity}"
if [[ "$SIGNING_IDENTITY" != "Developer ID Application:"* ]]; then
  printf 'A Developer ID Application certificate is required for notarization.\n' >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/JustNow.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCHIVE="$ROOT/dist/JustNow-$VERSION-universal"
STATUS_FILE="$(mktemp "$ROOT/dist/.notary-status.XXXXXX")"
trap 'rm -f "$STATUS_FILE"' EXIT
codesign --verify --deep --strict --verbose=2 "$APP"
SIGNATURE="$(codesign --display --verbose=4 "$APP" 2>&1)"
if [[ "$SIGNATURE" != *"Authority=$SIGNING_IDENTITY"* || "$SIGNATURE" != *"runtime"* || "$SIGNATURE" != *"Timestamp="* ]]; then
  printf 'Rebuild with SIGNING_IDENTITY before notarizing: Developer ID, hardened runtime and timestamp are required.\n' >&2
  exit 1
fi

submit() {
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$STATUS_FILE"
  STATUS="$(plutil -extract status raw -o - "$STATUS_FILE")"
  SUBMISSION="$(plutil -extract id raw -o - "$STATUS_FILE")"
  printf 'Notarization %s: %s\n' "$SUBMISSION" "$STATUS"
  if [[ "$STATUS" != Accepted ]]; then
    printf 'Notarization failed. Inspect the submission with xcrun notarytool log using your Keychain profile.\n' >&2
    exit 1
  fi
}

submit "$ARCHIVE.zip"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# ZIPs cannot be stapled. Repackage the stapled app, then notarize and staple the DMG.
"$ROOT/scripts/package-app.sh"
submit "$ARCHIVE.dmg"
xcrun stapler staple "$ARCHIVE.dmg"
xcrun stapler validate "$ARCHIVE.dmg"
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$ARCHIVE.dmg"
(
  cd "$ROOT/dist"
  shasum -a 256 "JustNow-$VERSION-universal.zip" "JustNow-$VERSION-universal.dmg" > "JustNow-$VERSION-SHA256.txt"
)
printf '\nNotarized and stapled: JustNow.app and JustNow-%s-universal.dmg\n' "$VERSION"
