#!/usr/bin/env bash
# Builds the standalone game runner for this platform (release) into
# bin/runners/<platform>/, with the UI font in bin/runners/. The editor's
# Export Standalone Game copies it next to the game's .ore - no compiler
# needed when exporting. Run it on each platform you ship for and copy the
# runners/<platform>/ folders next to the editor (or into bin/runners/).
#   scripts/build_runners.sh            # release (-o:speed)
#   scripts/build_runners.sh -debug     # extra odin flags
#   scripts/build_runners.sh --if-missing  # only when there's no runner yet
#
# Everything in runners/<platform>/ besides the runner (shared libraries)
# ships with the game: next to the executable, or in Contents/Frameworks
# of a macOS .app.
#
# macOS: Lua comes from Homebrew as a shared library; it's copied next to
# the runner and referenced as @rpath/liblua.dylib (found next to the
# executable or in the .app's Frameworks). The runner is universal
# (arm64 + x86_64) when the x86_64 libraries (raylib, Box2D, Lua) are
# installed; otherwise it's built for this Mac's architecture only.
set -euo pipefail
cd "$(dirname "$0")/.."
case "$(uname -s)" in
	Darwin) platform=macos; exe=runner ;;
	Linux) platform=linux; exe=runner ;;
	MINGW*|MSYS*|CYGWIN*) platform=windows; exe=runner.exe ;;
	*) echo "Unknown platform $(uname -s)" >&2; exit 1 ;;
esac
out="bin/runners/$platform"
if [ "${1:-}" = --if-missing ]; then
	shift
	[ -x "$out/$exe" ] && { echo "$out/$exe exists"; exit 0; }
fi
rm -rf "$out"
mkdir -p "$out"

if [ "$platform" = macos ]; then
	rpath='-extra-linker-flags:-Wl,-rpath,@executable_path/../Frameworks'
	native=$(uname -m)
	odin build runner -o:speed "$rpath" -out:"$out/runner-$native" "$@"
	other=x86_64; target=darwin_amd64
	[ "$native" = x86_64 ] && other=arm64 && target=darwin_arm64
	if odin build runner -o:speed "$rpath" -target:$target -out:"$out/runner-$other" "$@" > "$out/.other.log" 2>&1; then
		lipo -create -output "$out/$exe" "$out/runner-$native" "$out/runner-$other"
		echo "Universal runner ($native + $other)"
	else
		echo "Note: no $other build ($(grep -m1 -o 'Could not find[^,]*\|Error:.*' "$out/.other.log" || echo 'see the log')); the runner is $native only."
		mv "$out/runner-$native" "$out/$exe"
	fi
	rm -f "$out/runner-$native" "$out/runner-$other" "$out/.other.log"

	# Ship Lua's shared library with the runner.
	lualib=$(otool -L "$out/$exe" | awk '/liblua/ {print $1; exit}')
	if [ -n "$lualib" ] && [ "${lualib#@rpath}" = "$lualib" ]; then
		cp "$lualib" "$out/liblua.dylib"
		chmod u+w "$out/liblua.dylib"
		install_name_tool -id @rpath/liblua.dylib "$out/liblua.dylib"
		install_name_tool -change "$lualib" @rpath/liblua.dylib "$out/$exe"
		# install_name_tool invalidates the (ad-hoc) signatures.
		codesign --force -s - "$out/liblua.dylib" "$out/$exe" 2>/dev/null
	fi
elif [ "$platform" = windows ]; then
	odin build runner -o:speed -subsystem:windows -out:"$out/$exe" "$@"
	cp "$(odin root)/vendor/lua/5.4/windows/lua54.dll" "$out/"
else
	odin build runner -o:speed -out:"$out/$exe" "$@"
fi
cp engine/Open_Sans/static/OpenSans-Regular.ttf bin/runners/
echo "Built $out/$exe"
