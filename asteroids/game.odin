package asteroids

import "core:log"
import rl "vendor:raylib"
import e "../engine"

CreateGame :: proc() -> ^e.Game {
	asteroids := new(e.Game)
	e.InitializeGame(asteroids)
	asteroids.setup = GameSetup
	asteroids.update = GameUpdate

	return asteroids
}

GameUpdate :: proc(game: ^e.Game, scene: ^e.Scene, deltaTime: f32) {
}

MainScene_Build :: proc(scene: ^e.Scene, ctx: ^e.GameContext) {
	if ctx == nil || ctx.game == nil do return
	game := ctx.game

	// 1. Spaceship (with child AnimationPlayer)
	_ = CreateSpaceShip(scene, game)

	// 2. Particle Emitter Node
	particleNode := e.ParticleEmitterNode_Create(scene, "Particle Emitter")
	particleNode.position = {640, 360}
	particleNode.emitter.amount = 50
	particleNode.emitter.lifetime = 2.0
	particleNode.emitter.velocity = 100
	particleNode.emitter.burst = 0.0
	particleNode.emitter.continuous = true
	if rl.IsWindowReady() {
		tex, ok := game.resourceManager->loadTexture("assets/graphics/Space Pack/Asteroids/Asteroid_1.png")
		if ok && tex != nil {
			particleNode.emitter.texture = &tex.texture
		}
	}

	// 3. Box2D Physics Nodes
	// StaticBodyNode (Floor & Ramp shapes)
	staticBody := e.StaticBodyNode_Create(scene, "StaticBody")
	staticBody.position = {640, 620}
	e.StaticBodyNode_AddShape(staticBody, e.MakeBoxPhysicsShape(560, 28, {0, 0}, 0), ctx)
	e.StaticBodyNode_AddShape(staticBody, e.MakeBoxPhysicsShape(140, 20, {-200, -45}, 18), ctx)
	e.StaticBodyNode_AddShape(staticBody, e.MakeBoxPhysicsShape(140, 20, {200, -45}, -18), ctx)

	// DynamicBodyNode (Crate shape)
	dynamicBody := e.DynamicBodyNode_Create(scene, "DynamicBody")
	dynamicBody.position = {640, 180}
	boxShape := e.MakeBoxPhysicsShape(44, 44)
	boxShape.restitution = 0.45
	e.DynamicBodyNode_AddShape(dynamicBody, boxShape, ctx)

	// CharacterMoverNode
	characterMover := e.CharacterMoverNode_Create(scene, "CharacterMover")
	characterMover.position = {540, 320}

	// AreaNode
	areaNode := e.AreaNode_Create(scene, "Area Sensor")
	areaNode.position = {640, 520}
	e.AreaNode_AddShape(areaNode, e.MakeBoxPhysicsShape(240, 90), ctx)

	// RaycastNode
	raycastNode := e.RaycastNode_Create(scene, "Raycast")
	raycastNode.position = {330, 535}
	raycastNode.direction = {1.0, 0.25}
	raycastNode.length = 440.0

	// 4. Lua 5.4 Scripted Recon Drone (demonstrating node script attachment & lifecycle)
	droneNode := e.TextureNode_Create(scene, &game.resourceManager, "assets/graphics/Space Pack/Ships/Ship_2.png")
	droneNode.name = "ReconDrone"
	droneNode.origin = {droneNode.size.x * 0.5, droneNode.size.y * 0.5}
	e.Script_AttachToNode(droneNode, "assets/scripts/orbiting_drone.lua", nil, &game.scriptManager)
}

GameSetup :: proc(game: ^e.Game) {
	log.info("Setup Asteroids")

	// Register embedded Lua scripts for standalone binary release packaging
	e.ScriptVFS_RegisterEmbedded("assets/scripts/orbiting_drone.lua", #load("../assets/scripts/orbiting_drone.lua", string))

	// 1. Create Main Playable Scene ("main") as initial active scene
	_ = game->createScene("main", true, MainScene_Build)

	// 2. Create Battle Arena Scene ("battle_arena") with Starfield, Spaceships, Turrets, Camera
	_ = game->createScene("battle_arena", false, BattleArenaScene_Build)

	// 3. Create Deep Space Station Scene ("deep_space_station") loaded directly from LDtk Level Editor Project
	_ = game->createScene("deep_space_station", false, DeepSpaceStationScene_Build)

	game.state = .Ready
	game.drawBounds = true
}
