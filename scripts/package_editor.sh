#!/usr/bin/env bash
# Packages the editor as an installed app (editor/resources.odin's layout):
# no Odin compiler, no source checkout, no Homebrew needed to run it.
#
#   scripts/package_editor.sh [--out dist] [--version 0.1.0] [--name "Ore Editor"]
#
#   macOS    dist/<name>.app
#              Contents/MacOS/ore-editor
#              Contents/Frameworks/*.dylib        (the editor's shared libraries)
#              Contents/Resources/runners/<platform>/, fonts/,
#                                 lua-language-server/, templates/demo_project/
#   Linux,   dist/ore-editor-<platform>/
#   Windows    ore-editor[.exe], its libraries, runners/, fonts/,
#              lua-language-server/, templates/demo_project/
#
# Runners: this platform's is built if missing (scripts/build_runners.sh);
# every runners/<platform>/ folder already in bin/runners (other platforms'
# from CI, the web one) is included, so the editor exports to all of them.
# Signing: ad-hoc on macOS (CI signs with a Developer ID and notarizes).
set -euo pipefail
cd "$(dirname "$0")/.."

out=dist
version=0.0.0-dev
name="Ore Editor"
while [ $# -gt 0 ]; do
	case "$1" in
		--out) out="$2"; shift 2 ;;
		--version) version="$2"; shift 2 ;;
		--name) name="$2"; shift 2 ;;
		*) echo "unknown option $1" >&2; exit 2 ;;
	esac
done

case "$(uname -s)" in
	Darwin) platform=macos; exe=ore-editor ;;
	Linux) platform=linux; exe=ore-editor ;;
	MINGW*|MSYS*|CYGWIN*) platform=windows; exe=ore-editor.exe ;;
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
	odin build editor -o:speed '-extra-linker-flags:-Wl,-rpath,@executable_path/../Frameworks' \
		-define:ORE_RELEASE="$version" -out:"$bin/$exe"
elif [ "$platform" = windows ]; then
	root="$out/ore-editor-$platform"
	rm -rf "$root"
	bin="$root"; libs="$root"; res="$root"
	mkdir -p "$root"
	odin build editor -o:speed -subsystem:windows -define:ORE_RELEASE="$version" -out:"$bin/$exe"
	rm -f "$bin"/*.pdb
else
	root="$out/ore-editor-$platform"
	rm -rf "$root"
	bin="$root"; libs="$root"; res="$root"
	mkdir -p "$root"
	odin build editor -o:speed '-extra-linker-flags:-Wl,-rpath,$ORIGIN' -define:ORE_RELEASE="$version" -out:"$bin/$exe"
fi

# The editor's shared libraries that aren't the system's (Homebrew's Lua and
# cmark on macOS until they're linked statically: TODO D.3 / D.4).
if [ "$platform" = macos ]; then
	for lib in $(otool -L "$bin/$exe" | awk 'NR > 1 {print $1}' | grep -E '^/(opt|usr/local)/'); do
		base=$(basename "$lib")
		cp "$lib" "$libs/$base"
		chmod u+w "$libs/$base"
		install_name_tool -id "@rpath/$base" "$libs/$base"
		install_name_tool -change "$lib" "@rpath/$base" "$bin/$exe"
	done
elif [ "$platform" = windows ]; then
	cp "$(odin root)/vendor/lua/5.4/windows/lua54.dll" "$libs/" 2>/dev/null || true
else
	# Linux: cmark isn't on every distribution (found next to the editor: $ORIGIN).
	for lib in $(ldd "$bin/$exe" | awk '/libcmark/ {print $3}'); do
		cp "$lib" "$libs/"
	done
fi

echo "== resources"
mkdir -p "$res/runners" "$res/fonts" "$res/templates"
for d in bin/runners/*/; do
	cp -R "${d%/}" "$res/runners/" # (no trailing slash: BSD cp would copy the folder's contents)
done
cp engine/Open_Sans/static/OpenSans-Regular.ttf "$res/runners/"
cp engine/Open_Sans/static/OpenSans-Regular.ttf "$res/fonts/"
# The demo project, without per-user editor state.
cp -R assets/demo_project "$res/templates/demo_project"
rm -rf "$res/templates/demo_project/.ore" "$res/templates/demo_project/.editor_settings.ini" "$res/templates/demo_project/.luarc.json"
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
		<key>CFBundleIdentifier</key><string>com.bcrowe306.ore-editor</string>
		<key>CFBundleExecutable</key><string>$exe</string>
		<key>CFBundlePackageType</key><string>APPL</string>
		<key>CFBundleShortVersionString</key><string>$version</string>
		<key>CFBundleVersion</key><string>$version</string>
		<key>LSMinimumSystemVersion</key><string>12.0</string>
		<key>NSHighResolutionCapable</key><true/>
	</dict>
	</plist>
	EOF
	# Ad-hoc signatures (install_name_tool invalidated them); CI re-signs.
	codesign --force --deep -s - "$app" > /dev/null 2>&1 || true
	echo "Packaged $app"
else
	echo "Packaged $root"
fi
