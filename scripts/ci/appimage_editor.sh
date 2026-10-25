#!/usr/bin/env bash
# Linux: wraps the packaged editor (scripts/package_editor.sh's
# dist/ore-editor-linux) in an AppImage - one file users download, mark
# executable and run. appimagetool is downloaded if it isn't on PATH.
#   scripts/ci/appimage_editor.sh <version> [dist]
set -euo pipefail
cd "$(dirname "$0")/../.."
version="$1"
dist="${2:-dist}"
src="$dist/ore-editor-linux"
[ -x "$src/ore-editor" ] || { echo "no packaged editor in $src" >&2; exit 1; }

app="$dist/OreEditor.AppDir"
rm -rf "$app"
mkdir -p "$app/usr/lib/ore-editor"
cp -R "$src/." "$app/usr/lib/ore-editor/"
cp editor/assets/icon.png "$app/ore-editor.png"
cat > "$app/ore-editor.desktop" <<-EOF
	[Desktop Entry]
	Type=Application
	Name=Ore Editor
	Comment=2D game editor
	Exec=ore-editor
	Icon=ore-editor
	Categories=Development;Game;
	Terminal=false
	X-AppImage-Version=$version
EOF
cat > "$app/AppRun" <<-'EOF'
	#!/bin/sh
	# The editor finds its runners, fonts and language server next to itself.
	here="$(dirname "$(readlink -f "$0")")"
	exec "$here/usr/lib/ore-editor/ore-editor" "$@"
EOF
chmod +x "$app/AppRun"

tool=$(command -v appimagetool || true)
if [ -z "$tool" ]; then
	tool="$dist/appimagetool"
	curl -fsSL -o "$tool" https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
	chmod +x "$tool"
fi
# (--appimage-extract-and-run: no FUSE needed, e.g. in CI containers.)
ARCH=x86_64 "$tool" --appimage-extract-and-run "$app" "$dist/Ore_Editor-$version-x86_64.AppImage"
echo "Built $dist/Ore_Editor-$version-x86_64.AppImage"
