#!/usr/bin/env bash
# Launches editor_demo with the remote-control hook on a scratch copy of
# example/assets/lsp_fixture.odin.txt, runs tools/lsp_smoke.edctl against
# it with edctl, then quits the app. Exit status 0 = every check passed.
# Requires `task build`, `task build:edctl` and `task ols:build` first
# (`task test:remote` does all of that).
set -euo pipefail
cd "$(dirname "$0")/.."

PORT="${PORT:-7799}"
if [ ! -x third_party/ols/ols ]; then
	echo "lsp smoke: third_party/ols/ols not found -- run 'task ols:build'" >&2
	exit 2
fi

# No dots in the directory name: OLS derives the package path from it.
WORK="$(mktemp -d /tmp/odin_editor_smoke_XXXXXX)"
cp example/assets/lsp_fixture.odin.txt "$WORK/main.odin"

./example/editor_demo --control "$PORT" --control-only "$WORK/main.odin" >"$WORK/demo.log" 2>&1 &
APP=$!
trap 'kill "$APP" 2>/dev/null || true' EXIT

status=0
./tools/edctl/edctl --port "$PORT" --retry 15 -q <tools/lsp_smoke.edctl || status=$?
./tools/edctl/edctl --port "$PORT" -q quit >/dev/null 2>&1 || true
wait "$APP" 2>/dev/null || true

if [ "$status" -eq 0 ]; then
	echo "lsp smoke: PASS (screenshots: /tmp/odin_editor_smoke_*.png)"
else
	echo "lsp smoke: FAIL (app log: $WORK/demo.log)" >&2
fi
exit "$status"
