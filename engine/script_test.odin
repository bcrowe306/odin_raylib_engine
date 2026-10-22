package engine

import "core:testing"

// ============================================================================
// Lua 5.4 Scripting Subsystem Unit Tests
// ============================================================================

@(test)
test_script_manager_lifecycle :: proc(t: ^testing.T) {
	sm: ScriptManager
	ok := ScriptManager_Init(&sm)
	testing.expect(t, ok, "ScriptManager_Init should succeed")
	testing.expect(t, sm.isReady, "ScriptManager should be marked ready")
	testing.expect(t, sm.L != nil, "Lua state should not be nil")

	ScriptManager_Destroy(&sm)
	testing.expect(t, !sm.isReady, "ScriptManager should not be ready after destroy")
	testing.expect(t, sm.L == nil, "Lua state should be nil after destroy")
}

@(test)
test_script_property_reflection :: proc(t: ^testing.T) {
	sm: ScriptManager
	ScriptManager_Init(&sm)
	defer ScriptManager_Destroy(&sm)

	scriptSource := `
local M = {}
M.properties = {
    speed = { type = "float", default = 150.0, min = 10.0, max = 500.0, label = "Movement Speed" },
    count = { type = "int", default = 5, min = 1, max = 10, label = "Enemy Count" },
    targetName = { type = "string", default = "PlayerNode", label = "Target Node Name" },
    isActive = { type = "bool", default = true, label = "Active Toggle" },
    offset = { type = "vector2", default = { 10.0, 20.0 }, label = "Spawn Offset" },
}
return M
`
	ScriptVFS_RegisterEmbedded("test_reflection.lua", scriptSource)

	props, ok := Script_InspectProperties("test_reflection.lua", &sm)
	testing.expect(t, ok, "Script_InspectProperties should succeed")
	testing.expect_value(t, len(props), 5)

	propMap := make(map[string]ScriptProperty, context.temp_allocator)
	for p in props {
		propMap[p.name] = p
	}

	// 1. Float speed
	speedProp, hasSpeed := propMap["speed"]
	testing.expect(t, hasSpeed, "Should have 'speed' property")
	testing.expect_value(t, speedProp.type, ScriptPropertyType.Float)
	testing.expect_value(t, speedProp.defaultVal.valFloat, f32(150.0))
	testing.expect(t, speedProp.min == 10.0, "Min should be 10.0")
	testing.expect(t, speedProp.max == 500.0, "Max should be 500.0")
	testing.expect_value(t, speedProp.label, "Movement Speed")

	// 2. Int count
	countProp, hasCount := propMap["count"]
	testing.expect(t, hasCount, "Should have 'count' property")
	testing.expect_value(t, countProp.type, ScriptPropertyType.Int)
	testing.expect_value(t, countProp.defaultVal.valInt, 5)

	// 3. String targetName
	targetProp, hasTarget := propMap["targetName"]
	testing.expect(t, hasTarget, "Should have 'targetName' property")
	testing.expect_value(t, targetProp.type, ScriptPropertyType.String)
	testing.expect_value(t, targetProp.defaultVal.valString, "PlayerNode")

	// 4. Bool isActive
	activeProp, hasActive := propMap["isActive"]
	testing.expect(t, hasActive, "Should have 'isActive' property")
	testing.expect_value(t, activeProp.type, ScriptPropertyType.Boolean)
	testing.expect_value(t, activeProp.defaultVal.valBool, true)

	// 5. Vector2 offset
	offsetProp, hasOffset := propMap["offset"]
	testing.expect(t, hasOffset, "Should have 'offset' property")
	testing.expect_value(t, offsetProp.type, ScriptPropertyType.Vector2)
	testing.expect_value(t, offsetProp.defaultVal.valVec2.x, f32(10.0))
	testing.expect_value(t, offsetProp.defaultVal.valVec2.y, f32(20.0))
}

@(test)
test_script_instance_lifecycle_and_transforms :: proc(t: ^testing.T) {
	sm: ScriptManager
	ScriptManager_Init(&sm)
	defer ScriptManager_Destroy(&sm)

	scriptSource := `
local M = {}
M.properties = {
    speed = { type = "float", default = 100.0 },
    readyCalled = { type = "bool", default = false },
}

function M:ready()
    self.readyCalled = true
    self.node:set_position(50.0, 50.0)
    self.node:set_rotation(45.0)
end

function M:update(dt)
    self.node:translate(self.speed * dt, 0.0)
end

function M:on_destroy()
    self.readyCalled = false
end

return M
`
	ScriptVFS_RegisterEmbedded("test_drone.lua", scriptSource)

	testNode: Node
	InitializeNode(&testNode)
	testNode.name = "DroneNode"
	defer Node_Terminate(&testNode)

	// Attach script with an override: speed = 200.0 instead of default 100.0
	overrides := make(map[string]ScriptValue, context.temp_allocator)
	overrides["speed"] = ScriptValue{ type = .Float, valFloat = 200.0 }

	inst := Script_AttachToNode(&testNode, "test_drone.lua", overrides, &sm)
	testing.expect(t, inst != nil, "ScriptInstance should not be nil")
	testing.expect_value(t, testNode.scriptInstance, rawptr(inst))

	// Verify overridden speed
	speedVal, hasSpeed := ScriptInstance_GetProperty(inst, "speed")
	testing.expect(t, hasSpeed, "Should have property speed")
	testing.expect_value(t, speedVal.valFloat, f32(200.0))

	// Call ready
	ScriptInstance_CallReady(inst, &sm)
	testing.expect(t, inst.isReady, "ScriptInstance should be marked ready")
	testing.expect_value(t, testNode.position.x, f32(50.0))
	testing.expect_value(t, testNode.position.y, f32(50.0))
	testing.expect_value(t, testNode.rotation, f32(45.0))

	// Call update with dt = 0.5s: dx = speed * dt = 200.0 * 0.5 = 100.0 -> x becomes 50 + 100 = 150.0
	ScriptInstance_CallUpdate(inst, 0.5, &sm)
	testing.expect_value(t, testNode.position.x, f32(150.0))
	testing.expect_value(t, testNode.position.y, f32(50.0))

	// Live property update: change speed to 50.0
	ScriptInstance_SetProperty(inst, "speed", ScriptValue{ type = .Float, valFloat = 50.0 }, &sm)
	newSpeed, _ := ScriptInstance_GetProperty(inst, "speed")
	testing.expect_value(t, newSpeed.valFloat, f32(50.0))

	// Update again with dt = 1.0s: dx = 50.0 * 1.0 = 50.0 -> x becomes 150 + 50 = 200.0
	ScriptInstance_CallUpdate(inst, 1.0, &sm)
	testing.expect_value(t, testNode.position.x, f32(200.0))

	// Destroy instance
	ScriptInstance_Destroy(inst, &sm)
	testNode.scriptInstance = nil
}

@(test)
test_script_vfs_require_module :: proc(t: ^testing.T) {
	sm: ScriptManager
	ScriptManager_Init(&sm)
	defer ScriptManager_Destroy(&sm)

	mathHelperSource := `
local MathHelper = {}
function MathHelper.double(x)
    return x * 2.0
end
return MathHelper
`
	ScriptVFS_RegisterEmbedded("utils/math_helper.lua", mathHelperSource)

	mainSource := `
local MathHelper = require("utils.math_helper")
local M = {}
M.properties = {
    result = { type = "float", default = 0.0 }
}

function M:ready()
    self.result = MathHelper.double(21.0)
end

return M
`
	ScriptVFS_RegisterEmbedded("test_require_main.lua", mainSource)

	testNode: Node
	InitializeNode(&testNode)
	testNode.name = "RequireTestNode"
	defer Node_Terminate(&testNode)

	inst := Script_AttachToNode(&testNode, "test_require_main.lua", nil, &sm)
	testing.expect(t, inst != nil, "Script should load with require()")

	ScriptInstance_CallReady(inst, &sm)
	testing.expect(t, inst.isReady, "ScriptInstance should be ready")

	ScriptInstance_Destroy(inst, &sm)
	testNode.scriptInstance = nil
}

@(test)
test_script_node_in_scene :: proc(t: ^testing.T) {
	scriptSource := `
local M = {}
M.properties = {
    rotationSpeed = { type = "float", default = 90.0 }
}

function M:ready()
    Log.info("ScriptNode scene ready!")
end

function M:update(dt)
    self.node:rotate(self.rotationSpeed * dt)
end

return M
`
	ScriptVFS_RegisterEmbedded("rotator.lua", scriptSource)

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()

	scene := game->createScene("TestScene", true, proc(s: ^Scene, ctx: ^GameContext) {
		sn := ScriptNode_Create(s, "rotator.lua", "RotatorNode", nil, nil, ctx.scriptManager if ctx != nil else nil)
		_ = sn
	})
	testing.expect(t, scene != nil, "Scene should be created")

	game.state = .Running

	// Frame 1: Scene initializes node, calls ready(), and updates by 90.0 * 1.0s = 90.0 deg
	game->run(1.0)

	rotNode, found := GetNodeByPath(scene, scene.rootNode, "/RotatorNode")
	testing.expect(t, found && rotNode != nil, "RotatorNode should be found in scene")
	testing.expect_value(t, rotNode.rotation, f32(90.0))

	// Frame 2: rotated by another 90.0 deg -> 180.0 deg
	game->run(1.0)
	testing.expect_value(t, rotNode.rotation, f32(180.0))
}

@(test)
test_script_engine_and_camera_bindings :: proc(t: ^testing.T) {
	scriptSource := `
local M = {}

function M:ready()
    -- Test Engine globals
    local fps = Engine.get_fps()
    local dt = Engine.get_delta_time()
    local vw, vh = Engine.get_virtual_size()

    -- Test Camera globals
    Camera.set_zoom(2.5)
    Camera.set_target_position(320.0, 240.0)
    Camera.shake(0.8, 0.4)
end

function M:update(dt)
    local tx, ty = Camera.get_target_position()
    local zoom = Camera.get_zoom()
    local shaking = Camera.is_shaking()
    Camera.stop_shake()
end

return M
`
	ScriptVFS_RegisterEmbedded("test_camera_script.lua", scriptSource)

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()

	scene := game->createScene("CameraTestScene", true, proc(s: ^Scene, ctx: ^GameContext) {
		cam := CameraNode_Create(s, "MainCamera", true)
		_ = cam
		sn := ScriptNode_Create(s, "test_camera_script.lua", "CameraScriptNode", nil, nil, ctx.scriptManager if ctx != nil else nil)
		_ = sn
	})
	testing.expect(t, scene != nil, "CameraTestScene should be created")

	game.state = .Running
	game->run(0.016)

	cam := scene.camera
	testing.expect(t, cam != nil, "Camera should exist in scene")
	testing.expect_value(t, cam.targetZoom, f32(2.5))
	testing.expect_value(t, cam.targetPosition.x, f32(320.0))
	testing.expect_value(t, cam.targetPosition.y, f32(240.0))
}

@(test)
test_script_physics_and_nodes_bindings :: proc(t: ^testing.T) {
	scriptSource := `
local M = {}

function M:ready()
    -- Test Physics globals
    Physics.set_gravity(0.0, 400.0)
    local gx, gy = Physics.get_gravity()

    -- Test Node types & methods
    local myType = self.node:get_type()
    Log.info("Node type is: " .. myType)
end

return M
`
	ScriptVFS_RegisterEmbedded("test_physics_script.lua", scriptSource)

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()

	scene := game->createScene("PhysicsTestScene", true, proc(s: ^Scene, ctx: ^GameContext) {
		sn := ScriptNode_Create(s, "test_physics_script.lua", "PhysicsScriptNode", nil, nil, ctx.scriptManager if ctx != nil else nil)
		_ = sn

		timerNode := TimerNode_Create(s, 5.0, false, false)
		timerNode.name = "TestTimer"

		pen := ParticleEmitterNode_Create(s, "TestEmitter")
		_ = pen
	})
	testing.expect(t, scene != nil, "PhysicsTestScene should be created")

	game.state = .Running
	game->run(0.016)

	testing.expect_value(t, game.physicsWorld.gravity.y, f32(400.0))
}

@(test)
test_script_scene_dynamic_spawning :: proc(t: ^testing.T) {
	scriptSource := `
local M = {}

function M:ready()
    -- Dynamically spawn a child TextureNode via Scene.create_node
    local childSprite = Scene.create_node("TextureNode", "DynamicSprite", self.node)
    if childSprite then
        childSprite:set_position(75.0, 85.0)
        childSprite:set_scale(1.5, 1.5)
    end
end

return M
`
	ScriptVFS_RegisterEmbedded("test_spawner.lua", scriptSource)

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()

	scene := game->createScene("SpawnScene", true, proc(s: ^Scene, ctx: ^GameContext) {
		sn := ScriptNode_Create(s, "test_spawner.lua", "SpawnerNode", nil, nil, ctx.scriptManager if ctx != nil else nil)
		_ = sn
	})

	game.state = .Running
	game->run(0.016)

	spawner, foundSpawner := GetNodeByPath(scene, scene.rootNode, "/SpawnerNode")
	testing.expect(t, foundSpawner && spawner != nil, "SpawnerNode should exist")

	childSprite, foundChild := GetNodeByPath(scene, spawner, "DynamicSprite")
	testing.expect(t, foundChild && childSprite != nil, "DynamicSprite should have been dynamically created via Scene.create_node")
	testing.expect_value(t, childSprite.position.x, f32(75.0))
	testing.expect_value(t, childSprite.position.y, f32(85.0))
	testing.expect_value(t, childSprite.scale.x, f32(1.5))
	testing.expect_value(t, childSprite.typeId, TextureNode)
}
