#!/usr/bin/env bash
# Builds the standalone game runner for this platform into
# bin/runners/<platform>/ - runner (release) and runner-debug (debug info,
# a console on Windows; export presets with "Debug" use it) - with the UI
# font in bin/runners/. The editor's
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
# Lua is linked statically (engine/lua54/lib: scripts/build_lua.sh). macOS:
# the runner is universal (arm64 + x86_64) when the x86_64 libraries
# (raylib, Box2D) are installed; otherwise it's built for this Mac's
# architecture only. (A shared Lua library, if one is ever linked, is still
# copied next to it as @rpath/liblua.dylib.)
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
	# Only with the other architecture's libraries (else the build can't link).
	built_other=0
	if ls "$(odin root)"/vendor/box2d/lib/box2d_${target}*.a > /dev/null 2>&1; then
		if perl -e 'alarm 600; exec @ARGV' odin build runner -o:speed "$rpath" -target:$target -out:"$out/runner-$other" "$@" > "$out/.other.log" 2>&1; then
			built_other=1
		fi
	else
		echo "Box2D for $other isn't built (vendor/box2d/build_box2d.sh)" > "$out/.other.log"
	fi
	if [ $built_other = 1 ]; then
		lipo -create -output "$out/$exe" "$out/runner-$native" "$out/runner-$other"
		echo "Universal runner ($native + $other)"
	else
		echo "Note: no $other build ($(grep -m1 -o "Could not find[^,]*\|Error:.*\|Box2D.*" "$out/.other.log" || echo 'see the log')); the runner is $native only."
		mv "$out/runner-$native" "$out/$exe"
	fi
	rm -f "$out/runner-$native" "$out/runner-$other" "$out/.other.log"
	odin build runner -debug "$rpath" -out:"$out/runner-debug" "$@"

	# Ship Lua's shared library with the runners.
	lualib=$(otool -L "$out/$exe" | awk '/liblua/ {print $1; exit}')
	if [ -n "$lualib" ] && [ "${lualib#@rpath}" = "$lualib" ]; then
		cp "$lualib" "$out/liblua.dylib"
		chmod u+w "$out/liblua.dylib"
		install_name_tool -id @rpath/liblua.dylib "$out/liblua.dylib"
		for r in "$out/$exe" "$out/runner-debug"; do install_name_tool -change "$lualib" @rpath/liblua.dylib "$r"; done
		# install_name_tool invalidates the (ad-hoc) signatures.
		codesign --force -s - "$out/liblua.dylib" "$out/$exe" "$out/runner-debug" 2>/dev/null
	fi
	rm -rf "$out"/*.dSYM
elif [ "$platform" = windows ]; then
	odin build runner -o:speed -subsystem:windows -out:"$out/$exe" "$@"
	odin build runner -debug -out:"$out/runner-debug.exe" "$@"
	rm -f "$out"/*.pdb
else
	odin build runner -o:speed -out:"$out/$exe" "$@"
	odin build runner -debug -out:"$out/runner-debug" "$@"
fi
cp engine/Open_Sans/static/OpenSans-Regular.ttf bin/runners/
echo "Built $out/$exe"
# The web runner too when emscripten is installed (scripts/build_web_runner.sh).
if command -v emcc >/dev/null; then
	scripts/build_web_runner.sh >/dev/null && echo "Built bin/runners/web"
fi
