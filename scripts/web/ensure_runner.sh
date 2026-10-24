#!/usr/bin/env bash
# The web runner, built once (test drives; scripts/build_web_runner.sh).
cd "$(dirname "$0")/../.."
[ -f bin/runners/web/index.wasm ] || scripts/build_web_runner.sh
