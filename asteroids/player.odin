package asteroids
import e "../engine"
import "core:fmt"
import rl "vendor:raylib"



CreatePlayer :: proc(scene: ^e.Scene, game: ^e.Game, position: [2]f32) {
	player := e.CreateNodeScene(scene, e.Node, true)
	player.update = proc(node: ^e.Node, gameContext: ^e.GameContext, deltaTime: f32) {
		axis: f32 = 0
		if rl.IsKeyDown(.D) {
			axis += 1

		}

		if rl.IsKeyDown(.A) {
			axis -= 1
		}

		if rl.IsKeyPressed(.SPACE) {
			cannon, found := e.GetNodeByPath(gameContext.scene, node, "./cannon")
			if found {
				c := cast(^e.SoundNode)cannon
				e.SoundNode_Play(c)
			}
		}

		no, found := e.GetNodeByPath(gameContext.scene, node, "./player_animation_player")
		if !found {
			fmt.println("Animation player not found")
			return
		}
		apn := cast(^e.AnimationPlayerNode)no
		animation := e.AnimationPlayerNode_GetAnimation(apn)

		if axis > 0 {
			animation.flipX = false
			e.AnimationPlayerNode_Resume(apn)
		} else if axis < 0 {
			animation.flipX = true
			e.AnimationPlayerNode_Resume(apn)
		}
		else {
			e.AnimationPlayerNode_Pause(apn)
		}

		vel :[2]f32 = {350,0}
		node.position += vel * axis * deltaTime

	}


	cannon := e.SoundNode_Create(scene, &game.resourceManager, "assets/audio/cannon-gunshot-1.wav", "cannon")
	scene->addNode(cannon, player)
	runAnimation := e.GameCreateResource(game, e.SpriteSheetAnimation)
	e.SpriteSheetAnimation_Init(runAnimation, "run")
	runAnimation->loadSpriteSheet(&game.resourceManager, "assets/graphics/Running.png")
	runAnimation.grid.x = 12
	runAnimation.endFrame = 11
	runAnimation.startFrame = 0
	runAnimation.loop = true
	runAnimation.flipX = true
	apn := e.AnimationPlayerNode_Create(scene, "player_animation_player")
	e.AnimationPlayerNode_SetFPS(apn, 24)
	e.AnimationPlayerNode_AddAnimation(apn, runAnimation)

	e.AnimationPlayerNode_Start(apn)
	scene->addNode(apn, player)
}
