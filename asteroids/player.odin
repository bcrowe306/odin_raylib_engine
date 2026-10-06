package asteroids
import e "../engine"
import rl "vendor:raylib"



CreatePlayer :: proc(scene: ^e.Scene, game: ^e.Game, position: [2]f32) {
	runAnimation := e.GameCreateResource(game, e.SpriteSheetAnimation)
	e.SpriteSheetAnimation_Init(runAnimation)
	runAnimation->loadSpriteSheet(&game.resourceManager, "assets/graphics/Running.png")
	runAnimation.grid.x = 12
	runAnimation.endFrame = 11
	runAnimation.startFrame = 0
	runAnimation.loop = true
	runAnimation.flipX = true
	apn := e.AnimationPlayerNode_Create(scene)
	e.AnimationPlayerNode_SetFPS(apn, 24)
	apn.position = position
	apn.scale = .5
	e.AnimationPlayerNode_AddAnimation(apn, runAnimation)

	e.AnimationPlayerNode_Start(apn)
	scene->addNode(apn)
}
