#!/usr/bin/env bash
# Installs what building the editor and the runners needs on a CI machine
# (GitHub Actions: macOS arm64, Ubuntu x64, Windows x64 under Git Bash),
# after Odin itself (laytan/setup-odin). The official Odin release already
# ships raylib for every platform, Lua for Windows / Linux and Box2D for
# macOS / Windows; the rest comes from here:
#   macOS    cmark (Homebrew; linked dynamically until TODO D.4)
#   Linux    X11 / GL / ALSA headers, cmark, Box2D (built from source), ImGui
#   Windows  cmark (built from source as a static library), Lua (static), ImGui
set -euo pipefail
cd "$(dirname "$0")/../.."
odin_root=$(odin root)

case "$(uname -s)" in
Darwin)
	brew install cmark > /dev/null
	scripts/build_imgui.sh --if-missing
	;;
Linux)
	sudo apt-get update -qq
	sudo apt-get install -y -qq libx11-dev libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev \
		libgl1-mesa-dev libasound2-dev libcmark-dev cmake python3-venv xvfb > /dev/null
	if ! ls "$odin_root"/vendor/box2d/lib/box2d_linux_amd64*.a > /dev/null 2>&1; then
		(cd "$odin_root/vendor/box2d" && bash build_box2d.sh > /dev/null)
	fi
	scripts/build_imgui.sh --if-missing
	;;
MINGW*|MSYS*|CYGWIN*)
	cm="$odin_root/vendor/commonmark"
	if [ ! -f "$cm/cmark_static.lib" ]; then
		tmp=$(mktemp -d)
		git clone -q --depth 1 --branch 0.31.1 https://github.com/commonmark/cmark.git "$tmp/cmark"
		cmake -S "$tmp/cmark" -B "$tmp/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
			-DBUILD_TESTING=OFF -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded > /dev/null
		cmake --build "$tmp/build" --config Release > /dev/null
		cp "$(find "$tmp/build" -name 'cmark.lib' | head -1)" "$cm/cmark_static.lib"
	fi
	scripts/build_imgui.sh --if-missing
	scripts/build_lua.sh --if-missing
	;;
esac
echo "Dependencies ready"
