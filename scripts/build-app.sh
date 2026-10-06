#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.1.2}"
DIST="$ROOT/dist"
APP="$DIST/JustNow.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'VERSION must be a numeric semantic version, such as 0.1.2.\n' >&2
  exit 1
fi
if [[ -n "${SIGNING_IDENTITY:-}" && "$SIGNING_IDENTITY" != "Developer ID Application:"* ]]; then
  printf 'SIGNING_IDENTITY must be a Developer ID Application identity.\n' >&2
  exit 1
fi

mkdir -p "$DIST"
STAGE="$(mktemp -d "$DIST/.build-app.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

for ARCH in arm64 x86_64; do
  BUILD_ARGS=(--package-path "$ROOT" --configuration release --product JustNow
    --triple "$ARCH-apple-macosx14.0" --sdk "$SDK" --scratch-path "$ROOT/.build-release/$ARCH")
  swift build "${BUILD_ARGS[@]}"
  BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
  cp "$BIN_PATH/JustNow" "$STAGE/JustNow-$ARCH"
done

CONTENTS="$STAGE/JustNow.app/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
lipo -create "$STAGE/JustNow-arm64" "$STAGE/JustNow-x86_64" -output "$CONTENTS/MacOS/JustNow"
lipo "$CONTENTS/MacOS/JustNow" -verify_arch arm64 x86_64
cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>JustNow</string>
  <key>CFBundleDisplayName</key><string>JustNow</string>
  <key>CFBundleExecutable</key><string>JustNow</string>
  <key>CFBundleIdentifier</key><string>io.github.abyssskb.justnow</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 JustNow contributors. MIT License.</string>
</dict></plist>
PLIST
plutil -lint "$CONTENTS/Info.plist"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$STAGE/JustNow.app"
  SIGNING_LABEL="Developer ID signed; notarization still required"
else
  codesign --force --sign - "$STAGE/JustNow.app"
  SIGNING_LABEL="Ad-hoc signed; NOT notarized"
fi
codesign --verify --strict --verbose=2 "$STAGE/JustNow.app"

rm -rf "$APP"
mv "$STAGE/JustNow.app" "$APP"
"$ROOT/scripts/package-app.sh"
printf '\nBuilt %s\n%s\n' "$APP" "$SIGNING_LABEL"
