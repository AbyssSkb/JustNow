#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.1.8}"
DIST="$ROOT/dist"
APP="$DIST/JustNow.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'VERSION must be a numeric semantic version, such as 0.1.8.\n' >&2
  exit 1
fi
python3 - <<'PY'
import base64
import os
from urllib.parse import urlsplit

feed = os.environ.get("UPDATE_FEED_URL", "")
key = os.environ.get("UPDATE_PUBLIC_ED_KEY", "")
if bool(feed) != bool(key):
    raise SystemExit("Set UPDATE_FEED_URL and UPDATE_PUBLIC_ED_KEY together, or omit both.")
if feed:
    url = urlsplit(feed)
    if url.scheme != "https" or not url.hostname or url.username or url.password or url.fragment:
        raise SystemExit("UPDATE_FEED_URL must be an HTTPS URL without credentials or a fragment.")
    try:
        valid_key = len(base64.b64decode(key, validate=True)) == 32
    except ValueError:
        valid_key = False
    if not valid_key:
        raise SystemExit("UPDATE_PUBLIC_ED_KEY must be a base64-encoded 32-byte Ed25519 public key.")
PY
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
  if [[ "$ARCH" == "arm64" ]]; then
    cp "$BIN_PATH/JustNow_JustNow.bundle/BrandMark.png" "$STAGE/BrandMark.png"
    SPARKLE_SOURCE="$ROOT/.build-release/$ARCH/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
    if [[ ! -d "$SPARKLE_SOURCE" ]]; then
      printf 'Sparkle framework not found: %s\n' "$SPARKLE_SOURCE" >&2
      exit 1
    fi
    ditto "$SPARKLE_SOURCE" "$STAGE/Sparkle.framework"
  fi
done

CONTENTS="$STAGE/JustNow.app/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"
lipo -create "$STAGE/JustNow-arm64" "$STAGE/JustNow-x86_64" -output "$CONTENTS/MacOS/JustNow"
lipo "$CONTENTS/MacOS/JustNow" -verify_arch arm64 x86_64
cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
cp "$STAGE/BrandMark.png" "$CONTENTS/Resources/BrandMark.png"
ditto "$STAGE/Sparkle.framework" "$CONTENTS/Frameworks/Sparkle.framework"
lipo "$CONTENTS/Frameworks/Sparkle.framework/Sparkle" -verify_arch arm64 x86_64
python3 - "$CONTENTS/Info.plist" "$VERSION" <<'PY'
import os
import plistlib
import sys

info = {
    "CFBundleName": "JustNow",
    "CFBundleDisplayName": "JustNow",
    "CFBundleExecutable": "JustNow",
    "CFBundleIdentifier": "io.github.abyssskb.justnow",
    "CFBundlePackageType": "APPL",
    "CFBundleLocalizations": ["en", "zh-Hans"],
    "CFBundleDevelopmentRegion": "en",
    "CFBundleShortVersionString": sys.argv[2],
    "CFBundleVersion": sys.argv[2],
    "CFBundleIconFile": "AppIcon",
    "LSMinimumSystemVersion": "14.0",
    "NSHighResolutionCapable": True,
    "NSPrincipalClass": "NSApplication",
    "NSHumanReadableCopyright": "Copyright © 2026 JustNow contributors. MIT License.",
    "SUEnableAutomaticChecks": True,
    "SUAutomaticallyUpdate": False,
    "SUAllowsAutomaticUpdates": False,
    "SUEnableSystemProfiling": False,
}
if os.environ.get("UPDATE_FEED_URL"):
    info["SUFeedURL"] = os.environ["UPDATE_FEED_URL"]
    info["SUPublicEDKey"] = os.environ["UPDATE_PUBLIC_ED_KEY"]
with open(sys.argv[1], "wb") as file:
    plistlib.dump(info, file)
PY
plutil -lint "$CONTENTS/Info.plist"

SIGN_ARGS=(--force --sign "${SIGNING_IDENTITY:--}")
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  SIGN_ARGS+=(--timestamp)
fi
SPARKLE="$CONTENTS/Frameworks/Sparkle.framework"
for HELPER in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
  HELPER_PATH="$SPARKLE/Versions/Current/$HELPER"
  if [[ "$HELPER" == XPCServices/Downloader.xpc ]]; then
    codesign "${SIGN_ARGS[@]}" --options runtime --preserve-metadata=entitlements "$HELPER_PATH"
  else
    codesign "${SIGN_ARGS[@]}" --options runtime "$HELPER_PATH"
  fi
  codesign --verify --strict --verbose=2 "$HELPER_PATH"
done
codesign "${SIGN_ARGS[@]}" --options runtime "$SPARKLE"
codesign --verify --strict --verbose=2 "$SPARKLE"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$STAGE/JustNow.app"
  SIGNING_LABEL="Developer ID signed; notarization still required"
else
  codesign --force --sign - "$STAGE/JustNow.app"
  SIGNING_LABEL="Ad-hoc signed; NOT notarized"
fi
codesign --verify --deep --strict --verbose=2 "$STAGE/JustNow.app"

rm -rf "$APP"
mv "$STAGE/JustNow.app" "$APP"
"$ROOT/scripts/package-app.sh"
printf '\nBuilt %s\n%s\n' "$APP" "$SIGNING_LABEL"
