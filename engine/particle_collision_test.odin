package engine

import "core:fmt"
import "core:strings"
import "core:testing"
import lua "lua54"

// #123: particles collide with the physics world (not the window's edges in
// world coordinates): anywhere, negative space included; bounce / stop /
// kill; collision layers; the particle_hit event.

@(private = "file")
Collision_Run :: struct {
	game:    ^Game,
	scene:   ^Scene,
	emitter: ^ParticleEmitterNode,
	floor:   ^StaticBodyNode,
}

// collision_run: a floor at y = -100 (top -110) and an emitter above it at
// (-500, -300) dropping particles straight down, stepped for `seconds`.
@(private = "file")
collision_run :: proc(mode: ParticleCollisionMode, layers: CollisionLayerSet, seconds: f32, name: string) -> Collision_Run {
	r: Collision_Run
	r.game = new(Game)
	InitializeGame(r.game)
	r.scene = r.game->createScene(name, true)
	ProcessSceneChange(&r.game.sceneManager, &r.game.gameContext)
	r.game.state = .Running
	ctx := &r.game.gameContext

	r.floor = StaticBodyNode_Create(r.scene, "Floor")
	r.floor.position = {-500, -100}
	r.floor.gameContext = ctx
	StaticBodyNode_AddShape(r.floor, MakeBoxPhysicsShape(400, 20), ctx)

	r.emitter = ParticleEmitterNode_Create(r.scene, "Drops")
	r.emitter.position = {-500, -300}
	em := &r.emitter.emitter
	em.amount = 20
	em.burst = 1
	em.lifetime = 4
	em.continuous = false
	em.angle = 90 // down
	em.velocity = 50
	em.gravityVelocity = 400
	em.collisionEnabled = true
	em.collisionMode = mode
	em.collisionLayers = layers
	em.elasticity = 0.5
	ProcessNodeQueues(r.scene.manager, ctx)
	for _ in 0 ..< int(seconds * 60) do r.game->run(1.0 / 60)
	return r
}

@(private = "file")
alive_particles :: proc(em: ^ParticleEmitter) -> (n: int, maxY, minX, maxX: f32) {
	maxY, minX, maxX = -1e9, 1e9, -1e9
	for p in em.particles do if p.alive {
		n += 1
		maxY = max(maxY, p.position.y)
		minX = min(minX, p.position.x)
		maxX = max(maxX, p.position.x)
	}
	return
}

@(test)
test_particle_collision_physics_world :: proc(t: ^testing.T) {
	// Bounce: they land on the floor in negative space and stay above it -
	// not pushed to x, y >= 0 (the old clamp to the window).
	{
		r := collision_run(.Bounce, DEFAULT_COLLISION_MASK, 1.5, "bounce")
		defer r.game->terminate()
		n, maxY, minX, maxX := alive_particles(&r.emitter.emitter)
		testing.expect_value(t, n, 20)
		testing.expectf(t, maxY <= -109, "above the floor's top (-110): %v", maxY)
		testing.expectf(t, minX > -510 && maxX < -490, "where they were emitted (x -500): %v..%v", minX, maxX)
		testing.expect(t, r.emitter.emitter.lastHitNode == cast(^Node)r.floor, "the floor was hit")
	}
	// Stop: they rest on it.
	{
		r := collision_run(.Stop, DEFAULT_COLLISION_MASK, 1.5, "stop")
		defer r.game->terminate()
		for p in r.emitter.emitter.particles do if p.alive {
			testing.expectf(t, p.position.y > -112 && p.position.y <= -109, "resting on the floor: %v", p.position.y)
			testing.expectf(t, abs(p.velocity.y) < 10, "not moving: %v", p.velocity)
		}
	}
	// Kill: they die on it.
	{
		r := collision_run(.Kill, DEFAULT_COLLISION_MASK, 1.5, "kill")
		defer r.game->terminate()
		n, _, _, _ := alive_particles(&r.emitter.emitter)
		testing.expect_value(t, n, 0)
	}
	// Another layer: the floor (Layer1) isn't in the mask - they fall through.
	{
		r := collision_run(.Bounce, {.Layer2}, 1.5, "layers")
		defer r.game->terminate()
		_, maxY, _, _ := alive_particles(&r.emitter.emitter)
		testing.expectf(t, maxY > 0, "fell through the floor: %v", maxY)
		testing.expect(t, r.emitter.emitter.lastHitNode == nil, "nothing hit")
	}
}

// The particle_hit event reaches a script, and particle_get_last_hit says
// where.
@(test)
test_particle_hit_event :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("particle_hits.lua", `
local P = {}
function P:on_particle_hit(other)
	hits = (hits or 0) + 1
	hit_name = other and other:get_name()
	local x, y, nx, ny = self.node:particle_get_last_hit()
	hit_y, hit_ny = y, ny
end
return P
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("hits", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	ctx := &game.gameContext
	floor := StaticBodyNode_Create(scene, "Floor")
	floor.position = {-500, -100}
	floor.gameContext = ctx
	StaticBodyNode_AddShape(floor, MakeBoxPhysicsShape(400, 20), ctx)
	pen := ParticleEmitterNode_Create(scene, "Drops")
	pen.position = {-500, -300}
	pen.emitter.amount, pen.emitter.burst, pen.emitter.continuous = 5, 1, false
	pen.emitter.angle, pen.emitter.gravityVelocity = 90, 400
	pen.emitter.collisionEnabled, pen.emitter.collisionMode = true, .Kill
	pen.gameContext = ctx
	Script_AttachToNode(pen, "particle_hits.lua", nil, &game.scriptManager)
	ProcessNodeQueues(scene.manager, ctx)
	for _ in 0 ..< 90 do game->run(1.0 / 60)

	L := game.scriptManager.L
	get :: proc(L: ^lua.State, expr: string) -> string {
		_ = lua.L_dostring(L, strings.clone_to_cstring(fmt.tprintf("return tostring(%s)", expr), context.temp_allocator))
		defer lua.pop(L, 1)
		return strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
	}
	testing.expect_value(t, get(L, "hits"), "5")
	testing.expect_value(t, get(L, "hit_name"), "Floor")
	testing.expect_value(t, get(L, "math.floor(hit_y + 0.5)"), "-110")
	testing.expect_value(t, get(L, "hit_ny"), "-1.0")
}
