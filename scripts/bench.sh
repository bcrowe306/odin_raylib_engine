#!/usr/bin/env bash
# Runs the performance benchmarks and prints their [bench] lines:
#   - engine (no window): node create/destroy, transforms, scene JSON,
#     particles, Lua scripts (engine/perf_bench_test.odin)
#   - rendering (a window, uncapped frames): the runner's --bench on the
#     scenes of scripts/make_bench_project.py, with and without the render
#     caches (--no-render-cache)
# Baselines are recorded in engine/GAPS.md ("Performance baselines").
# macOS: needs an awake display for the rendering part.
set -uo pipefail
cd "$(dirname "$0")/.."
echo "== engine"
odin build engine -build-mode:test -o:speed -define:ODIN_TEST_THREADS=1 \
	-define:ODIN_TEST_NAMES=engine.bench_scene_hot_paths,engine.bench_particles,engine.bench_scripts \
	-out:/tmp/ore_bench_engine > /dev/null || exit 1
/tmp/ore_bench_engine 2>&1 | grep '\[bench\]' | sed 's/^.*\[bench\]/[bench]/'

echo "== rendering"
odin build runner -o:speed -out:/tmp/ore_bench_runner || exit 1
python3 scripts/make_bench_project.py /tmp/ore_bench > /dev/null
for s in bench_sprites bench_sprites_overlap bench_tiles bench_particles bench_particles_circles main; do
	for flag in "" --no-render-cache; do
		command -v caffeinate > /dev/null && caffeinate -u -t 2
		line=$(perl -e 'alarm 120; exec @ARGV' /tmp/ore_bench_runner /tmp/ore_bench --scene "scenes/$s.scene.json" --bench 300 $flag 2>&1 | grep '\[bench\]')
		printf '%-24s %-18s %s\n' "$s" "${flag:-cached}" "${line#*frames: }"
	done
done
