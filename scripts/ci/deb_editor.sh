#!/usr/bin/env bash
# Linux: a .deb of the packaged editor (scripts/package_editor.sh's
# dist/rayzr-editor-linux): installed to /opt/rayzr-editor, `rayzr-editor` on PATH,
# a desktop entry and icon (Debian / Ubuntu: apt install ./file.deb).
#   scripts/ci/deb_editor.sh <version> [dist]
set -euo pipefail
cd "$(dirname "$0")/../.."
version="$1"
dist="${2:-dist}"
src="$dist/rayzr-editor-linux"
[ -x "$src/rayzr-editor" ] || { echo "no packaged editor in $src" >&2; exit 1; }
# Debian versions: no leading v; a pre-release sorts before its release (~).
debver=$(echo "${version#v}" | sed 's/-/~/')

root="$dist/deb"
rm -rf "$root"
mkdir -p "$root/DEBIAN" "$root/opt/rayzr-editor" "$root/usr/bin" "$root/usr/share/applications" "$root/usr/share/icons/hicolor/512x512/apps"
cp -R "$src/." "$root/opt/rayzr-editor/"
ln -s /opt/rayzr-editor/rayzr-editor "$root/usr/bin/rayzr-editor"
cp editor/assets/icon.png "$root/usr/share/icons/hicolor/512x512/apps/rayzr-editor.png"
cat > "$root/usr/share/applications/rayzr-editor.desktop" <<-EOF
	[Desktop Entry]
	Type=Application
	Name=Rayzr Editor
	Comment=2D game editor
	Exec=/opt/rayzr-editor/rayzr-editor
	Icon=rayzr-editor
	Categories=Development;Game;
	Terminal=false
EOF
size=$(du -sk "$root/opt" | cut -f1)
cat > "$root/DEBIAN/control" <<-EOF
	Package: rayzr-editor
	Version: $debver
	Section: devel
	Priority: optional
	Architecture: amd64
	Installed-Size: $size
	Depends: libc6 (>= 2.35), libgl1, libx11-6, libasound2 | libasound2t64
	Maintainer: Brandon Crowe <noreply@github.com>
	Homepage: https://github.com/bcrowe306/rayzr
	Description: Rayzr Editor - a 2D game editor
	 Scenes, Lua scripting, physics, LDtk levels, animation and export to
	 desktop platforms and the web, with the game runners included.
EOF
out="$dist/rayzr-editor_${debver}_amd64.deb"
dpkg-deb --root-owner-group --build "$root" "$out" > /dev/null
echo "Built $out"
