package engine

import "core:strings"
import "core:testing"
import lua "lua54"
import uilib "../ui"

// #227: UI nodes' lists can be set - from Lua (ui_set_items / set_property),
// saved and loaded - and a Text Input's text too.
@(test)
test_ui_list_content :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("ui227", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	mk :: proc(scene: ^Scene, type, name: string) -> ^Node {
		n := Node_CreateByTypeName(scene, type)
		n.name = strings.clone(name, n.allocator)
		return n
	}
	dd := cast(^UIDropdownNode)mk(scene, "UIDropdownNode", "Dd")
	tree := cast(^UITreeViewNode)mk(scene, "UITreeViewNode", "Tree")
	tbl := cast(^UITableNode)mk(scene, "UITableNode", "Tbl")
	tb := cast(^UIToolbarNode)mk(scene, "UIToolbarNode", "Tb")
	plot := cast(^UIXYPlotNode)mk(scene, "UIXYPlotNode", "Plot")
	ol := cast(^UIOrderedListNode)mk(scene, "UIOrderedListNode", "Ol")
	ti := cast(^UITextInputNode)mk(scene, "UITextInputNode", "Ti")
	ProcessNodeQueues(scene.manager, &game.gameContext)

	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local f = Scene.find_node
f("Dd"):ui_set_items({"Easy", "Normal", "Hard"})
f("Tree"):ui_set_items({"Root", "  Child", "    Leaf", "  Child 2", "Other"})
f("Tbl"):set_property("columns", {"Name", "Score|80"})
f("Tbl"):ui_set_items({"Ada|10", "Bo|7"})
f("Tb"):ui_set_items({"Save|Save|Save the game", "-", "toggle:|Grid", "~"})
f("Plot"):ui_set_items({Vec2(0, 1), {2, 3}, "4, 5"})
f("Ol"):ui_set_items({"One", "  Sub"})
f("Ti"):set_text("hello")
dd_items = f("Dd"):ui_get_items()
ti_text = f("Ti"):get_text()
`) == 0
	if !ok do testing.expectf(t, false, "Lua: %s", lua.tostring(L, -1))

	testing.expect(t, len(dd.items) == 3 && dd.items[2] == "Hard", "dropdown items")
	lua.getglobal(L, "dd_items")
	testing.expect(t, lua.rawlen(L, -1) == 3, "ui_get_items")
	lua.pop(L, 1)
	testing.expect_value(t, len(tree.items), 5)
	if len(tree.items) == 5 {
		testing.expect(t, tree.items[1].depth == 1 && tree.items[2].depth == 2 && tree.items[4].depth == 0, "tree depths")
		testing.expect(t, tree.items[0].hasChildren && !tree.items[2].hasChildren && tree.items[1].hasChildren, "parents")
		testing.expect(t, !tree.items[1].isLastChild && tree.items[3].isLastChild, "last children")
	}
	testing.expect(t, len(tbl.columns) == 2 && tbl.columns[1].title == "Score" && tbl.columns[1].width == 80, "table columns")
	testing.expect(t, len(tbl.rows) == 2 && len(tbl.rows[1].cells) == 2 && tbl.rows[1].cells[0].text == "Bo", "table rows")
	testing.expect_value(t, len(tb.items), 4)
	if len(tb.items) == 4 {
		testing.expect(t, tb.items[0].icon == .Save && tb.items[0].label == "Save" && tb.items[0].tooltip == "Save the game", "toolbar button")
		testing.expect(t, tb.items[1].itemType == .Separator && tb.items[2].itemType == .Toggle && tb.items[3].itemType == .Spacer, "toolbar kinds")
	}
	testing.expect(t, len(plot.points) == 3 && plot.points[2] == {4, 5} && plot.points[0] == {0, 1}, "plot points")
	testing.expect(t, len(ol.items) == 2 && ol.items[1].depth == 1, "ordered list")
	lua.getglobal(L, "ti_text")
	testing.expect_value(t, string(lua.tostring(L, -1)), "hello")
	lua.pop(L, 1)
	testing.expect_value(t, ti.text, "hello")

	// Saved and loaded.
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"items": ["Easy", "Normal", "Hard"]`), "dropdown saved")
	testing.expect(t, strings.contains(text, `"rows": ["Ada|10", "Bo|7"]`), "table rows saved")
	testing.expect(t, strings.contains(text, `"text": "hello"`), "text input saved")
	s2 := game->createScene("ui227b", false)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)
	tree2 := cast(^UITreeViewNode)Scene_FindNodeByName(s2, "Tree")
	tb2 := cast(^UIToolbarNode)Scene_FindNodeByName(s2, "Tb")
	ti2 := cast(^UITextInputNode)Scene_FindNodeByName(s2, "Ti")
	testing.expect(t, tree2 != nil && len(tree2.items) == 5 && tree2.items[2].label == "Leaf" && tree2.items[2].depth == 2, "tree loaded")
	testing.expect(t, tb2 != nil && len(tb2.items) == 4 && tb2.items[0].icon == uilib.Icon.Save, "toolbar loaded")
	testing.expect(t, ti2 != nil && UITextInputNode_GetText(ti2) == "hello", "text input loaded into its buffer")
}
