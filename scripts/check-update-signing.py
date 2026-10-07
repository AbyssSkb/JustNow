#!/usr/bin/env python3
"""Check archive and appcast signing using an explicitly public, nonproduction fixture."""
import base64
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
signer = Path(os.environ.get("SPARKLE_BIN_DIR", root / ".build/artifacts/sparkle/Sparkle/bin")) / "sign_update"
if not signer.is_file() or not os.access(signer, os.X_OK):
    raise SystemExit("Sparkle sign_update is missing; set SPARKLE_BIN_DIR to its bin directory.")
signer = signer.resolve()
verifier = root / "scripts/verify-update-signature.swift"

# Public RFC 8032 section 7.1 test vectors; never use these keys for releases.
# https://www.rfc-editor.org/rfc/rfc8032#section-7.1
fixture_seed_hex = "9d61b19deffd5a60ba844af492ec2cc4" "4449c5697b326919703bac031cae7f60"
fixture_key = base64.b64encode(bytes.fromhex(fixture_seed_hex)).decode() + "\n"
public = base64.b64encode(bytes.fromhex(
    "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
)).decode()
wrong_public = base64.b64encode(bytes.fromhex(
    "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"
)).decode()

with tempfile.TemporaryDirectory(prefix="justnow-update-signing-check-") as directory:
    work = Path(directory)
    work.chmod(0o700)

    def command(arguments, *, stdin=None, succeeds=True):
        # Capture both streams: Sparkle diagnostics may include supplied key data.
        result = subprocess.run(arguments, input=stdin, text=True, capture_output=True, cwd=work)
        assert (result.returncode == 0) == succeeds, "Signing regression command failed"
        return result.stdout.strip()

    archive = work / "fixture.zip"
    archive.write_bytes(b"JustNow signing regression archive fixture\n")
    signature = command([str(signer), "--ed-key-file", "-", "-p", str(archive)], stdin=fixture_key)
    assert len(base64.b64decode(signature, validate=True)) == 64, "Invalid fixture signature"
    command(["swift", str(verifier), public, str(archive), signature])
    command(["swift", str(verifier), wrong_public, str(archive), signature], succeeds=False)
    for invalid_public, invalid_signature in [("!", signature), ("AA==", signature), (public, "!"), (public, "AA==")]:
        command(["swift", str(verifier), invalid_public, str(archive), invalid_signature], succeeds=False)
    command(["swift", str(verifier), public, str(work / "missing.zip"), signature], succeeds=False)

    feed = work / "appcast.xml"
    feed.write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel><title>fixture</title><link>https://example.invalid/</link><description>Signing fixture</description>
<item><title>Fixture update</title><sparkle:version>1</sparkle:version>
<enclosure url="https://example.invalid/fixture.zip" type="application/octet-stream"
length="{archive.stat().st_size}" sparkle:edSignature="{signature}"/></item></channel></rss>
''')
    command([str(signer), "--ed-key-file", "-", "-p", str(feed)], stdin=fixture_key)
    command([str(signer), "--verify", "--ed-key-file", "-", str(feed)], stdin=fixture_key)
    feed.write_text(feed.read_text().replace("<title>fixture</title>", "<title>changed</title>", 1))
    command([str(signer), "--verify", "--ed-key-file", "-", str(feed)], stdin=fixture_key, succeeds=False)
    archive.write_bytes(b"justNow signing regression archive fixture\n")
    command(["swift", str(verifier), public, str(archive), signature], succeeds=False)

print("PASS: archive verification, wrong key, malformed inputs, archive tampering, and signed feed tampering")
