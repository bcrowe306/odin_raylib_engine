package engine

import "core:testing"

// #229: Toggle Switch / List View / Tab Container signals; List View
// scrolls; Table sorts; Tab Container shows only the active page; XY Plot
// auto scale; Tree View hides a collapsed parent's children; the meter
// holds its clip light; a knob resets on right-click.
@(test)
test_ui_signals_settings :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	game.uiTestInputEnabled = true
	scene := game->createScene("ui229", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	layer := ScreenLayerNode_Create(scene, "HUD")
	count :: proc(source: rawptr, val: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}
	click :: proc(game: ^Game, at: [2]f32, right := false) {
		game.uiTestMousePos = at
		if right do game.uiTestRightPressed = true
		else do game.uiTestMousePressed, game.uiTestMouseDown = true, true
		game->run(0.016)
		game.uiTestMousePressed, game.uiTestMouseDown, game.uiTestRightPressed = false, false, false
		game->run(0.016)
	}
	center :: proc(e: ^UIElement) -> [2]f32 {
		r := UI_GetElementRect(e)
		return {r.x + r.width * 0.5, r.y + r.height * 0.5}
	}

	ts := UIToggleSwitchNode_Create(scene, "Ts", parent = layer)
	ts.position = {20, 20}
	toggled := 0
	ts.onChanged->subscribe(count, &toggled)
	items := [?]string{"a", "b", "c", "d", "e", "f", "g", "h", "i", "j"}
	lv := UIListViewNode_Create(scene, "Lv", items[:], {200, 72}, layer) // (3 rows of 24)
	lv.position = {20, 80}
	picked := 0
	lv.onSelected->subscribe(count, &picked)
	knob := UIKnobNode_Create(scene, "Knob", value = 80, defaultValue = 50, parent = layer)
	knob.position = {300, 20}
	game->run(0.016)

	click(game, center(&ts.ui))
	testing.expect(t, ts.active && toggled == 1, "the toggle raises value_changed")
	r := UI_GetElementRect(&lv.ui)
	click(game, {r.x + 20, r.y + 30}) // (the second row)
	testing.expect(t, lv.selectedIndex == 1 && picked == 1, "the list raises selected")
	game.uiTestMousePos = {r.x + 20, r.y + 30}
	game.uiTestWheel = -1
	game->run(0.016)
	game.uiTestWheel = 0
	testing.expectf(t, lv.scroll.y == 24, "the wheel scrolls a row (%v)", lv.scroll.y)
	click(game, center(&knob.ui), right = true)
	testing.expect_value(t, knob.value, 50)

	// Table: sorted by a column, numbers as numbers, the selection kept.
	tbl := UITableNode_Create(scene, "Tbl", parent = layer)
	Property_SetList(tbl, Node_FindProperty(tbl, "columns") or_else {}, {"Name", "Score"})
	Property_SetList(tbl, Node_FindProperty(tbl, "rows") or_else {}, {"Ada|10", "Bo|9", "Cy|100"})
	tbl.selectedRow = 0 // Ada
	tbl.sortColumn, tbl.sortAscending = 1, true
	UITableNode_SortRows(tbl)
	testing.expect(t, tbl.rows[0].cells[0].text == "Bo" && tbl.rows[2].cells[0].text == "Cy", "sorted by score")
	testing.expect_value(t, tbl.selectedRow, 1) // (Ada, now second)

	// Tab Container: only the active page shows; tab_changed.
	names := [?]string{"One", "Two"}
	tc := UITabContainerNode_Create(scene, "Tabs", names[:], parent = layer)
	p1 := UIVerticalContainerNode_Create(scene, "P1", parent = tc)
	p2 := UIVerticalContainerNode_Create(scene, "P2", parent = tc)
	changed := 0
	tc.onTabChanged->subscribe(count, &changed)
	game->run(0.016)
	testing.expect(t, p1.enabled && !p2.enabled, "the first page shows")
	tc.activeTab = 1
	game->run(0.016)
	testing.expect(t, !p1.enabled && p2.enabled && changed == 1, "the second page, and tab_changed")

	// XY Plot: fitted to its points.
	plot := UIXYPlotNode_Create(scene, "Plot", parent = layer)
	UIXYPlotNode_AddPoint(plot, 10, 100)
	UIXYPlotNode_AddPoint(plot, 20, 300)
	plot.autoScaleX, plot.autoScaleY = true, true
	x0, x1, y0, y1 := UIXYPlotNode_Range(plot)
	testing.expectf(t, x0 < 10 && x0 > 9 && x1 > 20 && x1 < 21 && y0 < 100 && y1 > 300, "fitted: %v %v %v %v", x0, x1, y0, y1)

	// Tree View: Down skips a collapsed parent's children.
	tree := UITreeViewNode_Create(scene, "Tree", parent = layer)
	Property_SetList(tree, Node_FindProperty(tree, "items") or_else {}, {"Root", "  Hidden", "Next"})
	tree.items[0].isCollapsed = true
	tree.selectedId = 1
	game->run(0.016) // (in the scene's node list)
	UI_SetFocus(scene, &tree.ui)
	game->run(0.016)
	testing.expect(t, tree.focused, "the tree has the focus")
	game.uiTestKeyDown = true
	game->run(0.016)
	game.uiTestKeyDown = false
	testing.expect_value(t, tree.selectedId, 3)

	// Volume Meter: the clip light stays on after the level drops.
	meter := UIVolumeMeterNode_Create(scene, "Meter", parent = layer)
	meter.levelL = meter.maxDb
	game->run(0.016)
	meter.levelL = meter.minDb
	game->run(0.016)
	game->run(0.016)
	testing.expect(t, meter.state.clipL, "the clip light holds")
}
