#!/usr/bin/env bash
# Runs a project folder in the web runner (headless Chrome) and screenshots
# it - the web side of render tests (e.g. tests/vector: Phase 14's vector
# art on WebGL 2):
#   scripts/web/test_project.sh <project-dir> <out.png> [seconds] [scene]
# Packs the project (scripts/pack_rayzr.odin), lays out a web export (the
# runner's files + game.rayzr + the font, like the editor's Web export),
# serves it on localhost and captures it (scripts/web/capture.mjs: console
# errors fail the run). Needs bin/runners/web (scripts/build_web_runner.sh).
set -euo pipefail
cd "$(dirname "$0")/../.."
proj="$1"; out="$2"; secs="${3:-8}"; scene="${4:-}"
[ -f bin/runners/web/index.wasm ] || { echo "no web runner: scripts/build_web_runner.sh" >&2; exit 2; }
dir="$(mktemp -d /tmp/rayzr_web_test.XXXXXX)"
trap 'kill $server 2>/dev/null || true; rm -rf "$dir"' EXIT
src="$proj"
if [ -n "$scene" ]; then
	# (Start in another scene: a copy with its initial_scene changed.)
	src="$dir/project"; cp -R "$proj" "$src"
	python3 -I - "$src/project.json" "$scene" <<'PY'
import json, sys
p = sys.argv[1]; cfg = json.load(open(p)); cfg["initial_scene"] = sys.argv[2]; json.dump(cfg, open(p, "w"))
PY
fi
odin run scripts/pack_rayzr.odin -file -- "$src" "$dir/game.rayzr" > /dev/null
cp bin/runners/web/index.html bin/runners/web/index.js bin/runners/web/index.wasm bin/runners/web/odin.js "$dir/"
if [ -f bin/runners/web/fonts/OpenSans-Regular.ttf ]; then mkdir -p "$dir/fonts"; cp bin/runners/web/fonts/*.ttf "$dir/fonts/"; fi
port=$((20000 + RANDOM % 20000))
(cd "$dir" && python3 -m http.server "$port" --bind 127.0.0.1 > /dev/null 2>&1) & server=$!
sleep 1
node scripts/web/capture.mjs "http://127.0.0.1:$port/index.html?autostart" "$out" "$secs"
