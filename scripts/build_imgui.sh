#!/usr/bin/env bash
# Builds Dear ImGui's static library for this platform into editor/lib/imgui/
# (imgui_<os>_<arch>.a / .lib), from the odin-imgui revision the editor's
# bindings (editor/lib/imgui/imgui.odin, ImGui v1.91.1-docking) were
# generated with. No ImGui backends: the editor has its own raylib one
# (editor/lib/imgui/imgui_impl_raylib). The repo has the macOS arm64 library;
# CI builds the others.
#   scripts/build_imgui.sh [--if-missing]
# Needs git, python3 (`ply` is installed in a private venv if missing), a C++ compiler (Windows:
# MSVC's environment, e.g. ilammy/msvc-dev-cmd in CI).
set -euo pipefail
cd "$(dirname "$0")/.."
REV=ea2d688 # odin-imgui (gitlab.com/L-4/odin-imgui): ImGui v1.91.1-docking, dear_bindings 139b5b

case "$(uname -s)" in
	Darwin) os=darwin; ext=a ;;
	Linux) os=linux; ext=a ;;
	MINGW*|MSYS*|CYGWIN*) os=windows; ext=lib ;;
	*) echo "Unknown platform $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
	x86_64|amd64) arch=x64 ;;
	arm64|aarch64) arch=arm64 ;;
	*) echo "Unknown architecture $(uname -m)" >&2; exit 1 ;;
esac
lib="imgui_${os}_${arch}.${ext}"
dst="editor/lib/imgui/$lib"
if [ "${1:-}" = --if-missing ] && [ -f "$dst" ]; then
	echo "$dst exists"
	exit 0
fi

work="${TMPDIR:-/tmp}/odin-imgui-$REV"
if [ ! -d "$work/.git" ]; then
	rm -rf "$work"
	git clone -q https://gitlab.com/L-4/odin-imgui.git "$work"
fi
git -C "$work" checkout -q -f "$REV"
# Only ImGui itself (no backends, no backend dependencies to fetch).
python3 - "$work/build.py" <<-'EOF'
	import re, sys
	p = sys.argv[1]
	s = open(p).read()
	s = re.sub(r'^wanted_backends = .*$', 'wanted_backends = []', s, count=1, flags=re.M)
	# Windows: MSVC's environment is already set (a Developer prompt, or
	# ilammy/msvc-dev-cmd in CI) - vcvarsall.bat isn't on PATH there.
	s = s.replace('f"vcvarsall.bat x64 && {', 'f"{')
	open(p, 'w').write(s)
EOF
# dear_bindings needs `ply`: a private virtual environment when it's missing.
py=python3
if ! python3 -c 'import ply' 2> /dev/null; then
	python3 -m venv "$work/.venv"
	py="$work/.venv/bin/python3"
	[ -x "$py" ] || py="$work/.venv/Scripts/python.exe" # (Windows)
	"$py" -m pip install -q ply
fi
(cd "$work" && "$py" build.py)
cp "$work/$lib" "$dst"
echo "Built $dst"
