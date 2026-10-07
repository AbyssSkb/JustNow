#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPDATES="${1:-$ROOT/dist/update-feed}"
SPARKLE_BIN_DIR="${SPARKLE_BIN_DIR:-$ROOT/.build-release/arm64/artifacts/sparkle/Sparkle/bin}"
: "${DOWNLOAD_URL_PREFIX:?Set DOWNLOAD_URL_PREFIX to the HTTPS GitHub Release asset directory}"
python3 - "$DOWNLOAD_URL_PREFIX" "$ROOT/dist/JustNow.app/Contents/Info.plist" <<'PY'
import plistlib
import sys
from urllib.parse import urlsplit

url = urlsplit(sys.argv[1])
if url.scheme != "https" or not url.hostname or url.username or url.password or url.query or url.fragment:
    raise SystemExit("DOWNLOAD_URL_PREFIX must be an HTTPS URL without credentials, query or fragment.")
if not sys.argv[1].endswith("/"):
    raise SystemExit("DOWNLOAD_URL_PREFIX must end with a slash.")
with open(sys.argv[2], "rb") as file:
    info = plistlib.load(file)
if not info.get("SUFeedURL") or not info.get("SUPublicEDKey"):
    raise SystemExit("Rebuild with UPDATE_FEED_URL and UPDATE_PUBLIC_ED_KEY before generating an update feed.")
PY
if [[ ! -x "$SPARKLE_BIN_DIR/generate_appcast" ]]; then
  printf 'Sparkle generate_appcast not found in %s. Build the app first or set SPARKLE_BIN_DIR.\n' "$SPARKLE_BIN_DIR" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/dist/JustNow.app/Contents/Info.plist")"
mkdir -p "$UPDATES"
STAGE="$(mktemp -d "$ROOT/dist/.update-feed.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ARCHIVE="JustNow-$VERSION-universal.zip"
cp "$ROOT/dist/$ARCHIVE" "$STAGE/"
if [[ -f "$UPDATES/appcast.xml" ]]; then
  cp "$UPDATES/appcast.xml" "$STAGE/"
fi
for EXTENSION in html md txt; do
  NOTES="$UPDATES/${ARCHIVE%.zip}.$EXTENSION"
  if [[ -f "$NOTES" ]]; then
    cp "$NOTES" "$STAGE/"
  fi
done
# Only the new archive may receive this release tag's download prefix.
ARGS=(--download-url-prefix "$DOWNLOAD_URL_PREFIX" --maximum-deltas 0 --embed-release-notes
  -o "$STAGE/appcast.xml")
if [[ -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
  ARGS+=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
fi
"$SPARKLE_BIN_DIR/generate_appcast" "${ARGS[@]}" "$STAGE"
python3 - "$STAGE/appcast.xml" "$VERSION" <<'PY'
import base64
import sys
import xml.etree.ElementTree as ET

sparkle = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
for item in ET.parse(sys.argv[1]).findall("./channel/item"):
    enclosure = item.find("enclosure")
    if enclosure is None:
        continue
    version = item.findtext(sparkle + "version") or enclosure.get(sparkle + "version")
    if version == sys.argv[2]:
        try:
            signed = len(base64.b64decode(enclosure.get(sparkle + "edSignature", ""), validate=True)) == 64
        except ValueError:
            signed = False
        if signed:
            break
else:
    raise SystemExit("No signed update for this version. Check the Sparkle private key before publishing.")
PY
cp "$ROOT/dist/$ARCHIVE" "$UPDATES/"
mv -f "$STAGE/appcast.xml" "$UPDATES/appcast.xml"
printf '\nUpload %s/appcast.xml and JustNow-%s-universal.zip to the same GitHub Release.\n' "$UPDATES" "$VERSION"
