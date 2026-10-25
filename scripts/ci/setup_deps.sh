#!/usr/bin/env bash
# Installs what building the editor and the runners needs on a CI machine
# (GitHub Actions: macOS arm64, Ubuntu x64, Windows x64 under Git Bash),
# after Odin itself (laytan/setup-odin). The official Odin release already
# ships raylib for every platform, Lua for Windows / Linux and Box2D for
# macOS / Windows; the rest comes from here:
#   macOS    nothing (ImGui, Lua and cmark static libraries are in the repo)
#   Linux    X11 / GL / ALSA headers, Box2D (built from source), ImGui, cmark (static)
#   Windows  ImGui, Lua and cmark (static, MSVC)
set -euo pipefail
cd "$(dirname "$0")/../.."
odin_root=$(odin root)

case "$(uname -s)" in
Darwin)
	scripts/build_imgui.sh --if-missing
	scripts/build_cmark.sh --if-missing
	;;
Linux)
	sudo apt-get update -qq
	sudo apt-get install -y -qq libx11-dev libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev \
		libgl1-mesa-dev libasound2-dev cmake python3-venv xvfb > /dev/null
	if ! ls "$odin_root"/vendor/box2d/lib/box2d_linux_amd64*.a > /dev/null 2>&1; then
		(cd "$odin_root/vendor/box2d" && bash build_box2d.sh > /dev/null)
	fi
	scripts/build_imgui.sh --if-missing
	scripts/build_cmark.sh --if-missing
	;;
MINGW*|MSYS*|CYGWIN*)
	scripts/build_imgui.sh --if-missing
	scripts/build_lua.sh --if-missing
	scripts/build_cmark.sh --if-missing
	;;
esac
echo "Dependencies ready"
