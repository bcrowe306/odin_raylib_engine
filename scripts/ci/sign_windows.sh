#!/usr/bin/env bash
# Signs the Windows editor and runners with a code-signing certificate
# (release workflow; TODO C.5) so SmartScreen doesn't warn. From the
# repository secrets:
#   WINDOWS_CERTIFICATE           the certificate (.pfx, base64)
#   WINDOWS_CERTIFICATE_PASSWORD  its password
# (Azure Trusted Signing works too: replace the signtool line with the
# azure/trusted-signing-action step.)
#   scripts/ci/sign_windows.sh dist/rayzr-editor-windows
set -euo pipefail
dir="$1"
pfx="$RUNNER_TEMP/cert.pfx"
echo "$WINDOWS_CERTIFICATE" | base64 --decode > "$pfx"
# signtool comes with the Windows SDK (on PATH after ilammy/msvc-dev-cmd).
find "$dir" -type f \( -name '*.exe' -o -name '*.dll' \) -print0 |
	while IFS= read -r -d '' f; do
		signtool sign -fd SHA256 -td SHA256 -tr http://timestamp.digicert.com \
			-f "$(cygpath -w "$pfx")" -p "$WINDOWS_CERTIFICATE_PASSWORD" "$(cygpath -w "$f")"
	done
rm -f "$pfx"
echo "Signed the executables in $dir"
