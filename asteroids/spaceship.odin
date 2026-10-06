package asteroids
import e "../engine"
import rl "vendor:raylib"

SPACESHIP_DEFAULT_POSITION : [2]f32 : {200, 200}
SPACESHIP_DEFAULT_SIZE: [2]f32: {50, 100}
SPACESHIP_DEFAULT_VELOCITY :: 300



CreateSpaceShip :: proc(scene: ^e.Scene, game: ^e.Game) {
	ship := e.CreateNodeScene(scene, e.Node)
	ship.update = proc(node: ^e.Node, gameContext: ^e.GameContext, deltaTime: f32) {
		if rl.IsKeyDown(.D) {
			node.position += {5, 0}
		}
		if rl.IsKeyDown(.A){
			node.position += {-5, 0}
		}

		if rl.IsKeyDown(.S) {
			node.position += {0, 5}
		}

		if rl.IsKeyDown(.W){
			node.position += {0, -5}
		}
	}

	shipAnimation := e.FrameAnimationNode_Create(scene)

	// e.FrameAnimationNode_AddFrame(ship, &game.resourceManager, "assets/graphics/Ship_01/Exhaust/Exhaust_1_1_001.png")
	// e.FrameAnimationNode_AddFrame(ship, &game.resourceManager, "assets/graphics/Ship_01/Exhaust/Exhaust_1_1_000.png")
	e.FrameAnimationNode_AddFrame(shipAnimation, &game.resourceManager, "assets/graphics/Ship_01/Exhaust/Exhaust_1_1_002.png")
	e.FrameAnimationNode_AddFrame(shipAnimation, &game.resourceManager, "assets/graphics/Ship_01/Exhaust/Exhaust_1_1_003.png")
	e.FrameAnimationNode_AddFrame(shipAnimation, &game.resourceManager, "assets/graphics/Ship_01/Exhaust/Exhaust_1_1_004.png")
	e.FrameAnimationNode_AddFrame(shipAnimation, &game.resourceManager, "assets/graphics/Ship_01/Exhaust/Exhaust_1_1_005.png")
	e.FrameAnimationNode_AddFrame(shipAnimation, &game.resourceManager, "assets/graphics/Ship_01/Exhaust/Exhaust_1_1_006.png")
	e.FrameAnimationNode_AddFrame(shipAnimation, &game.resourceManager, "assets/graphics/Ship_01/Exhaust/Exhaust_1_1_007.png")
	e.FrameAnimationNode_AddFrame(shipAnimation, &game.resourceManager, "assets/graphics/Ship_01/Exhaust/Exhaust_1_1_008.png")
	e.FrameAnimationNode_AddFrame(shipAnimation, &game.resourceManager, "assets/graphics/Ship_01/Exhaust/Exhaust_1_1_009.png")


	shipAnimation.loop = true
	shipAnimation.scale = .1
	shipAnimation.position = {100,100}
	e.FrameAnimationNode_Start(shipAnimation)
	e.FrameAnimationNode_SetFPS(shipAnimation, 6)
	scene->addNode(ship)
	scene->addNode(shipAnimation, ship)

}
