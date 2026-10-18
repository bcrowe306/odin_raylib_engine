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

	// 2. In-Game HUD (ReturnToMenu button)
	CreateInGameHUD(scene)

	// 3. Particle Emitter Node
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

	// 4. Box2D Physics Nodes
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
}

GameSetup :: proc(game: ^e.Game) {
	log.info("Setup")
	uiState := e.GameCreateResource(game, AsteroidsUIState)

	// 1. Create Main Playable Scene ("main") with scene builder
	_ = game->createScene("main", false, MainScene_Build)

	// 2. Create Battle Arena Scene ("battle_arena") with Starfield, Spaceships, Turrets, Camera & Combat HUD
	_ = game->createScene("battle_arena", false, BattleArenaScene_Build)

	// 3. Create Settings Menu Scene ("settings") with full UI Widget & Container Showcase
	_ = CreateSettingsMenuScene(game, uiState)

	// 4. Create Title Menu Scene ("title_menu") as initial active scene
	_ = CreateTitleMenuScene(game, true)

	game.state = .Ready
	game.drawBounds = true
}
