#!/usr/bin/env bash
# Rebuilds the Aseprite test files and what Aseprite makes of them (TODO E.3):
#   tests/aseprite/fixtures/<name>.aseprite        (make_fixtures.lua)
#   tests/aseprite/expected/<name>.json            (dump.lua: layers, cels, tags, slices, user data...)
#   tests/aseprite/expected/<name>_<frame>.png     (every frame rendered by Aseprite)
# The engine's tests (engine/aseprite_test.odin) compare against these - CI
# doesn't need Aseprite. Needs Aseprite (ASEPRITE=path, default: the macOS app).
set -euo pipefail
cd "$(dirname "$0")/.."
A="${ASEPRITE:-/Applications/Aseprite.app/Contents/MacOS/aseprite}"
[ -x "$A" ] || { echo "Aseprite not found: set ASEPRITE"; exit 1; }
rm -rf tests/aseprite/fixtures tests/aseprite/expected
mkdir -p tests/aseprite/fixtures tests/aseprite/expected
"$A" -b --script tests/aseprite/make_fixtures.lua
for f in tests/aseprite/fixtures/*.aseprite; do
	n=$(basename "$f" .aseprite)
	"$A" -b --script-param file="$f" --script-param out="tests/aseprite/expected/$n.json" --script tests/aseprite/dump.lua
	"$A" -b "$f" --color-mode rgb --save-as "tests/aseprite/expected/${n}_{frame}.png" # (RGBA, as the engine renders)
done
ls tests/aseprite/expected | wc -l

# Aseprite's own test sprites (the aseprite/ submodule): rendered here into
# build/aseprite_upstream/ (not committed - they're under Aseprite's EULA);
# engine/aseprite_test.odin compares them too when they're there.
if [ -d aseprite/tests/sprites ]; then
	up=build/aseprite_upstream
	rm -rf "$up"; mkdir -p "$up"
	for f in aseprite/tests/sprites/*.aseprite; do
		n=$(basename "$f" .aseprite)
		cp "$f" "$up/$n.aseprite"
		"$A" -b --script-param file="$f" --script-param out="$up/$n.json" --script tests/aseprite/dump.lua 2>/dev/null || true
		"$A" -b "$f" --color-mode rgb --save-as "$up/${n}_{frame}.png" 2>/dev/null || true
	done
	echo "upstream: $(ls $up/*.aseprite | wc -l) sprites in $up"
fi
