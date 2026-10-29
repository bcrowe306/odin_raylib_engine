package engine

import "core:fmt"
import os "osx"
import "core:strings"
import "core:testing"
import lua "lua54"

// #152: custom node types - definitions, linked defaults, the runtime and
// the Lua API.

@(private = "file")
CN_DIR :: "test_custom_nodes"

@(private = "file")
HURTBOX_DEF :: `{"name": "Hurtbox", "base": "AreaNode", "script": "scripts/cn_hurtbox.lua",
 "icon": "heart", "category": "Combat", "description": "Takes damage",
 "defaults": {"shapes": [{"type": "Box", "size": [32, 32], "isSensor": true, "enableSensorEvents": true}],
              "script": {"properties": {"max_health": 5}}}}`

@(private = "file")
cn_write :: proc(rel, text: string) {
	full := strings.concatenate({CN_DIR, "/", rel}, context.temp_allocator)
	_ = os.make_directory_all(full[:strings.last_index_byte(full, '/')])
	_ = os.write_entire_file(full, transmute([]u8)text)
}

@(private = "file")
cn_setup :: proc(name: string) -> (^Game, ^Scene) {
	ScriptVFS_RegisterEmbedded("scripts/cn_hurtbox.lua", `
local Hurtbox = {}
Hurtbox.properties = {
	max_health = { type = "float", default = 10 },
	armor = { type = "float", default = 0 },
}
function Hurtbox:ready() self.health = self.max_health end
function Hurtbox:take_damage(amount) self.health = self.health - amount end
return Hurtbox
`)
	CustomNodes_Forget()
	_ = os.make_directory_all(CN_DIR + "/nodes")
	cn_write("nodes/Hurtbox.node.json", HURTBOX_DEF)
	game := new(Game)
	InitializeGame(game)
	AssetManager_SetProjectDir(&game.assetManager, CN_DIR)
	scene := game->createScene(name, true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	return game, scene
}

@(private = "file")
cn_teardown :: proc(game: ^Game) {
	game->terminate()
	CustomNodes_Forget()
	os.remove_all(CN_DIR)
}

@(private = "file")
cn_find :: proc(scene: ^Scene, name: string) -> ^Node {
	return Scene_FindNodeByName(scene, name)
}

@(test)
test_custom_node_definitions :: proc(t: ^testing.T) {
	game, _ := cn_setup("defs")
	defer cn_teardown(game)
	cn_write("nodes/broken.node.json", `{"name": "Sprite", "base": "AreaNode"}`) // (a built-in's name)
	cn_write("more/Pickup.node.json", `{"name": "Pickup", "base": "AreaNode"}`)  // (any folder)
	ctx := &game.gameContext

	all := CustomNodes_All(ctx)
	names := make([dynamic]string, context.temp_allocator)
	for x in all do append(&names, x.name)
	testing.expect_value(t, strings.join(names[:], ",", context.temp_allocator), "Hurtbox,Pickup")
	_, problem := CustomNode_Get(ctx, "nodes/broken.node.json")
	testing.expectf(t, strings.contains(problem, "built-in"), "why it isn't loaded: %s", problem)
	h := CustomNode_FindByName(ctx, "Hurtbox")
	if !testing.expect(t, h != nil, "found by name") do return
	testing.expect_value(t, h.base, "AreaNode")
	testing.expect_value(t, h.category, "Combat")

	ok, why := CustomNode_IsValidName("2Fast")
	testing.expectf(t, !ok && why != "", "not an identifier: %s", why)
	ok, _ = CustomNode_IsValidName("Hurt_box2")
	testing.expect(t, ok, "an identifier")
}

@(test)
test_custom_node_create_and_linked_save :: proc(t: ^testing.T) {
	game, scene := cn_setup("linked")
	defer cn_teardown(game)
	ctx := &game.gameContext
	h := CustomNode_FindByName(ctx, "Hurtbox")
	if !testing.expect(t, h != nil, "type") do return

	// A new one: the base type, the type's shape and script values.
	a := Scene_CreateCustomNode(scene, h, nil, ctx)
	b := Scene_CreateCustomNode(scene, h, nil, ctx)
	ProcessNodeQueues(scene.manager, ctx)
	if !testing.expect(t, a != nil && b != nil, "created") do return
	a.name, b.name = "HurtA", "HurtB"
	testing.expect(t, a.typeId == AreaNode, "an Area")
	area := cast(^AreaNode)a
	testing.expect(t, len(area.shapes) == 1 && area.shapes[0].size == {32, 32}, "the type's box")
	testing.expect_value(t, Node_ClassName(a), "Hurtbox")
	testing.expect(t, Node_Is(a, "Hurtbox") && Node_Is(a, "AreaNode") && Node_Is(a, "Node") && !Node_Is(a, "Pickup"), "is")
	inst := cast(^ScriptInstance)a.scriptInstance
	if !testing.expect(t, inst != nil, "the script") do return
	v, _ := ScriptInstance_GetProperty(inst, "max_health")
	testing.expect_value(t, v.valFloat, 5) // the type's value, not the script's 10

	// B changes its shape and one script value.
	(cast(^AreaNode)b).shapes[0].size = {80, 40}
	ScriptInstance_SetProperty(cast(^ScriptInstance)b.scriptInstance, "armor", ScriptValue{type = .Float, valFloat = 3})
	b.position = {50, 60}
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	aText := node_text(saved, "HurtA")
	bText := node_text(saved, "HurtB")
	testing.expectf(t, strings.contains(aText, `"node_type": "nodes/Hurtbox.node.json"`) && strings.contains(aText, `"type": "AreaNode"`), "the link and the base: %s", aText)
	testing.expectf(t, !strings.contains(aText, "shapes") && !strings.contains(aText, "script"), "unchanged: only its own keys: %s", aText)
	testing.expectf(t, strings.contains(bText, "shapes") && strings.contains(bText, `"armor": 3`) && !strings.contains(bText, "max_health"), "only what B changed: %s", bText)

	// The type changes: A follows, B keeps its own shape and armor.
	changed, _ := strings.replace(HURTBOX_DEF, "[32, 32]", "[16, 16]", 1, context.temp_allocator)
	changed, _ = strings.replace(changed, `"max_health": 5`, `"max_health": 7`, 1, context.temp_allocator)
	cn_write("nodes/Hurtbox.node.json", changed)
	CustomNodes_Forget()
	again := game->createScene("linked2", false)
	testing.expect(t, Scene_InstantiateFromJSON(again, transmute([]u8)saved, ctx), "loads")
	ProcessNodeQueues(again.manager, ctx)
	ra, rb := cn_find(again, "HurtA"), cn_find(again, "HurtB")
	if !testing.expect(t, ra != nil && rb != nil, "reloaded") do return
	testing.expect_value(t, (cast(^AreaNode)ra).shapes[0].size, [2]f32{16, 16})
	testing.expect_value(t, (cast(^AreaNode)rb).shapes[0].size, [2]f32{80, 40})
	testing.expect_value(t, rb.position, [2]f32{50, 60})
	va, _ := ScriptInstance_GetProperty(cast(^ScriptInstance)ra.scriptInstance, "max_health")
	vb, _ := ScriptInstance_GetProperty(cast(^ScriptInstance)rb.scriptInstance, "armor")
	testing.expect_value(t, va.valFloat, 7)
	testing.expect_value(t, vb.valFloat, 3)
	testing.expect_value(t, Node_ClassName(rb), "Hurtbox")
}

// node_text: the JSON text of a scene's node by name (to the next node).
@(private = "file")
node_text :: proc(saved, name: string) -> string {
	i := strings.index(saved, fmt.tprintf(`"name": "%s"`, name))
	if i < 0 do return ""
	rest := saved[i:]
	end := strings.index(rest[1:], `"name": `)
	return rest if end < 0 else rest[:end + 1]
}

@(test)
test_custom_node_missing_type :: proc(t: ^testing.T) {
	game, scene := cn_setup("missing")
	defer cn_teardown(game)
	ctx := &game.gameContext
	text := `{"name": "missing", "root": {"type": "Node", "name": "Root", "children": [
		{"type": "AreaNode", "name": "Lost", "node_type": "nodes/Gone.node.json", "position": [5, 6], "layer": 3}]}}`
	testing.expect(t, Scene_InstantiateFromJSON(scene, transmute([]u8)text, ctx), "loads")
	ProcessNodeQueues(scene.manager, ctx)
	lost := cn_find(scene, "Lost")
	if !testing.expect(t, lost != nil, "kept") do return
	testing.expect(t, lost.typeId == AreaNode && lost.customMissing, "its base type, marked")
	testing.expect_value(t, Node_ClassName(lost), "AreaNode")
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	lt := node_text(saved, "Lost")
	testing.expectf(t, strings.contains(lt, `"node_type": "nodes/Gone.node.json"`) && strings.contains(lt, `"layer": 3`) && !strings.contains(lt, "shapes"), "saved back as loaded: %s", lt)
}

@(test)
test_custom_node_in_component :: proc(t: ^testing.T) {
	game, scene := cn_setup("component")
	defer cn_teardown(game)
	ctx := &game.gameContext
	cn_write("components/enemy.component.json", `{"type": "Node", "name": "Enemy", "uid": "en000000", "children": [
		{"type": "AreaNode", "name": "Hurtbox", "uid": "hb000000", "node_type": "nodes/Hurtbox.node.json", "position": [0, -8]}]}`)
	inst := Scene_InstantiateComponent(scene, "components/enemy.component.json", nil, ctx)
	ProcessNodeQueues(scene.manager, ctx)
	if !testing.expect(t, inst != nil, "instance") do return
	hb := cn_find(scene, "Hurtbox")
	if !testing.expect(t, hb != nil && hb.typeId == AreaNode, "the custom node inside") do return
	testing.expect_value(t, Node_ClassName(hb), "Hurtbox")
	testing.expect_value(t, len(Node_ComponentOverrides(scene.manager, hb)), 0) // (unchanged: no overrides)
	(cast(^AreaNode)hb).shapes[0].size = {64, 64}
	ov := Node_ComponentOverrides(scene.manager, hb)
	testing.expectf(t, len(ov) == 1 && ov[0] == "shapes", "one override: %v", ov)
}

@(test)
test_custom_node_lua :: proc(t: ^testing.T) {
	game, scene := cn_setup("lua")
	defer cn_teardown(game)
	ctx := &game.gameContext
	game.state = .Running
	h := CustomNode_FindByName(ctx, "Hurtbox")
	placed := Scene_CreateCustomNode(scene, h, nil, ctx)
	placed.name = "Placed"
	ProcessNodeQueues(scene.manager, ctx)
	L := game.scriptManager.L
	get :: proc(L: ^lua.State, expr: string) -> string {
		_ = lua.L_dostring(L, strings.clone_to_cstring(fmt.tprintf("return tostring(%s)", expr), context.temp_allocator))
		defer lua.pop(L, 1)
		return strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
	}
	_ = lua.L_dostring(L, `p = Scene.find_node("Placed")`)
	testing.expect_value(t, get(L, "p:get_type()"), "Hurtbox")
	testing.expect_value(t, get(L, "p:get_base_type()"), "AreaNode")
	testing.expect_value(t, get(L, `p:is("Hurtbox") and p:is("AreaNode") and p:is("Node") and not p:is("TimerNode")`), "true")
	_ = lua.L_dostring(L, `made = Scene.create("Hurtbox", nil, 30, 40)`)
	game->run(1.0 / 60)
	testing.expect_value(t, get(L, "made:get_type()"), "Hurtbox")
	testing.expect_value(t, get(L, "(made:get_position())"), "30.0")
	testing.expect_value(t, get(L, "made:get_script().max_health"), "5.0")
	testing.expect_value(t, get(L, "#Scene.find_nodes_of_type('Hurtbox')"), "2")
	testing.expect_value(t, get(L, `Scene.create("TimerNode"):get_type()`), "TimerNode")
	testing.expect_value(t, get(L, `Scene.create_node("Hurtbox", "Named"):get_type()`), "Hurtbox")
	testing.expect_value(t, get(L, `Scene.create("NoSuchType")`), "nil")
}
