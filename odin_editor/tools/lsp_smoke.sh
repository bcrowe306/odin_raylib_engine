#!/usr/bin/env bash
# Runs every remote-control smoke script (see tools/run_smoke.sh).
# `task test:remote` calls this after building the demo and edctl.
set -uo pipefail
cd "$(dirname "$0")/.."

if [ ! -x third_party/ols/ols ]; then
	echo "remote smoke: third_party/ols/ols not found -- run 'task ols:build'" >&2
	exit 2
fi

failed=0
./tools/run_smoke.sh tools/lsp_smoke.edctl example/assets/lsp_fixture.odin.txt || failed=1
./tools/run_smoke.sh tools/lsp_crash.edctl example/assets/lsp_fixture.odin.txt || failed=1
./tools/run_smoke.sh tools/mouse_smoke.edctl example/assets/mouse_fixture.odin.txt || failed=1
./tools/run_smoke.sh tools/diagnostics_smoke.edctl example/assets/diag_fixture.odin.txt || failed=1
exit "$failed"
