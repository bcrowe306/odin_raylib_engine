#!/usr/bin/env bash
# Runs editor test-drives: each tests/drive/<name>.drive operates the editor
# through injected mouse/keyboard input against a fresh copy of the demo
# project (the real project is never modified).
#   scripts/editor_drive.sh                 # all drives
#   scripts/editor_drive.sh playtest nodes  # selected drives
# Screenshots + a report per drive: editor_screenshots/drive/<name>/index.md
set -uo pipefail
cd "$(dirname "$0")/.."

mkdir -p bin
# The Odin compiler very occasionally stalls; time out and retry.
build() {
	for attempt in 1 2 3; do
		perl -e 'alarm 90; exec @ARGV' odin build "$@" && return 0
		echo "odin build $* failed or stalled (attempt $attempt), retrying..." >&2
		pkill -f "odin build $1" 2>/dev/null
	done
	return 1
}
# EDITOR_DEFINES: extra build flags (e.g. -define:ORE_MEM_TRACK=true for leak reports).
# EDITOR_BIN: where to build the editor (a second run can use its own binary).
EDITOR_BIN="${EDITOR_BIN:-bin/editor}"
build editor -out:"$EDITOR_BIN" ${EDITOR_DEFINES:-} || exit 1
# SKIP_GAME_BUILD=1: keep bin/odin_raylib_engine (another run is using it).
[ -n "${SKIP_GAME_BUILD:-}" ] || build . -out:bin/odin_raylib_engine || exit 1

if [ $# -gt 0 ]; then
	drives=()
	for n in "$@"; do drives+=("tests/drive/$n.drive"); done
else
	drives=(tests/drive/*.drive)
fi

fail=0
summary=()
for d in "${drives[@]}"; do
	name="$(basename "$d" .drive)"
	tmp="$(mktemp -d /tmp/ore_drive_${name}.XXXXXX)"
	cp -R assets/demo_project "$tmp/project"
	# Scratch "new_scene*" scenes made while using the editor on the demo
	# project would shift the drives' expected default names: drop them
	# from the copy (the demo project itself is untouched).
	rm -f "$tmp/project"/scenes/new_scene*.scene.json
	python3 -I - "$tmp/project/project.json" <<-'EOF'
		import json, sys
		p = sys.argv[1]
		cfg = json.load(open(p))
		cfg["scenes"] = [s for s in cfg.get("scenes", []) if not s.startswith("scenes/new_scene")]
		if cfg.get("initial_scene", "").startswith("scenes/new_scene"):
		    cfg["initial_scene"] = "scenes/main.scene.json"
		# Settings drives toggle start from their defaults, whatever the demo
		# project has now.
		cfg.setdefault("physics", {})["debug_draw"] = True
		json.dump(cfg, open(p, "w"), indent=2)
	EOF
	shots="editor_screenshots/drive/$name"
	rm -rf "$shots"
	if perl -e 'alarm 600; exec @ARGV' "./$EDITOR_BIN" --project "$tmp/project" --drive "$d" --shots "$shots" --no-build > "$tmp/editor.log" 2>&1; then
		cp "$tmp/editor.log" "$shots/editor.log" 2>/dev/null # kept (memory reports, ...)
		summary+=("PASS  $name")
	else
		summary+=("FAIL  $name   (log: $tmp/editor.log)")
		fail=1
		grep "\[DRIVE\] FAIL" "$tmp/editor.log" | sed 's/^/      /'
	fi
done
printf '%s\n' "${summary[@]}"
exit $fail
