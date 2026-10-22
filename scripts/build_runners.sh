#!/usr/bin/env bash
# Builds the standalone game runner for this platform (release) into
# bin/runners/<platform>/, with the UI font in bin/runners/. The editor's
# Export Standalone Game copies it next to the game's .ore - no compiler
# needed when exporting. Run it on each platform you ship for and copy the
# runners/<platform>/ folders next to the editor (or into bin/runners/).
#   scripts/build_runners.sh            # release (-o:speed)
#   scripts/build_runners.sh -debug     # extra odin flags
set -euo pipefail
cd "$(dirname "$0")/.."
case "$(uname -s)" in
	Darwin) platform=macos; exe=runner ;;
	Linux) platform=linux; exe=runner ;;
	MINGW*|MSYS*|CYGWIN*) platform=windows; exe=runner.exe ;;
	*) echo "Unknown platform $(uname -s)" >&2; exit 1 ;;
esac
out="bin/runners/$platform"
mkdir -p "$out"
odin build runner -o:speed -out:"$out/$exe" "$@"
cp engine/Open_Sans/static/OpenSans-Regular.ttf bin/runners/
echo "Built $out/$exe"
