#!/usr/bin/env bash
# Runs one remote-control smoke script against a fresh editor_demo:
#   tools/run_smoke.sh <script.edctl> <fixture> [extra demo flags...]
# The fixture is copied to a scratch main.odin (repo files are never
# edited), the demo is launched with the control hook in --control-only
# mode (real keyboard/mouse ignored, window never takes focus), the script
# is replayed with edctl, and the app is quit. Exit 0 = every check passed.
# Needs `task build build:edctl` (and `task ols:build` for LSP scripts).
set -euo pipefail
cd "$(dirname "$0")/.."

SCRIPT="$1"
FIXTURE="$2"
shift 2
PORT="${PORT:-7799}"
NAME="$(basename "$SCRIPT" .edctl)"

# No dots in the directory name: OLS derives the package path from it.
WORK="$(mktemp -d "/tmp/odin_editor_${NAME}_XXXXXX")"
cp "$FIXTURE" "$WORK/main.odin"

./example/editor_demo --control "$PORT" --control-only "$@" "$WORK/main.odin" >"$WORK/demo.log" 2>&1 &
APP=$!
trap 'kill "$APP" 2>/dev/null || true' EXIT

status=0
./tools/edctl/edctl --port "$PORT" --retry 15 -q <"$SCRIPT" || status=$?
./tools/edctl/edctl --port "$PORT" -q quit >/dev/null 2>&1 || true
wait "$APP" 2>/dev/null || true

if [ "$status" -eq 0 ]; then
	echo "$NAME: PASS"
else
	echo "$NAME: FAIL (app log: $WORK/demo.log)" >&2
fi
exit "$status"
