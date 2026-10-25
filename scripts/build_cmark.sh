#!/usr/bin/env bash
# Builds cmark (CommonMark) as a static library for the editor's markdown view
# (editor/lib/cmark; TODO D.4: no libcmark with the editor):
#   macOS    editor/lib/cmark/lib/libcmark_darwin.a       universal (in the repo)
#   Linux    editor/lib/cmark/lib/libcmark_linux_x64.a    (CI builds it)
#   Windows  editor/lib/cmark/lib/cmark_windows_x64.lib   (MSVC, static CRT; CI)
#   scripts/build_cmark.sh [--if-missing]
# Needs git, cmake and a C compiler (Windows: MSVC's environment).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=0.31.1
case "$(uname -s)" in
	Darwin) out=editor/lib/cmark/lib/libcmark_darwin.a ;;
	Linux) out=editor/lib/cmark/lib/libcmark_linux_x64.a ;;
	MINGW*|MSYS*|CYGWIN*) out=editor/lib/cmark/lib/cmark_windows_x64.lib ;;
	*) echo "Unknown platform $(uname -s)" >&2; exit 1 ;;
esac
if [ "${1:-}" = --if-missing ] && [ -f "$out" ]; then
	echo "$out exists"
	exit 0
fi
tmp=$(mktemp -d)
git clone -q --depth 1 --branch "$VERSION" https://github.com/commonmark/cmark.git "$tmp/cmark"
flags=(-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON)
case "$(uname -s)" in
	Darwin) flags+=("-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0) ;;
	MINGW*|MSYS*|CYGWIN*) flags+=(-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded) ;;
esac
cmake -S "$tmp/cmark" -B "$tmp/build" "${flags[@]}" > /dev/null
cmake --build "$tmp/build" --config Release > /dev/null
lib=$(find "$tmp/build" \( -name 'libcmark.a' -o -name 'cmark.lib' \) | head -1)
mkdir -p "$(dirname "$out")"
cp "$lib" "$out"
echo "Built $out (cmark $VERSION)"
