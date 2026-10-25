#!/usr/bin/env bash
# Builds the web runner: bin/runners/web/{index.html, index.js, index.wasm, odin.js}.
# The editor's Web export copies it next to the game's game.rayzr - exporting
# needs no compiler; only building the runner needs emscripten (emcc) and
# odin. Ship the editor with runners/web/ and web exports work anywhere.
#
#   scripts/build_web_runner.sh            (deps are built once into bin/web_deps)
#   scripts/build_web_runner.sh -define:RAYZR_RELEASE=1.2.3   (extra odin flags)
#
# Dependencies built with emcc: raylib 5.5 (WebGL 2), Lua 5.4.7, Box2D 3.1.1
# (the versions Odin's bindings expect). Sources: the official release
# tarballs.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
DEPS="$ROOT/bin/web_deps"
BUILD="$ROOT/bin/web_build"
OUT="${OUT:-$ROOT/bin/runners/web}"
ODIN_ROOT="$(odin root)"

command -v emcc >/dev/null || { echo "emcc not found: brew install emscripten (or source emsdk_env.sh)"; exit 1; }
mkdir -p "$DEPS" "$BUILD" "$OUT"

fetch() { # url dir
	[ -d "$DEPS/$2" ] && return
	echo "Downloading $1"
	curl -sL -o "$DEPS/$2.tgz" "$1"
	tar -xzf "$DEPS/$2.tgz" -C "$DEPS"
}
fetch https://github.com/raysan5/raylib/archive/refs/tags/5.5.tar.gz raylib-5.5
fetch https://www.lua.org/ftp/lua-5.4.7.tar.gz lua-5.4.7
fetch https://github.com/erincatto/box2d/archive/refs/tags/v3.1.1.tar.gz box2d-3.1.1

if [ ! -f "$DEPS/raylib-5.5/src/libraylib.a" ]; then
	echo "Building raylib (web)"
	make -C "$DEPS/raylib-5.5/src" PLATFORM=PLATFORM_WEB GRAPHICS=GRAPHICS_API_OPENGL_ES3 RAYLIB_LIBTYPE=STATIC -B -j8 >/dev/null
fi
if [ ! -f "$DEPS/lua-5.4.7/src/liblua.a" ]; then
	echo "Building Lua (web)"
	( cd "$DEPS/lua-5.4.7/src" && for f in *.c; do
		[ "$f" = lua.c ] || [ "$f" = luac.c ] || emcc -O2 -c "$f" -o "${f%.c}.o"; done && emar rcs liblua.a ./*.o )
fi
if [ ! -f "$DEPS/box2d-3.1.1/libbox2d.a" ]; then
	echo "Building Box2D (web)"
	( cd "$DEPS/box2d-3.1.1" && for f in src/*.c; do
		emcc -O2 -std=gnu17 -D_POSIX_C_SOURCE=199309L -Iinclude -Isrc -DNDEBUG -DBOX2D_DISABLE_SIMD -c "$f" -o "${f%.c}.o"; done && emar rcs libbox2d.a src/*.o )
fi

echo "Compiling the engine (js_wasm32)"
python3 scripts/web_prepare.py "$ROOT" "$BUILD/src" "$ODIN_ROOT" >/dev/null
odin build "$BUILD/src/runner/web" -target:js_wasm32 -build-mode:obj -define:RAYLIB_WASM_LIB=env.o -default-to-panic-allocator -o:speed -out:"$BUILD/game.wasm.o" "$@"

echo "Linking (emcc)"
cp "$ODIN_ROOT/core/sys/wasm/js/odin.js" "$OUT/odin.js"
emcc -o "$OUT/index.html" "$BUILD/game.wasm.o" \
	"$DEPS/raylib-5.5/src/libraylib.a" "$DEPS/lua-5.4.7/src/liblua.a" "$DEPS/box2d-3.1.1/libbox2d.a" \
	--shell-file scripts/web/shell.html \
	-O2 -sUSE_GLFW=3 -sUSE_ZLIB=1 -sWARN_ON_UNDEFINED_SYMBOLS=0 -sALLOW_MEMORY_GROWTH=1 \
	-sMIN_WEBGL_VERSION=2 -sMAX_WEBGL_VERSION=2 -sSTACK_SIZE=2MB \
	-sFORCE_FILESYSTEM=1 -lidbfs.js -sEXPORTED_RUNTIME_METHODS=FS,IDBFS,HEAPF32,HEAP8,HEAPU8,HEAP16,HEAPU16,HEAP32,HEAPU32 \
	-sEXPORTED_FUNCTIONS=_main_start,_main_update,_main_resize,_malloc,_free
echo "Web runner: $OUT"
ls -la "$OUT"
