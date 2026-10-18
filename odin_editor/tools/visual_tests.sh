#!/usr/bin/env bash
# Visual UI test suite (`task test:visual`): replays every tools/*.edctl
# script against a fresh editor_demo through the remote-control hook
# (real SDL input, live OLS), failing on any `expect`/`wait` that doesn't
# hold, and saves the screenshots each script takes into
# test_output/visual/<script>/ plus an index.md gallery. Run it after every
# feature and look at the screenshots.
set -uo pipefail
cd "$(dirname "$0")/.."

if [ ! -x third_party/ols/ols ]; then
	echo "visual tests: third_party/ols/ols not found -- run 'task ols:build'" >&2
	exit 2
fi

OUT="${VISUAL_DIR:-test_output/visual}"
mkdir -p "$OUT"

# script : fixture : one-line description (shown in the gallery)
SUITES=(
	"lsp_smoke:example/assets/lsp_fixture.odin.txt:Completion popup and signature help against live OLS"
	"lsp_crash:example/assets/lsp_fixture.odin.txt:OLS is killed mid-session; the editor keeps working and restarts it"
	"mouse_smoke:example/assets/mouse_fixture.odin.txt:Mouse and cursor gestures, scrolling, tab stops"
	"diagnostics_smoke:example/assets/diag_fixture.odin.txt:Diagnostics: squiggles, gutter markers, tooltips, F8"
)

failed=0
results=()
for entry in "${SUITES[@]}"; do
	IFS=: read -r name fixture desc <<<"$entry"
	if ./tools/run_smoke.sh "tools/$name.edctl" "$fixture"; then
		results+=("$name:PASS:$desc")
	else
		results+=("$name:FAIL:$desc")
		failed=1
	fi
done

# One labelled contact sheet per suite, for reviewing a run at a glance.
for entry in "${SUITES[@]}"; do
	IFS=: read -r name _ _ <<<"$entry"
	./tools/contact_sheet/contact_sheet "$OUT/$name" >/dev/null || true
done

INDEX="$OUT/index.md"
{
	echo "# odin_editor visual UI tests"
	echo
	echo "Generated $(date '+%Y-%m-%d %H:%M') from \`task test:visual\` on $(git rev-parse --short HEAD 2>/dev/null || echo '?')."
	echo "Each screenshot is the real demo window, driven by real SDL events through the control hook."
	for r in "${results[@]}"; do
		IFS=: read -r name status desc <<<"$r"
		echo
		echo "## $name — $status"
		echo
		echo "$desc (\`tools/$name.edctl\`)"
		if [ -e "$OUT/$name/contact_sheet.png" ]; then
			echo
			echo "![$name contact sheet]($name/contact_sheet.png)"
		fi
		for img in "$OUT/$name"/[0-9]*.png; do
			[ -e "$img" ] || continue
			file="$(basename "$img")"
			caption="$(echo "${file%.png}" | sed -E 's/^[0-9]+_//; s/_/ /g')"
			echo
			echo "**$caption**"
			echo
			echo "![$caption]($name/$file)"
		done
	done
} >"$INDEX"

shots=$(find "$OUT" -name '*.png' | wc -l | tr -d ' ')
echo "visual tests: $shots images, gallery: $INDEX (contact sheets: $OUT/*/contact_sheet.png)"
exit "$failed"
