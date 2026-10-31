#!/usr/bin/env bash
# Packages the editor as an installed app (editor/resources.odin's layout):
# no Odin compiler, no source checkout, no Homebrew needed to run it.
#
#   scripts/package_editor.sh [--out dist] [--version 0.1.0] [--name "Rayzr Editor"]
#
#   macOS    dist/<name>.app
#              Contents/MacOS/rayzr-editor
#              Contents/Frameworks/*.dylib        (the editor's shared libraries)
#              Contents/Resources/runners/<platform>/, fonts/,
#                                 lua-language-server/, templates/ (demo_project + the New Project templates)
#   Linux,   dist/rayzr-editor-<platform>/
#   Windows    rayzr-editor[.exe], its libraries, runners/, fonts/,
#              lua-language-server/, templates/ (demo_project + the New Project templates)
#
# Runners: this platform's is built if missing (scripts/build_runners.sh);
# every runners/<platform>/ folder already in bin/runners (other platforms'
# from CI, the web one) is included, so the editor exports to all of them.
# Signing: ad-hoc on macOS (CI signs with a Developer ID and notarizes).
set -euo pipefail
cd "$(dirname "$0")/.."

out=dist
version=0.0.0-dev
name="Rayzr Editor"
while [ $# -gt 0 ]; do
	case "$1" in
		--out) out="$2"; shift 2 ;;
		--version) version="$2"; shift 2 ;;
		--name) name="$2"; shift 2 ;;
		*) echo "unknown option $1" >&2; exit 2 ;;
	esac
done

case "$(uname -s)" in
	Darwin) platform=macos; exe=rayzr-editor ;;
	Linux) platform=linux; exe=rayzr-editor ;;
	MINGW*|MSYS*|CYGWIN*) platform=windows; exe=rayzr-editor.exe ;;
	*) echo "Unknown platform $(uname -s)" >&2; exit 1 ;;
esac

echo "== runners"
scripts/build_runners.sh --if-missing

echo "== editor ($platform, $version)"
mkdir -p "$out"
if [ "$platform" = macos ]; then
	app="$out/$name.app"
	rm -rf "$app"
	bin="$app/Contents/MacOS"
	libs="$app/Contents/Frameworks"
	res="$app/Contents/Resources"
	mkdir -p "$bin" "$libs" "$res"
	odin build editor -o:speed '-extra-linker-flags:-Wl,-rpath,@executable_path/../Frameworks' $(scripts/odin_flags.sh) \
		-define:RAYZR_RELEASE="$version" -out:"$bin/$exe"
elif [ "$platform" = windows ]; then
	root="$out/rayzr-editor-$platform"
	rm -rf "$root"
	bin="$root"; libs="$root"; res="$root"
	mkdir -p "$root"
	# (-o:size when Odin crashes at -o:speed, as it has on Windows CI.)
	odin build editor -o:speed -subsystem:windows $(scripts/odin_flags.sh) -define:RAYZR_RELEASE="$version" -out:"$bin/$exe" ||
		odin build editor -o:size -subsystem:windows $(scripts/odin_flags.sh) -define:RAYZR_RELEASE="$version" -out:"$bin/$exe"
	# The icon, written into the linked exe (raylib.lib has its own resource:
	# the linker can't take a second one) - scripts/branding/set_exe_icon.odin.
	odin run scripts/branding/set_exe_icon.odin -file -out:"$out/set_exe_icon.exe" -- "$bin/$exe" editor/assets/icon.ico
	rm -f "$out"/set_exe_icon.*
	rm -f "$bin"/*.pdb
else
	root="$out/rayzr-editor-$platform"
	rm -rf "$root"
	bin="$root"; libs="$root"; res="$root"
	mkdir -p "$root"
	odin build editor -o:speed -define:RAYZR_RELEASE="$version" -out:"$bin/$exe" # (no bundled libraries: Lua and cmark are static)
fi

# The editor's shared libraries that aren't the system's (none since Lua and
# cmark are static; kept for a library linked dynamically later).
if [ "$platform" = macos ]; then
	for lib in $(otool -L "$bin/$exe" | awk 'NR > 1 {print $1}' | grep -E '^/(opt|usr/local)/'); do
		base=$(basename "$lib")
		cp "$lib" "$libs/$base"
		chmod u+w "$libs/$base"
		install_name_tool -id "@rpath/$base" "$libs/$base"
		install_name_tool -change "$lib" "@rpath/$base" "$bin/$exe"
	done
elif [ "$platform" = windows ]; then
	: # (Lua and cmark are static)
fi

echo "== resources"
mkdir -p "$res/runners" "$res/fonts" "$res/templates"
for d in bin/runners/*/; do
	cp -R "${d%/}" "$res/runners/" # (no trailing slash: BSD cp would copy the folder's contents)
done
cp engine/Open_Sans/static/OpenSans-Regular.ttf "$res/runners/"
cp licenses/THIRD_PARTY_NOTICES.txt "$res/runners/"
cp licenses/THIRD_PARTY_NOTICES.txt "$res/"
cp engine/Open_Sans/static/OpenSans-Regular.ttf "$res/fonts/"
# The Node Reference's screenshots (editor/node_reference.odin; the pages
# themselves are embedded).
mkdir -p "$res/docs" && cp -R docs/images "$res/docs/"
# The demo project, without per-user editor state.
cp -R assets/demo_project "$res/templates/demo_project"
rm -rf "$res/templates/demo_project/.rayzr" "$res/templates/demo_project/.editor_settings.ini" "$res/templates/demo_project/.luarc.json"
# The New Project templates (templates/: scripts/templates/make_templates.py).
for t in templates/*/; do cp -R "${t%/}" "$res/templates/"; done
# lua-language-server: what it runs (its generated meta files go to the user's
# cache folder: editor/code_editor_lsp.odin).
luals="lua-language-server"
if [ -x "$luals/bin/lua-language-server" ] || [ -f "$luals/bin/lua-language-server.exe" ]; then
	mkdir -p "$res/$luals/meta"
	cp -R "$luals/bin" "$luals/script" "$luals/locale" "$res/$luals/"
	cp "$luals/main.lua" "$res/$luals/"
	cp "$luals/debugger.lua" "$luals/LICENSE" "$res/$luals/" 2>/dev/null || true
	cp -R "$luals/meta/template" "$luals/meta/3rd" "$luals/meta/spell" "$res/$luals/meta/" 2>/dev/null || true
	rm -rf "$res/$luals/bin/log" "$res/$luals/bin"/*.dSYM
else
	echo "note: lua-language-server isn't built ($luals/make.sh): the Code tab will have no completion" >&2
fi

if [ "$platform" = macos ]; then
	cat > "$app/Contents/Info.plist" <<-EOF
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
		<key>CFBundleName</key><string>$name</string>
		<key>CFBundleDisplayName</key><string>$name</string>
		<key>CFBundleIdentifier</key><string>com.bcrowe306.rayzr-editor</string>
		<key>CFBundleExecutable</key><string>$exe</string>
		<key>CFBundleIconFile</key><string>AppIcon</string>
		<key>CFBundlePackageType</key><string>APPL</string>
		<key>CFBundleShortVersionString</key><string>$version</string>
		<key>CFBundleVersion</key><string>$version</string>
		<key>LSMinimumSystemVersion</key><string>12.0</string>
		<key>NSHighResolutionCapable</key><true/>
	</dict>
	</plist>
	EOF
	# The icon as AppIcon.icns (editor/assets/icon_macos.png: Apple's margins;
	# scripts/branding/make_icons.odin makes it from branding/).
	iconset="$out/AppIcon.iconset"
	rm -rf "$iconset"; mkdir -p "$iconset"
	for s in 16 32 128 256; do
		sips -z $s $s editor/assets/icon_macos.png --out "$iconset/icon_${s}x${s}.png" > /dev/null
		sips -z $((s * 2)) $((s * 2)) editor/assets/icon_macos.png --out "$iconset/icon_${s}x${s}@2x.png" > /dev/null
	done
	iconutil -c icns "$iconset" -o "$res/AppIcon.icns"
	rm -rf "$iconset"
	# Ad-hoc signatures (install_name_tool invalidated them); CI re-signs.
	codesign --force --deep -s - "$app" > /dev/null 2>&1 || true
	echo "Packaged $app"
else
	echo "Packaged $root"
fi
