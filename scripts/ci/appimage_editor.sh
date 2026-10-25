#!/usr/bin/env bash
# Linux: wraps the packaged editor (scripts/package_editor.sh's
# dist/rayzr-editor-linux) in an AppImage - one file users download, mark
# executable and run. appimagetool is downloaded if it isn't on PATH.
#   scripts/ci/appimage_editor.sh <version> [dist]
set -euo pipefail
cd "$(dirname "$0")/../.."
version="$1"
dist="${2:-dist}"
src="$dist/rayzr-editor-linux"
[ -x "$src/rayzr-editor" ] || { echo "no packaged editor in $src" >&2; exit 1; }

app="$dist/RayzrEditor.AppDir"
rm -rf "$app"
mkdir -p "$app/usr/lib/rayzr-editor"
cp -R "$src/." "$app/usr/lib/rayzr-editor/"
cp editor/assets/icon.png "$app/rayzr-editor.png"
cat > "$app/rayzr-editor.desktop" <<-EOF
	[Desktop Entry]
	Type=Application
	Name=Rayzr Editor
	Comment=2D game editor
	Exec=rayzr-editor
	Icon=rayzr-editor
	Categories=Development;Game;
	Terminal=false
	X-AppImage-Version=$version
EOF
cat > "$app/AppRun" <<-'EOF'
	#!/bin/sh
	# The editor finds its runners, fonts and language server next to itself.
	here="$(dirname "$(readlink -f "$0")")"
	exec "$here/usr/lib/rayzr-editor/rayzr-editor" "$@"
EOF
chmod +x "$app/AppRun"

tool=$(command -v appimagetool || true)
if [ -z "$tool" ]; then
	tool="$dist/appimagetool"
	curl -fsSL -o "$tool" https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
	chmod +x "$tool"
fi
# (--appimage-extract-and-run: no FUSE needed, e.g. in CI containers.)
ARCH=x86_64 "$tool" --appimage-extract-and-run "$app" "$dist/Rayzr_Editor-$version-x86_64.AppImage"
echo "Built $dist/Rayzr_Editor-$version-x86_64.AppImage"
