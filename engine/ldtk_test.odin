package engine

import "core:os"
import "core:strings"
import "core:testing"
import b2 "vendor:box2d"
import lua "vendor:lua/5.4"

// Two worlds; Overworld has levels A (0,0) and B (64,0), side by side.
// A: Collisions 4x2 = [wall wall platform platform / water water 0 wall],
// a Ground tile tagged Water (tileset enum tags), a Button whose `targets`
// reference a Door in A and a Door in B, a Player.
LDTK_WORLDS_PROJECT :: `{
  "jsonVersion": "1.5.3", "iid": "proj", "worldLayout": null,
  "defs": {
    "layers": [
      {"uid": 1, "identifier": "Collisions", "__type": "IntGrid", "gridSize": 16, "parallaxFactorX": 0, "parallaxFactorY": 0,
       "intGridValues": [{"value": 1, "identifier": "wall", "color": "#FF0000"},
                         {"value": 2, "identifier": "platform", "color": "#00FF00"},
                         {"value": 3, "identifier": "water", "color": "#0000FF"}]},
      {"uid": 2, "identifier": "Far", "__type": "Tiles", "gridSize": 16, "parallaxFactorX": 0.5, "parallaxFactorY": 0.5, "parallaxScaling": true},
      {"uid": 3, "identifier": "Ground", "__type": "Tiles", "gridSize": 16}
    ],
    "entities": [
      {"uid": 10, "identifier": "Button", "color": "#FFAA00", "width": 16, "height": 16, "tags": ["interactive"],
       "fieldDefs": [{"identifier": "targets", "__type": "Array<EntityRef>"}]},
      {"uid": 11, "identifier": "Door", "color": "#8888FF", "width": 16, "height": 32,
       "fieldDefs": [{"identifier": "lockedWith", "__type": "LocalEnum.Item"}]},
      {"uid": 12, "identifier": "Player", "width": 16, "height": 16, "fieldDefs": []}
    ],
    "enums": [{"uid": 20, "identifier": "Item", "values": [{"id": "Gold", "color": 16766720}, {"id": "Key", "color": 255}]},
              {"uid": 21, "identifier": "Terrain", "values": [{"id": "Water", "color": 3355647}]}],
    "externalEnums": [],
    "tilesets": [{"uid": 5, "identifier": "T", "relPath": null, "pxWid": 32, "pxHei": 16, "tileGridSize": 16,
                  "tagsSourceEnumUid": 21, "enumTags": [{"enumValueId": "Water", "tileIds": [1]}], "customData": []}],
    "levelFields": [{"identifier": "music", "__type": "String"}, {"identifier": "loot", "__type": "LocalEnum.Item"}]
  },
  "levels": [],
  "worlds": [
    {"iid": "w1", "identifier": "Overworld", "worldLayout": "LinearHorizontal", "worldGridWidth": 64, "worldGridHeight": 32, "levels": [
      {"identifier": "A", "iid": "lA", "uid": 0, "worldX": 0, "worldY": 0, "worldDepth": 0, "pxWid": 64, "pxHei": 32,
       "__neighbours": [{"levelIid": "lB", "dir": "e"}],
       "fieldInstances": [{"__identifier": "music", "__type": "String", "__value": "overworld.ogg"},
                          {"__identifier": "loot", "__type": "LocalEnum.Item", "__value": "Gold"}],
       "layerInstances": [
         {"__identifier": "Entities", "__type": "Entities", "iid": "eA", "__cWid": 4, "__cHei": 2, "__gridSize": 16, "visible": true,
          "entityInstances": [
            {"__identifier": "Button", "iid": "b1", "px": [8, 8], "__pivot": [0.5, 0.5], "width": 16, "height": 16, "__tags": ["interactive"],
             "fieldInstances": [{"__identifier": "targets", "__type": "Array<EntityRef>", "__value": [
               {"entityIid": "d1", "layerIid": "eA", "levelIid": "lA", "worldIid": "w1"},
               {"entityIid": "d2", "layerIid": "eB", "levelIid": "lB", "worldIid": "w1"}]}]},
            {"__identifier": "Door", "iid": "d1", "px": [40, 8], "__pivot": [0, 0], "width": 16, "height": 32,
             "fieldInstances": [{"__identifier": "lockedWith", "__type": "LocalEnum.Item", "__value": "Key"}]},
            {"__identifier": "Player", "iid": "p1", "px": [24, 8], "__pivot": [0.5, 1], "width": 16, "height": 16, "fieldInstances": []}
          ]},
         {"__identifier": "Ground", "__type": "Tiles", "iid": "gA", "__cWid": 4, "__cHei": 2, "__gridSize": 16, "visible": true, "layerDefUid": 3,
          "__tilesetDefUid": 5, "gridTiles": [{"px": [0, 0], "src": [16, 0], "f": 0, "t": 1, "a": 1}]},
         {"__identifier": "Far", "__type": "Tiles", "iid": "fA", "__cWid": 4, "__cHei": 2, "__gridSize": 16, "visible": true, "layerDefUid": 2, "gridTiles": []},
         {"__identifier": "Collisions", "__type": "IntGrid", "iid": "cA", "__cWid": 4, "__cHei": 2, "__gridSize": 16, "visible": true, "layerDefUid": 1,
          "intGridCsv": [1, 1, 2, 2, 3, 3, 0, 1]}
       ]},
      {"identifier": "B", "iid": "lB", "uid": 1, "worldX": 64, "worldY": 0, "worldDepth": 0, "pxWid": 64, "pxHei": 32,
       "fieldInstances": [{"__identifier": "music", "__type": "String", "__value": "east.ogg"}],
       "layerInstances": [
         {"__identifier": "Entities", "__type": "Entities", "iid": "eB", "__cWid": 4, "__cHei": 2, "__gridSize": 16, "visible": true,
          "entityInstances": [
            {"__identifier": "Door", "iid": "d2", "px": [16, 0], "__pivot": [0, 0], "width": 16, "height": 32,
             "fieldInstances": [{"__identifier": "lockedWith", "__type": "LocalEnum.Item", "__value": null}]}
          ]}
       ]}
    ]},
    {"iid": "w2", "identifier": "Dungeon", "worldLayout": "Free", "levels": [
      {"identifier": "A", "iid": "lC", "uid": 2, "worldX": 0, "worldY": 0, "pxWid": 32, "pxHei": 32, "fieldInstances": [], "layerInstances": []}
    ]}
  ]
}`

@(test)
test_ldtk_worlds_enums_collision_mapping_links_lua :: proc(t: ^testing.T) {
	_ = os.make_directory_all("test_ldtk_worlds/components")
	defer os.remove_all("test_ldtk_worlds")
	_ = os.write_entire_file("test_ldtk_worlds/game.ldtk", transmute([]u8)string(LDTK_WORLDS_PROJECT))

	// --- data ---------------------------------------------------------------------------
	proj, ok := Ldtk_LoadProjectFromFile("test_ldtk_worlds/game.ldtk")
	testing.expect(t, ok && proj != nil, "project loads")
	if proj == nil do return
	testing.expect(t, proj.multiWorlds && len(proj.worlds) == 2, "two worlds")
	ow := Ldtk_GetWorld(proj, "Overworld")
	testing.expect(t, ow != nil && len(ow.levels) == 2 && ow.layout == "LinearHorizontal", "Overworld with 2 levels")
	// "A" exists in both worlds.
	testing.expect_value(t, Ldtk_GetLevelInWorld(proj, Ldtk_GetWorld(proj, "Dungeon"), "A").iid, "lC")
	testing.expect_value(t, Ldtk_LevelAt(proj, ow, {70, 5}).identifier, "B")
	gold, gi := Ldtk_GetEnumValue(proj, "Item", "Gold")
	testing.expect(t, gold != nil && gi == 0 && gold.color == {255, 215, 0, 255}, "enum value colour")
	lvlA := Ldtk_GetLevelInWorld(proj, ow, "A")
	coll := Ldtk_GetLayer(lvlA, "Collisions")
	testing.expect_value(t, Ldtk_GetIntGridValueDef(proj, coll, 2).identifier, "platform")
	testing.expect_value(t, Ldtk_GetLevelField(lvlA, "loot").enumName, "Item")
	testing.expect_value(t, len(proj.levelFieldDefs), 2)
	tags := Ldtk_GetTileEnumTags(proj, 5, 1)
	testing.expect(t, len(tags) == 1 && tags[0] == "Water", "tile enum tags")
	btn := Ldtk_GetEntityByIid(lvlA, "b1")
	refs := Ldtk_EntityRefs(btn)
	testing.expect(t, len(refs) == 2 && refs[1].ref.levelIid == "lB" && refs[1].index == 1, "array of entity refs with their level")
	testing.expect_value(t, Ldtk_EnumNameOf("Array<ExternEnum.Weapon>"), "Weapon")
	def := Ldtk_GetEntityDef(proj, "Door")
	testing.expect(t, def != nil && len(def.fields) == 1 && def.fields[0].enumName == "Item", "entity def fields")

	// LDtk's parallax: scaling layers scale by 1-f around the camera.
	far := Ldtk_GetLayer(lvlA, "Far")
	off, sc := Ldtk_ParallaxTransform(far, {100, 40})
	testing.expect(t, off == {50, 20} && sc == 0.5, "parallax with scaling")
	far.parallaxScaling = false
	off, sc = Ldtk_ParallaxTransform(far, {100, 40})
	testing.expect(t, off == {34, 12} && sc == 1, "parallax without scaling")
	Ldtk_DestroyProject(proj)

	// --- node in a running game -----------------------------------------------------------
	ScriptVFS_RegisterEmbedded("ldtk_button.lua", `
local B = {}
B.properties = {}
function B:ready() end
return B
`)
	ScriptVFS_RegisterEmbedded("ldtk_door.lua", `
local D = {}
D.properties = { lockedWith = { type = "string", default = "" } }
function D:ready() end
function D:open(value, source)
    opens = (opens or "") .. "open:" .. self.node:get_name() .. "<-" .. source:get_name() .. ";"
end
return D
`)
	_ = os.write_entire_file("test_ldtk_worlds/components/Button.component.json", transmute([]u8)string(`{"type": "Node", "name": "Button", "script": {"path": "ldtk_button.lua"}}`))
	_ = os.write_entire_file("test_ldtk_worlds/components/MyDoor.component.json", transmute([]u8)string(`{"type": "Node", "name": "Door", "script": {"path": "ldtk_door.lua"}}`))

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, "test_ldtk_worlds")
	scene := game->createScene("ldtk_worlds", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	game.physicsWorld.gravity = {0, 600}

	ln := cast(^LdtkLevelNode)Node_CreateByTypeName(scene, "LdtkLevelNode")
	ln.gameContext = &game.gameContext
	ln.worldIdentifier = "Overworld"
	ln.worldMode = true
	LdtkLevelNode_SetCollisionRule(ln, {layer = "Collisions", value = 1, type = .Solid, friction = 0.5})
	LdtkLevelNode_SetCollisionRule(ln, {layer = "Collisions", value = 2, type = .OneWay})
	LdtkLevelNode_SetCollisionRule(ln, {layer = "Collisions", value = 3, type = .Trigger})
	LdtkLevelNode_SetEntityMapping(ln, {entity = "Door", mode = .Component, component = "components/MyDoor.component.json"})
	LdtkLevelNode_SetEntityMapping(ln, {entity = "Player", mode = .None})
	append(&ln.linkRules, LdtkLinkRule{entity = "Button", field = "targets", action = .Signal, signal = "pressed", method = "open"})
	LdtkLevelNode_SetProject(ln, "test_ldtk_worlds/game.ldtk", "A")
	testing.expect_value(t, len(ln.activeLevels), 2)
	game->run(0.016)

	// Colliders: two merged wall boxes, one one-way platform box, one water trigger.
	testing.expect(t, ln.staticBody != nil && len(ln.staticBody.shapes) == 2, "wall colliders (merged)")
	testing.expect(t, ln.oneWayBody != nil && len(ln.oneWayBody.shapes) == 1, "one-way platform collider")
	testing.expect(t, len(ln.triggers) == 1 && ln.triggers[0].name == "Collisions_water" && len(ln.triggers[0].shapes) == 1, "water trigger area")

	// Mapping: Doors use MyDoor (LDtk enum field -> script property), Player not spawned.
	testing.expect_value(t, len(ln.spawnedEntities), 3)
	d1, d2 := ln.spawnedByIid["d1"], ln.spawnedByIid["d2"]
	testing.expect(t, d1 != nil && d1.componentPath == "components/MyDoor.component.json", "Door via the mapped component")
	testing.expect(t, d2 != nil && d2.position == {80, 0}, "world mode: level B's door at its world position")
	if d1 != nil && d1.scriptInstance != nil {
		testing.expect_value(t, (cast(^ScriptInstance)d1.scriptInstance).properties["lockedWith"].valString, "Key")
	}
	testing.expect(t, "p1" not_in ln.spawnedByIid, "Player mapped to None")
	testing.expect_value(t, len(ln.links), 2)

	// Link rule: Button "pressed" -> open() on both doors (one in another level).
	L := game.scriptManager.L
	ScriptVFS_RegisterEmbedded("ldtk_world_probe.lua", `
local P = {}
P.properties = {}
function P:on_level_loaded(id) loaded = id end
function P:ready()
    local lv = self.node
    local btn = lv:ldtk_get_entity_node("b1")
    local door = lv:ldtk_get_entity_node("d1")
    local parts = {}
    local function add(v) parts[#parts + 1] = tostring(v) end
    add(#lv:ldtk_get_worlds())
    add(lv:ldtk_get_world())
    add(lv:ldtk_level_at(70, 5))
    add(lv:ldtk_get_int_grid_name("Collisions", 40, 4))
    add((lv:ldtk_get_collision(2, 20)))
    add(lv:ldtk_get_enum("Item")[2].id)
    add(lv:ldtk_get_tile_enums("Ground", 4, 4)[1])
    add(door:ldtk_field("lockedWith"))
    add(door:ldtk_entity().enums.lockedWith)
    add(#btn:ldtk_refs("targets"))
    add(btn:ldtk_ref("targets"):get_name())
    add(door:ldtk_referenced_by()[1].field)
    add(lv:ldtk_get_level_field("music", "B"))
    add(lv:ldtk_get_level().neighbours[1].level)
    add(#lv:ldtk_get_layers())
    local x, y = lv:ldtk_cell_to_world("Collisions", 1, 1)
    add(x .. "," .. y)
    add(#lv:ldtk_get_entities_by_tag("interactive"))
    add(lv:ldtk_get_int_grid_values("Collisions")[2].collision)
    add(#lv:ldtk_get_links())
    btn:emit("pressed", 1)
    probe = table.concat(parts, "|")
end
return P
`)
	Script_AttachToNode(ln, "ldtk_world_probe.lua", nil, &game.scriptManager)
	game->run(0.016)
	lua.getglobal(L, "probe")
	testing.expect_value(t, string(lua.tostring(L, -1)), "2|Overworld|B|platform|trigger|Key|Water|Key|Item|2|Door|targets|east.ogg|B|4|24.0,24.0|1|one_way|2")
	lua.pop(L, 1)
	lua.getglobal(L, "opens")
	ev := strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
	lua.pop(L, 1)
	testing.expectf(t, strings.contains(ev, "open:Door<-Button") && strings.count(ev, "open:") == 2, "signal link opened both doors: %s", ev)
	// level_loaded reaches the level's script once the entities are ready.
	testing.expect(t, LdtkLevelNode_LoadLevel(ln, "A"), "reload level A")
	game->run(0.016)
	game->run(0.016)
	lua.getglobal(L, "loaded")
	testing.expect_value(t, string(lua.tostring(L, -1)), "A")
	lua.pop(L, 1)

	// One-way platform: a box falling onto it lands; one moving up passes through.
	falling := DynamicBodyNode_Create(scene, "Faller")
	falling.position = {60, -30}
	falling.globalPosition = falling.position
	falling.gameContext = &game.gameContext
	DynamicBodyNode_AddShape(falling, MakeBoxPhysicsShape(8, 8, {0, 0}, 0), &game.gameContext)
	rising := DynamicBodyNode_Create(scene, "Riser")
	rising.position = {40, 40}
	rising.globalPosition = rising.position
	rising.linearVelocity = {0, -400}
	rising.gameContext = &game.gameContext
	DynamicBodyNode_AddShape(rising, MakeBoxPhysicsShape(8, 8, {0, 0}, 0), &game.gameContext)
	for _ in 0 ..< 60 do game->run(0.016)
	testing.expectf(t, falling.position.y < 0 && falling.position.y > -12, "landed on the platform (y=%v)", falling.position.y)
	testing.expectf(t, rising.position.y < -10, "passed up through the platform (y=%v)", rising.position.y)

	// The configuration is saved with the scene and read back.
	ln.layerVisibility["Far"] = false
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	for want in ([]string{`"world": "Overworld"`, `"world_mode": true`, `"type": "one_way"`, `"type": "trigger"`, `"Door": {"mode": "component", "component": "components/MyDoor.component.json"}`, `"Player": {"mode": "none"}`, `"action": "signal", "signal": "pressed", "method": "open"`, `"layer_visibility": {"Far": false}`}) {
		testing.expectf(t, strings.contains(text, want), "saved: %s", want)
	}
	scene2 := game->createScene("ldtk_worlds2", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	Scene_InstantiateFromJSON(scene2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(scene2.manager, &game.gameContext)
	var: ^LdtkLevelNode
	for n in scene2.manager.nodes do if n != nil && n.typeId == LdtkLevelNode do var = cast(^LdtkLevelNode)n
	testing.expect(t, var != nil && var.worldMode && len(var.collisionRules) == 3 && len(var.entityMappings) == 2 && len(var.linkRules) == 1 && !var.layerVisibility["Far"], "config read back")
	testing.expect(t, var != nil && var.level != nil && var.level.iid == "lA" && len(var.activeLevels) == 2, "world and level restored")
}

// Colliders follow the level node's transform: the collider bodies are
// children at the level's origin and shapes scale with their node.
@(test)
test_ldtk_colliders_follow_level_scale :: proc(t: ^testing.T) {
	_ = os.make_directory_all("test_ldtk_scale")
	defer os.remove_all("test_ldtk_scale")
	_ = os.write_entire_file("test_ldtk_scale/game.ldtk", transmute([]u8)string(LDTK_WORLDS_PROJECT))
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("ldtk_scale", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	ln := cast(^LdtkLevelNode)Node_CreateByTypeName(scene, "LdtkLevelNode")
	ln.gameContext = &game.gameContext
	ln.spawnEntities = false
	ln.scale = {2, 3}
	ln.position = {100, 50}
	LdtkLevelNode_SetCollisionRule(ln, {layer = "Collisions", value = 1, type = .Solid})
	LdtkLevelNode_SetProject(ln, "test_ldtk_scale/game.ldtk", "A")
	game->run(0.016)
	game->run(0.016)

	// Row 0, cells 0-1 are walls: 32x16 at the level's top-left.
	has_aabb :: proc(sb: ^StaticBodyNode, lo, hi: [2]f32) -> bool {
		if sb == nil do return false
		for s in sb.shapes {
			box := b2.Shape_GetAABB(s.shapeId)
			if abs(box.lowerBound.x - lo.x) < 1 && abs(box.lowerBound.y - lo.y) < 1 && abs(box.upperBound.x - hi.x) < 1 && abs(box.upperBound.y - hi.y) < 1 do return true
		}
		return false
	}
	testing.expect(t, has_aabb(ln.staticBody, {100, 50}, {164, 98}), "wall collider scaled 2x3 at the level's origin")

	// Rescale while running: the shapes follow.
	ln.scale = {1, 1}
	game->run(0.016)
	game->run(0.016)
	testing.expect(t, has_aabb(ln.staticBody, {100, 50}, {132, 66}), "wall collider back at scale 1")
}

// Physics shapes follow their node's scale (also mirrored and changed at
// runtime), and so does a CharacterMover's capsule.
@(test)
test_physics_shapes_follow_node_scale :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("shape_scale", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	sb := StaticBodyNode_Create(scene, "Wall")
	sb.position = {200, 100}
	sb.scale = {2, 0.5}
	sb.gameContext = &game.gameContext
	StaticBodyNode_AddShape(sb, MakeBoxPhysicsShape(40, 40, {10, 0}, 0))
	circle := AreaNode_Create(scene, "Zone")
	circle.position = {0, 0}
	circle.scale = {3, 1}
	circle.gameContext = &game.gameContext
	AreaNode_AddShape(circle, MakeCirclePhysicsShape(10))
	game->run(0.016)
	game->run(0.016)

	box := b2.Shape_GetAABB(sb.shapes[0].shapeId)
	testing.expectf(t, abs(box.lowerBound.x - 180) < 1 && abs(box.upperBound.x - 260) < 1 && abs(box.lowerBound.y - 90) < 1 && abs(box.upperBound.y - 110) < 1, "box 40x40 offset 10 at scale 2x0.5: %v", box)
	testing.expect_value(t, sb.shapes[0].size, [2]f32{40, 40}) // authored size unchanged
	c := b2.Shape_GetCircle(circle.shapes[0].shapeId)
	testing.expectf(t, abs(c.radius - 30) < 0.01, "circle takes the larger axis: %v", c.radius)

	// Mirrored: the offset flips.
	sb.scale = {-1, 1}
	game->run(0.016)
	box = b2.Shape_GetAABB(sb.shapes[0].shapeId)
	testing.expectf(t, abs(box.lowerBound.x - 170) < 1 && abs(box.upperBound.x - 210) < 1, "mirrored box: %v", box)

	// A dynamic body's mass follows its area.
	db := DynamicBodyNode_Create(scene, "Crate")
	db.position = {500, 0}
	db.gameContext = &game.gameContext
	DynamicBodyNode_AddShape(db, MakeBoxPhysicsShape(10, 10))
	game->run(0.016)
	m1 := b2.Body_GetMass(db.bodyId)
	db.scale = {2, 2}
	game->run(0.016)
	m2 := b2.Body_GetMass(db.bodyId)
	testing.expectf(t, abs(m2 / m1 - 4) < 0.05, "mass x4 at scale 2 (%v -> %v)", m1, m2)

	// CharacterMover capsule: radius by x, length by y.
	cm := CharacterMoverNode_Create(scene, "Hero")
	cm.position = {0, 0}
	cm.scale = {2, 2}
	game->run(0.016)
	cap := CharacterMoverNode_GetWorldCapsule(cm)
	testing.expectf(t, abs(cap.radius - 28) < 0.01 && abs((cap.center2.y - cap.center1.y) - 56) < 0.01, "scaled capsule: %v", cap)
}
