#!/bin/bash
set -euo pipefail
umask 077

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
if [[ ! -x "$SPARKLE_BIN_DIR/generate_appcast" || ! -x "$SPARKLE_BIN_DIR/sign_update" ]]; then
  printf 'Sparkle release tools not found. Build the app first or set SPARKLE_BIN_DIR.\n' >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/dist/JustNow.app/Contents/Info.plist")"
mkdir -p "$UPDATES"
STAGE="$(mktemp -d "$ROOT/dist/.update-feed.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
KEY_ARGS=(--account JustNow)
if [[ -n "${SPARKLE_PRIVATE_KEY:-}${SPARKLE_ED_KEY_FILE:-}" ]]; then
  python3 - "$STAGE/private-key" <<'PY'
import base64
import os
from pathlib import Path
import sys

secret = os.environ.get("SPARKLE_PRIVATE_KEY", "")
key_file = os.environ.get("SPARKLE_ED_KEY_FILE", "")
if secret and key_file:
    raise SystemExit("Use SPARKLE_PRIVATE_KEY or SPARKLE_ED_KEY_FILE, not both.")
try:
    encoded = secret.strip() if secret else Path(key_file).read_text().strip()
    key = base64.b64decode(encoded, validate=True)
except (ValueError, OSError):
    raise SystemExit("Invalid Sparkle private key file or encoding.")
if len(key) not in (32, 96):
    raise SystemExit("Sparkle private key must decode to 32 bytes or the legacy 96-byte format.")
Path(sys.argv[1]).write_text(base64.b64encode(key).decode() + "\n")
PY
  KEY_ARGS=(--ed-key-file "$STAGE/private-key")
fi
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
if ! "$SPARKLE_BIN_DIR/generate_appcast" "${ARGS[@]}" "${KEY_ARGS[@]}" "$STAGE" > "$STAGE/signing.log" 2>&1; then
  printf 'Sparkle appcast generation failed; check the private key and archive configuration.\n' >&2
  exit 1
fi
SIGNATURE="$(python3 - "$STAGE/appcast.xml" "$VERSION" "$STAGE/$ARCHIVE" "$DOWNLOAD_URL_PREFIX$ARCHIVE" <<'PY'
import base64
from pathlib import Path
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
        if signed and enclosure.get("url") == sys.argv[4] and enclosure.get("length") == str(Path(sys.argv[3]).stat().st_size):
            print(enclosure.get(sparkle + "edSignature"))
            break
else:
    raise SystemExit("No signed update for this version. Check the Sparkle private key before publishing.")
PY
)"
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT/dist/JustNow.app/Contents/Info.plist")"
swift "$ROOT/scripts/verify-update-signature.swift" "$PUBLIC_KEY" "$STAGE/$ARCHIVE" "$SIGNATURE"
for MODE in -p --verify; do
  if ! "$SPARKLE_BIN_DIR/sign_update" "${KEY_ARGS[@]}" "$MODE" "$STAGE/appcast.xml" > "$STAGE/signing.log" 2>&1; then
    printf 'Sparkle appcast signing or verification failed.\n' >&2
    exit 1
  fi
done
cp "$STAGE/$ARCHIVE" "$UPDATES/"
mv -f "$STAGE/appcast.xml" "$UPDATES/appcast.xml"
printf '\nUpload %s/appcast.xml and JustNow-%s-universal.zip to the same GitHub Release.\n' "$UPDATES" "$VERSION"
