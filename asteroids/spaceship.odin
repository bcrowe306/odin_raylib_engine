package asteroids

import "core:math"
import rl "vendor:raylib"
import e "../engine"

SPACESHIP_DEFAULT_POSITION: [2]f32 : {200, 200}
SPACESHIP_DEFAULT_SIZE: [2]f32 : {50, 100}
SPACESHIP_DEFAULT_VELOCITY :: 300

Spaceship :: struct {
	maxSpeed:        f32 `gui:"true" min:"10" max:"2000"`,
	velocity:        [2]f32 `gui:"true" min:"-1000" max:"1000"`,
	acceleration:    f32 `gui:"true" min:"10" max:"5000"`,
	deceleration:    f32 `gui:"true" min:"10" max:"5000"`,
	axis:            [2]f32 `gui:"true" min:"-1" max:"1"`,
	oldAxis:         [2]f32,
	maxRotation:     f32 `gui:"true" min:"0" max:"360"`,
	animationPlayer: ^e.AnimationPlayerNode,
}

Spaceship_Ready :: proc(node: ^e.Node, gameContext: ^e.GameContext) {
	data := cast(^Spaceship)node.resource
	if data == nil do return

	// The ready proc runs only once when the scene is loaded and all other initial scene nodes are present!
	no, found := e.GetNodeByPath(gameContext.scene, node, "./ship_animation_player")
	if found && no != nil {
		data.animationPlayer = cast(^e.AnimationPlayerNode)no
		e.AnimationPlayerNode_Start(data.animationPlayer)
	}
}

Spaceship_Update :: proc(node: ^e.Node, gameContext: ^e.GameContext, deltaTime: f32) {
	data := cast(^Spaceship)node.resource
	if data == nil do return

	// Query Logical Actions via the Two-Tier Input System (hardware-agnostic)
	data.axis = e.GetActionVector2(gameContext, .MoveLeft, .MoveRight, .MoveUp, .MoveDown)

	destW, destH: f32 = 0, 0
	if data.animationPlayer != nil {
		anim := e.AnimationPlayerNode_GetAnimation(data.animationPlayer)
		if anim != nil {
			destW = anim.dest.width
			destH = anim.dest.height
		}
	} else {
		no, found := e.GetNodeByPath(gameContext.scene, node, "./ship_animation_player")
		if found && no != nil {
			data.animationPlayer = cast(^e.AnimationPlayerNode)no
			e.AnimationPlayerNode_Start(data.animationPlayer)
		}
	}

	effectiveMaxSpeed := data.maxSpeed
	if e.IsActionDown(gameContext, .Boost) {
		effectiveMaxSpeed *= 1.5
	}

	angle := math.atan2(data.axis[1], data.axis[0])

	if data.axis[0] == 0 {
		absVelocity := math.abs(data.velocity[0])
		absVelocity -= data.deceleration * deltaTime
		absRot := math.abs(node.rotation)
		absRot -= 30 * deltaTime

		if data.velocity[0] > 0 {
			data.velocity[0] = max(absVelocity, 0)
			node.rotation = max(absRot, 0)
		} else if data.velocity[0] < 0 {
			data.velocity[0] = min(-absVelocity, 0)
			node.rotation = min(-absRot, 0)
		}
	} else {
		if data.oldAxis[0] != data.axis[0] {
			node.rotation = 0
		}
		node.rotation += 30 * data.axis[0] * deltaTime
		data.velocity[0] += math.cos(angle) * (data.acceleration * deltaTime)
		data.velocity[0] = clamp(data.velocity[0], -effectiveMaxSpeed, effectiveMaxSpeed)
	}
	node.rotation = clamp(node.rotation, -data.maxRotation, data.maxRotation)

	// Y Axis movement
	if data.axis[1] == 0 {
		absVelocity := math.abs(data.velocity[1])
		absVelocity -= data.deceleration * deltaTime
		if data.velocity[1] > 0 {
			data.velocity[1] = max(absVelocity, 0)
		} else if data.velocity[1] < 0 {
			data.velocity[1] = min(-absVelocity, 0)
		}
	} else {
		data.velocity[1] += math.sin(angle) * (data.acceleration * deltaTime)
		data.velocity[1] = clamp(data.velocity[1], -effectiveMaxSpeed, effectiveMaxSpeed)
	}
	node.position += data.velocity * deltaTime

	boundsW: f32 = 1280.0
	boundsH: f32 = 720.0
	if gameContext != nil && gameContext.game != nil && gameContext.game.virtualSize.x > 0 {
		boundsW = gameContext.game.virtualSize.x
		boundsH = gameContext.game.virtualSize.y
	} else if rl.IsWindowReady() {
		boundsW = f32(rl.GetRenderWidth())
		boundsH = f32(rl.GetRenderHeight())
	}

	node.position[0] = clamp(node.position[0], 0, boundsW - destW)
	node.position[1] = clamp(node.position[1], 0, boundsH - destH)
	data.oldAxis = data.axis
}

CreateSpaceShip :: proc(scene: ^e.Scene, game: ^e.Game) -> ^e.Node {
	ship := e.CreateNodeScene(scene, e.Node, true)
	ship.name = "Spaceship"
	spaceship_data := e.Node_AddResource(ship, Spaceship)
	spaceship_data.maxSpeed = 800
	spaceship_data.acceleration = 2700
	spaceship_data.deceleration = 1000
	spaceship_data.maxRotation = 10
	ship.position = SPACESHIP_DEFAULT_POSITION

	// Node ready and update procs
	ship.ready = Spaceship_Ready
	ship.update = Spaceship_Update

	ship_idle_animation := e.GameCreateResource(game, e.FrameAnimation)
	e.FrameAnimation_Init(ship_idle_animation, "ship_idle_animation")
	e.FrameAnimation_AddFrame(ship_idle_animation, &game.resourceManager, "assets/graphics/Ship_03/Exhaust/Exhaust_1_1_009.png")
	e.FrameAnimation_AddFrame(ship_idle_animation, &game.resourceManager, "assets/graphics/Ship_03/Exhaust/Exhaust_1_1_008.png")
	e.FrameAnimation_AddFrame(ship_idle_animation, &game.resourceManager, "assets/graphics/Ship_03/Exhaust/Exhaust_1_1_007.png")
	e.FrameAnimation_AddFrame(ship_idle_animation, &game.resourceManager, "assets/graphics/Ship_03/Exhaust/Exhaust_1_1_006.png")
	e.FrameAnimation_AddFrame(ship_idle_animation, &game.resourceManager, "assets/graphics/Ship_03/Exhaust/Exhaust_1_1_005.png")
	ship_idle_animation.loop = true

	ship_apn := e.AnimationPlayerNode_Create(scene, "ship_animation_player")
	ship_apn.scale = .08
	e.AnimationPlayerNode_AddAnimation(ship_apn, ship_idle_animation)
	e.AnimationPlayerNode_SetAnimationByName(ship_apn, "ship_idle_animation")
	scene->addNode(ship_apn, ship)

	return ship
}
