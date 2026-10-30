package engine

import os "osx"
import "core:strings"
import "core:testing"

// #157: LDtk entities as custom node types - a mapping to a type, and Auto
// matching a type by the entity's name (opt in: matchCustomNodes).
@(test)
test_ldtk_entities_as_custom_nodes :: proc(t: ^testing.T) {
	DIR :: "test_ldtk_custom_nodes"
	_ = os.make_directory_all(DIR + "/nodes")
	defer os.remove_all(DIR)
	_ = os.write_entire_file(DIR + "/game.ldtk", transmute([]u8)string(LDTK_WORLDS_PROJECT))
	ScriptVFS_RegisterEmbedded("ldtk_cn_door.lua", `
local D = {}
D.properties = { lockedWith = { type = "string", default = "" }, hp = { type = "float", default = 1 } }
return D
`)
	_ = os.write_entire_file(DIR + "/nodes/DoorType.node.json", transmute([]u8)string(`{"name": "DoorType", "base": "AreaNode", "script": "ldtk_cn_door.lua", "defaults": {"script": {"properties": {"hp": 3}}}}`))
	_ = os.write_entire_file(DIR + "/nodes/Player.node.json", transmute([]u8)string(`{"name": "Player", "base": "TimerNode"}`))
	CustomNodes_Forget()
	defer CustomNodes_Forget()

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, DIR)
	ctx := &game.gameContext
	scene := game->createScene("ldtk_custom", true)
	ProcessSceneChange(&game.sceneManager, ctx)
	game.state = .Running

	build :: proc(scene: ^Scene, ctx: ^GameContext, match: bool) -> ^LdtkLevelNode {
		ln := cast(^LdtkLevelNode)Node_CreateByTypeName(scene, "LdtkLevelNode")
		ln.gameContext = ctx
		ln.worldIdentifier = "Overworld"
		ln.matchCustomNodes = match
		LdtkLevelNode_SetEntityMapping(ln, {entity = "Door", mode = .CustomNode, nodeType = "nodes/DoorType.node.json"})
		LdtkLevelNode_SetProject(ln, DIR + "/game.ldtk", "A")
		return ln
	}

	// A mapping to a type; Auto without matching: a plain node.
	ln := build(scene, ctx, false)
	game->run(0.016)
	d1 := ln.spawnedByIid["d1"]
	if !testing.expect(t, d1 != nil, "the door spawned") do return
	testing.expect_value(t, Node_ClassName(d1), "DoorType")
	testing.expect(t, d1.typeId == AreaNode, "its base type")
	inst := cast(^ScriptInstance)d1.scriptInstance
	if testing.expect(t, inst != nil, "its script") {
		testing.expect_value(t, inst.properties["lockedWith"].valString, "Key") // (the LDtk field)
		testing.expect_value(t, inst.properties["hp"].valFloat, 3)              // (the type's value)
	}
	p1 := ln.spawnedByIid["p1"]
	testing.expect(t, p1 != nil && p1.typeId == Node && p1.customType == "", "Auto, not matching: a plain Node")

	// Saved and loaded: the mapping and the setting.
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(saved, `"mode": "custom_node", "node_type": "nodes/DoorType.node.json"`), "the mapping saved: %s", saved)

	// Matching by name: the Player type.
	ln2 := build(scene, ctx, true)
	game->run(0.016)
	p2 := ln2.spawnedByIid["p1"]
	testing.expect(t, p2 != nil && Node_ClassName(p2) == "Player" && p2.typeId == TimerNode, "Auto with matching: the Player type")
	b2 := ln2.spawnedByIid["b1"]
	testing.expect(t, b2 != nil && b2.customType == "", "no type of that name: as before")
	saved = Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(saved, `"matchCustomNodes": true`), "the setting saved")
}
