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

// #154: a type built on another ("inherits"): the parent's base, defaults
// and script unless it gives its own; its nodes are of both types; a change
// to the parent reaches it.
@(test)
test_custom_node_inherits :: proc(t: ^testing.T) {
	game, scene := cn_setup("inherits")
	defer cn_teardown(game)
	ctx := &game.gameContext
	ScriptVFS_RegisterEmbedded("scripts/cn_boss.lua", `
local Boss = {}
Boss.extends = "scripts/cn_hurtbox.lua"
Boss.properties = { enrage = { type = "float", default = 4 } }
return Boss
`)
	cn_write("nodes/BossHurtbox.node.json", CustomNode_DefinitionJSON({name = "BossHurtbox", inherits = "nodes/Hurtbox.node.json", script = "scripts/cn_boss.lua", defaults = `{"layer": 2}`}, context.temp_allocator))
	cn_write("nodes/Loop1.node.json", `{"name": "Loop1", "inherits": "nodes/Loop2.node.json"}`)
	cn_write("nodes/Loop2.node.json", `{"name": "Loop2", "inherits": "nodes/Loop1.node.json"}`)
	boss := CustomNode_FindByName(ctx, "BossHurtbox")
	if !testing.expect(t, boss != nil, "loaded") do return
	testing.expect_value(t, boss.base, "AreaNode")
	_, loopProblem := CustomNode_Get(ctx, "nodes/Loop1.node.json")
	testing.expectf(t, loopProblem != "", "a loop isn't loaded: %s", loopProblem)

	n := Scene_CreateCustomNode(scene, boss, nil, ctx)
	ProcessNodeQueues(scene.manager, ctx)
	if !testing.expect(t, n != nil, "created") do return
	n.name = "Boss1"
	testing.expect(t, (cast(^AreaNode)n).shapes[0].size == {32, 32}, "the parent's shape")
	testing.expect_value(t, n.layer, RenderLayer(2))
	inst := cast(^ScriptInstance)n.scriptInstance
	testing.expect(t, inst != nil && inst.modulePath == "scripts/cn_boss.lua", "its own script")
	mh, _ := ScriptInstance_GetProperty(inst, "max_health")
	en, _ := ScriptInstance_GetProperty(inst, "enrage")
	testing.expect_value(t, mh.valFloat, 5) // the parent type's value
	testing.expect_value(t, en.valFloat, 4)
	testing.expect(t, Node_Is(n, "BossHurtbox") && Node_Is(n, "Hurtbox") && Node_Is(n, "AreaNode"), "both types")
	testing.expect_value(t, Node_ClassName(n), "BossHurtbox")

	// The parent changes: the child type's node follows.
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	bt := node_text(saved, "Boss1")
	testing.expectf(t, !strings.contains(bt, "shapes") && !strings.contains(bt, "layer") && !strings.contains(bt, "script"), "nothing of its own: %s", bt)
	changed, _ := strings.replace(HURTBOX_DEF, "[32, 32]", "[12, 12]", 1, context.temp_allocator)
	cn_write("nodes/Hurtbox.node.json", changed)
	CustomNodes_Forget()
	again := game->createScene("inherits2", false)
	_ = Scene_InstantiateFromJSON(again, transmute([]u8)saved, ctx)
	ProcessNodeQueues(again.manager, ctx)
	rb := cn_find(again, "Boss1")
	if !testing.expect(t, rb != nil, "reloaded") do return
	testing.expect_value(t, (cast(^AreaNode)rb).shapes[0].size, [2]f32{12, 12})
}

// #154: Save as Custom Node - a configured node's values as a type's
// defaults, and the definition file.
@(test)
test_custom_node_from_node :: proc(t: ^testing.T) {
	game, scene := cn_setup("from_node")
	defer cn_teardown(game)
	ctx := &game.gameContext
	n := cast(^AreaNode)Node_CreateByTypeName(scene, "AreaNode")
	n.gameContext = ctx
	AreaNode_AddShape(n, MakeBoxPhysicsShape(24, 24), ctx)
	n.layer = RenderLayer(3)
	n.position = {500, 500}
	Script_AttachToNode(n, "scripts/cn_hurtbox.lua", nil, &game.scriptManager)
	ProcessNodeQueues(scene.manager, ctx)
	ScriptInstance_SetProperty(cast(^ScriptInstance)n.scriptInstance, "armor", ScriptValue{type = .Float, valFloat = 2})

	defaults := CustomNode_DefaultsFromNode(n, scene.manager, context.temp_allocator)
	testing.expectf(t, strings.contains(defaults, `"shapes"`) && strings.contains(defaults, `"layer": 3`), "its values: %s", defaults)
	testing.expectf(t, strings.contains(defaults, `"armor": 2`) && !strings.contains(defaults, "max_health"), "only the script values it changed: %s", defaults)
	testing.expectf(t, !strings.contains(defaults, "position") && !strings.contains(defaults, `"path"`), "not its place or script file: %s", defaults)

	text := CustomNode_DefinitionJSON({name = "Guard", base = "AreaNode", script = "scripts/cn_hurtbox.lua", category = "Combat", defaults = defaults}, context.temp_allocator)
	def, problem := CustomNode_Parse("nodes/Guard.node.json", text)
	if !testing.expectf(t, def != nil, "a valid file: %s\n%s", problem, text) do return
	testing.expect_value(t, def.category, "Combat")
	cn_write("nodes/Guard.node.json", text)
	CustomNodes_Forget()
	g := CustomNode_FindByName(ctx, "Guard")
	made := Scene_CreateCustomNode(scene, g, nil, ctx)
	ProcessNodeQueues(scene.manager, ctx)
	testing.expect(t, made != nil && made.layer == RenderLayer(3) && (cast(^AreaNode)made).shapes[0].size == {24, 24}, "a new one: the node's values")
	a, _ := ScriptInstance_GetProperty(cast(^ScriptInstance)made.scriptInstance, "armor")
	testing.expect_value(t, a.valFloat, 2)
}

// #155: a type's file changing (edited, undone) after its nodes were built:
// they don't pin the old values when saved, and a refresh gives them the
// new ones - except what each node changed.
@(test)
test_custom_node_type_changes_under_nodes :: proc(t: ^testing.T) {
	game, scene := cn_setup("changes")
	defer cn_teardown(game)
	ctx := &game.gameContext
	h := CustomNode_FindByName(ctx, "Hurtbox")
	a := Scene_CreateCustomNode(scene, h, nil, ctx)
	b := Scene_CreateCustomNode(scene, h, nil, ctx)
	ProcessNodeQueues(scene.manager, ctx)
	a.name, b.name = "Plain", "Own"
	(cast(^AreaNode)b).shapes[0].size = {70, 70}

	// The file changes (the registry forgets: read again).
	changed, _ := strings.replace(HURTBOX_DEF, "[32, 32]", "[48, 48]", 1, context.temp_allocator)
	changed, _ = strings.replace(changed, `"max_health": 5`, `"max_health": 8`, 1, context.temp_allocator)
	cn_write("nodes/Hurtbox.node.json", changed)
	CustomNodes_Forget()
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	pt := node_text(saved, "Plain")
	testing.expectf(t, !strings.contains(pt, "shapes") && !strings.contains(pt, "script"), "the old values aren't pinned: %s", pt)

	// Refreshed: the new values, B's own shape kept.
	n := Scene_RefreshCustomNodes(scene, "nodes/Hurtbox.node.json", ctx)
	testing.expect_value(t, n, 2)
	ra, rb := cn_find(scene, "Plain"), cn_find(scene, "Own")
	if !testing.expect(t, ra != nil && rb != nil, "rebuilt") do return
	testing.expect_value(t, (cast(^AreaNode)ra).shapes[0].size, [2]f32{48, 48})
	testing.expect_value(t, (cast(^AreaNode)rb).shapes[0].size, [2]f32{70, 70})
	mh, _ := ScriptInstance_GetProperty(cast(^ScriptInstance)ra.scriptInstance, "max_health")
	testing.expect_value(t, mh.valFloat, 8)

	// A type's document: the defaults relative to its parent type.
	cn_write("nodes/Boss.node.json", `{"name": "Boss", "inherits": "nodes/Hurtbox.node.json", "defaults": {"layer": 4}}`)
	CustomNodes_Forget()
	boss := CustomNode_FindByName(ctx, "Boss")
	bn := Scene_CreateCustomNode(scene, boss, nil, ctx)
	ProcessNodeQueues(scene.manager, ctx)
	bn.renderable = false
	parent, _ := CustomNode_Get(ctx, boss.inherits)
	d := CustomNode_DefaultsFromNode(bn, scene.manager, context.temp_allocator, parent)
	testing.expectf(t, strings.contains(d, `"layer": 4`) && strings.contains(d, `"visible": false`), "its own values: %s", d)
	testing.expectf(t, !strings.contains(d, "shapes") && !strings.contains(d, "max_health"), "not the parent's: %s", d)
}

// #155: a type's base changed - its values for the new base, and what
// doesn't carry over.
@(test)
test_custom_node_rebase :: proc(t: ^testing.T) {
	game, _ := cn_setup("rebase")
	defer cn_teardown(game)
	ctx := &game.gameContext
	cn_write("nodes/Glow.node.json", `{"name": "Glow", "base": "AreaNode", "defaults": {"layer": 2, "shapes": [{"type": "Box", "size": [20, 20]}]}}`)
	glow := CustomNode_FindByName(ctx, "Glow")
	if !testing.expect(t, glow != nil, "type") do return
	defaults, dropped := CustomNode_Rebase(glow, "StaticBodyNode", ctx, context.temp_allocator)
	testing.expectf(t, strings.contains(defaults, `"shapes"`) && strings.contains(defaults, `"layer": 2`), "a body keeps the shape and the layer: %s", defaults)
	defaults, dropped = CustomNode_Rebase(glow, "TimerNode", ctx, context.temp_allocator)
	testing.expectf(t, !strings.contains(defaults, "shapes") && strings.contains(defaults, `"layer": 2`), "a timer: the layer only: %s", defaults)
	found := false
	for d in dropped do if d == "shapes" do found = true
	testing.expectf(t, found, "the shapes are dropped: %v", dropped)
}
