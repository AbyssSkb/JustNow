# Releasing JustNow

`macos.yml` tests main and pull requests. `release.yml` runs for `vX.Y.Z` tags, or manually for an existing tag by entering `X.Y.Z` without `v`. Releases use macOS 15, Xcode 26.3, and an explicit Swift 6.2 check. They build one universal macOS 14+ App for Apple Silicon and Intel.

## Repository configuration

The required GitHub Actions secret is **`SPARKLE_PRIVATE_KEY`**: the exported Sparkle Ed25519 private key as one base64 line. Current exports decode to a 32-byte seed; the legacy 96-byte export is also accepted. A raw 64-byte value is not a Sparkle export. Never commit this secret or include it in an artifact.

The public key is committed in `Resources/UpdateSigningPublicKey.txt`. The default feed is:

```text
https://github.com/AbyssSkb/JustNow/releases/latest/download/appcast.xml
```

The build adds `SUPublicEDKey`, `SURequireSignedFeed`, and `SUVerifyUpdateBeforeExtraction`. The archive is verified against the App's public key before publishing, and Sparkle signs and verifies the XML feed. Changing the public key requires a separate migration for already installed Apps; keep the existing private-key backup.

No repository Variables are required for Sparkle. The workflow's `GITHUB_TOKEN` needs the declared `contents: write` permission.

Apple signing is optional. Without these credentials, releases are **ad-hoc signed and not Apple notarized**, and the release notes say so. Sparkle signatures and the update feed are still required.

| Optional secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded Developer ID Application `.p12` export |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password protecting that export; required with the certificate |
| `APPLE_ID` | Apple account for notarization |
| `APPLE_TEAM_ID` | Apple Developer team for notarization |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for notarization |

Set all three notarization secrets together, with a Developer ID certificate. A certificate without notarization credentials produces a Developer ID signed release explicitly labelled as not notarized. Partial configuration fails instead of silently changing the signing mode.

The optional Variable `DEVELOPER_ID_SIGNING_IDENTITY` selects the exact `Developer ID Application: …` identity when necessary. A single imported identity is selected automatically. The runner creates and removes a temporary signing keychain; no extra keychain-password secret is needed.

## Publish

1. Update the version defaults and add the new version's notes to `CHANGELOG.md`. Commit and push the source, then push its `vX.Y.Z` tag. Manual dispatch builds that existing tag, not the selected branch.
2. The workflow validates the version, requires the Sparkle secret, and refuses any existing release for the tag, including drafts. Versions must increase relative to the latest release.
3. Tests run before the universal build. If configured, Developer ID signing and notarization finish before any Sparkle archive signature is generated.
4. The previous published appcast is retained with its original versioned download URLs. The new archive and XML feed are signed and verified. The workflow creates a draft with the ZIP, DMG, SHA256 manifest, and `appcast.xml`, downloads its assets, and compares every byte before publishing it as latest.

Release notes include only that version's changelog section and the actual signing/notarization status. GitHub also provides source archives for the immutable tag.

An upload or verification failure leaves an unpublished draft. Inspect it and resolve the failure; delete that draft before retrying the same tag. The workflow never uses `--clobber` and never replaces published assets. It also serializes release runs so the latest feed cannot be published from two workflows simultaneously.

## Local signing and verification

The public key and feed are default build inputs. Explicit `UPDATE_FEED_URL` and `UPDATE_PUBLIC_ED_KEY` environment values override them; setting both to empty is reserved for local builds without updates and preview fixtures. The release workflow verifies that its App uses the repository's public key, fixed HTTPS feed, and required feed signatures.

After building and optional notarization, use an exported private-key file with permissions `0600` in a protected directory:

```sh
DOWNLOAD_URL_PREFIX='https://github.com/AbyssSkb/JustNow/releases/download/v0.1.16/' \
SPARKLE_ED_KEY_FILE='/private/path/justnow-ed25519.key' \
./scripts/generate-update-feed.sh
```

Alternatively, supply `SPARKLE_PRIVATE_KEY` through the environment. The wrapper validates it without printing it and copies it into a `0600` file inside a `0700` temporary directory, removed on exit. If neither is supplied, the local tool uses the `JustNow` Keychain account. Tool failures are reported without exposing the private key. Previous feeds and archives are replaced only after verification succeeds.

Do not modify the final ZIP or `appcast.xml` after signing. Changing either invalidates its signature. Never reuse another project's signing key.

The minimal regression check uses explicitly public RFC test keys, never production keys or Keychain:

```sh
python3 scripts/check-update-signing.py
```

It requires the Sparkle tools already downloaded by `swift test` or `swift build`. Set `SPARKLE_BIN_DIR` if they are elsewhere. It verifies correct signatures and rejects wrong keys, malformed inputs, tampered archives, and tampered feeds. Public-key-only archive verification is also available as:

```sh
swift scripts/verify-update-signature.swift PUBLIC_KEY_BASE64 ARCHIVE_PATH SIGNATURE_BASE64
```

References: [Sparkle publishing](https://sparkle-project.org/documentation/publishing/) and the [macOS 15 runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md).

## Screenshots

Use English, a light appearance, and synthetic example data. Capture the native window with Command + Shift + 4 followed by Space, or `screencapture -x -l WINDOW_ID image.png`, keeping its native shadow. Screenshots must not contain real user records or other private content.
