#!/usr/bin/env bash
# Signs a macOS .app with a Developer ID (hardened runtime, every dylib and
# executable inside) and notarizes it (release workflow; TODO C.4). From the
# repository secrets:
#   MACOS_CERTIFICATE            the Developer ID Application certificate (.p12, base64)
#   MACOS_CERTIFICATE_PASSWORD   its password
#   MACOS_SIGNING_IDENTITY       e.g. "Developer ID Application: Name (TEAMID)"
#   MACOS_NOTARY_APPLE_ID, MACOS_NOTARY_TEAM_ID, MACOS_NOTARY_PASSWORD
#                                (an app-specific password) for notarytool
#   scripts/ci/sign_macos.sh "dist/Ore Editor.app"
set -euo pipefail
app="$1"

# A temporary keychain with the certificate.
keychain="$RUNNER_TEMP/signing.keychain-db"
kpass=$(uuidgen)
echo "$MACOS_CERTIFICATE" | base64 --decode > "$RUNNER_TEMP/cert.p12"
security create-keychain -p "$kpass" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$kpass" "$keychain"
security import "$RUNNER_TEMP/cert.p12" -P "$MACOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$keychain"
security set-key-partition-list -S apple-tool:,apple: -s -k "$kpass" "$keychain" > /dev/null
security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')
rm -f "$RUNNER_TEMP/cert.p12"

sign() { codesign --force --timestamp --options runtime --sign "$MACOS_SIGNING_IDENTITY" "$@"; }
# Inside out: libraries and helper executables first, the app last.
find "$app/Contents" -type f \( -name '*.dylib' -o -perm -u+x \) ! -path '*/MacOS/*' -print0 |
	while IFS= read -r -d '' f; do
		if file "$f" | grep -q 'Mach-O'; then sign "$f"; fi
	done
sign "$app"
codesign --verify --deep --strict "$app"

# Notarize and staple (so it opens without a network check).
zip="$RUNNER_TEMP/notarize.zip"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --apple-id "$MACOS_NOTARY_APPLE_ID" --team-id "$MACOS_NOTARY_TEAM_ID" \
	--password "$MACOS_NOTARY_PASSWORD" --wait
xcrun stapler staple "$app"
echo "Signed and notarized $app"
