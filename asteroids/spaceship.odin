package asteroids
import e "../engine"
import "core:strconv/decimal"
import "core:math"
import "core:fmt"
import rl "vendor:raylib"

SPACESHIP_DEFAULT_POSITION : [2]f32 : {200, 200}
SPACESHIP_DEFAULT_SIZE: [2]f32: {50, 100}
SPACESHIP_DEFAULT_VELOCITY :: 300

Spaceship :: struct {
	maxSpeed: f32 `gui:"true" min:"10" max:"2000"`,
	velocity: [2]f32 `gui:"true" min:"-1000" max:"1000"`,
	acceleration: f32 `gui:"true" min:"10" max:"5000"`,
	deceleration: f32 `gui:"true" min:"10" max:"5000"`,
	axis: [2]f32 `gui:"true" min:"-1" max:"1"`,
	oldAxis: [2]f32,
	maxRotation: f32 `gui:"true" min:"0" max:"360"`,
}

CreateSpaceShip :: proc(scene: ^e.Scene, game: ^e.Game) {
	ship := e.CreateNodeScene(scene, e.Node, true)
	ship.name = "Spaceship"
	spaceship_data := e.Node_AddResource(ship, Spaceship)
	spaceship_data.maxSpeed = 800
	spaceship_data.acceleration = 2700
	spaceship_data.deceleration = 1000
	spaceship_data.maxRotation = 10
	ship.position = SPACESHIP_DEFAULT_POSITION
	ship.update = proc(node: ^e.Node, gameContext: ^e.GameContext, deltaTime: f32) {
		data := cast(^Spaceship)node.resource
		data.axis = {0, 0}
		if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) do data.axis[0] += 1
		if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) do data.axis[0] -= 1
		if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP) do data.axis[1] -= 1
		if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN) do data.axis[1] += 1


		no, found := e.GetNodeByPath(gameContext.scene, node, "./ship_animation_player")
		if !found {
			fmt.println("Animation player not found")
			return
		}
		apn := cast(^e.AnimationPlayerNode)no
		animation := e.AnimationPlayerNode_GetAnimation(apn)

		angle := math.atan2(data.axis[1], data.axis[0])
		maxVelocity :[2]f32 = {math.cos(abs(angle)) * data.maxSpeed, math.sin(abs(angle)) * data.maxSpeed}

		if data.axis[0] == 0 {
			// Decelerate the ship when no input is given
			absVelocity := math.abs(data.velocity[0])
			absVelocity -= data.deceleration * deltaTime
			absRot := math.abs(node.rotation)
			absRot -= 30 * deltaTime

			if data.velocity[0] > 0 {
				data.velocity[0] = max(absVelocity, 0)
				node.rotation = max(absRot, 0)
			}
			else if data.velocity[0] < 0 {
				data.velocity[0] = min(-absVelocity, 0)
				node.rotation = min(-absRot, 0)
			}
		}
		else {

			// Accelerate the ship based on input
			if data.oldAxis[0] != data.axis[0] {
				node.rotation = 0
			}
			node.rotation += 30 * data.axis[0] * deltaTime
			data.velocity[0] += math.cos(angle) * (data.acceleration * deltaTime)
			data.velocity[0] = clamp(data.velocity[0], -data.maxSpeed, data.maxSpeed)
		}
		node.rotation = clamp(node.rotation, -data.maxRotation, data.maxRotation)

		// Y Axis movement
		if data.axis[1] == 0 {
			// Decelerate the ship when no input is given
			absVelocity := math.abs(data.velocity[1])
			absVelocity -= data.deceleration * deltaTime
			if data.velocity[1] > 0 {
				data.velocity[1] = max(absVelocity, 0)
			}
			else if data.velocity[1] < 0 {
				data.velocity[1] = min(-absVelocity, 0)
			}
		}
		else {

			// Accelerate the ship based on input
			data.velocity[1] += math.sin(angle) * (data.acceleration * deltaTime)
			data.velocity[1] = clamp(data.velocity[1], -data.maxSpeed, data.maxSpeed)
		}
		node.position += data.velocity * deltaTime
		node.position[0] = clamp(node.position[0], 0, f32(rl.GetRenderWidth()) - animation.dest.width )
		node.position[1] = clamp(node.position[1], 0, f32(rl.GetRenderHeight()) - animation.dest.height )
		data.oldAxis = data.axis

	}
	ship_idle_animation := e.GameCreateResource(game, e.FrameAnimation)
	e.FrameAnimation_Init(ship_idle_animation, "ship_idle_animation")
	e.FrameAnimation_AddFrame(ship_idle_animation, &game.resourceManager, "assets/graphics/Ship_03/Exhaust/Exhaust_1_1_009.png")
	e.FrameAnimation_AddFrame(ship_idle_animation, &game.resourceManager, "assets/graphics/Ship_03/Exhaust/Exhaust_1_1_008.png")
	e.FrameAnimation_AddFrame(ship_idle_animation, &game.resourceManager, "assets/graphics/Ship_03/Exhaust/Exhaust_1_1_007.png")
	e.FrameAnimation_AddFrame(ship_idle_animation, &game.resourceManager, "assets/graphics/Ship_03/Exhaust/Exhaust_1_1_006.png")
	e.FrameAnimation_AddFrame(ship_idle_animation, &game.resourceManager, "assets/graphics/Ship_03/Exhaust/Exhaust_1_1_005.png")
	// e.FrameAnimation_AddFrame(ship_idle_animation, &game.resourceManager, "assets/graphics/Ship_03/Exhaust/Exhaust_1_1_004.png")
	// e.FrameAnimation_AddFrame(ship_idle_animation, &game.resourceManager, "assets/graphics/Ship_03/Exhaust/Exhaust_1_1_003.png")
	// e.FrameAnimation_AddFrame(ship_idle_animation, &game.resourceManager, "assets/graphics/Ship_03/Exhaust/Exhaust_1_1_002.png")
	// e.FrameAnimation_AddFrame(ship_idle_animation, &game.resourceManager, "assets/graphics/Ship_03/Exhaust/Exhaust_1_1_001.png")
	// e.FrameAnimation_AddFrame(ship_idle_animation, &game.resourceManager, "assets/graphics/Ship_03/Exhaust/Exhaust_1_1_000.png")
	ship_idle_animation.loop = true

	ship_apn := e.AnimationPlayerNode_Create(scene, "ship_animation_player")
	ship_apn.scale = .08
	e.AnimationPlayerNode_AddAnimation(ship_apn, ship_idle_animation)
	e.AnimationPlayerNode_SetAnimationByName(ship_apn, "ship_idle_animation")
	e.AnimationPlayerNode_Start(ship_apn)
	scene->addNode(ship_apn, ship)
}
