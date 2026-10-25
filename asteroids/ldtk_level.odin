package asteroids

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"

// ============================================================================
// LDtk Space Station Level Data Structures
// ============================================================================

MAX_STATION_BULLETS :: 96

StationBullet :: struct {
	position: [2]f32,
	velocity: [2]f32,
	rotation: f32,
	damage:   f32,
	lifetime: f32,
	isPlayer: bool,
	alive:    bool,
	radius:   f32,
	tex:      rl.Texture2D,
}

StationTurret :: struct {
	position:     [2]f32,
	gunRotation:  f32,
	health:       f32,
	maxHealth:    f32,
	alive:        bool,
	fireTimer:    f32,
	fireInterval: f32,
	detectRange:  f32,
	radius:       f32,
}

StationPatrol :: struct {
	position:     [2]f32,
	velocity:     [2]f32,
	rotation:     f32,
	health:       f32,
	maxHealth:    f32,
	alive:        bool,
	patrolAnchor: [2]f32,
	patrolAngle:  f32,
	patrolRadius: f32,
	speed:        f32,
	fireTimer:    f32,
	radius:       f32,
}

StationAsteroid :: struct {
	position: [2]f32,
	rotation: f32,
	rotSpeed: f32,
	scale:    f32,
	radius:   f32,
}

StationEnergyCore :: struct {
	position:  [2]f32,
	collected: bool,
	radius:    f32,
	floatTime: f32,
}

DeepSpaceStationNode :: struct {
	using node:           e.Node,
	ldtkNode:             ^e.LdtkLevelNode,
	camera:               ^e.CameraNode,
	playerShip:           ^e.Node,
	playerPos:            [2]f32,
	playerVel:            [2]f32,
	playerAngle:          f32,
	playerHealth:         f32,
	playerMaxHealth:      f32,
	playerShield:         f32,
	playerMaxShield:      f32,
	playerFireTimer:      f32,
	score:                int,
	coresCollected:       int,
	coresTotal:           int,
	missionComplete:      bool,
	gameOver:             bool,
	goalPos:              [2]f32,
	goalRadius:           f32,

	// Game entity arrays
	turrets:              [dynamic]StationTurret,
	patrols:              [dynamic]StationPatrol,
	asteroids:            [dynamic]StationAsteroid,
	energyCores:          [dynamic]StationEnergyCore,
	bullets:              [dynamic]StationBullet,

	// Textures
	texPlayer:            rl.Texture2D,
	texEnemyScout:        rl.Texture2D,
	texEnemyFighter:      rl.Texture2D,
	texTurretBase:        rl.Texture2D,
	texTurretGun:         rl.Texture2D,
	texPlayerLaser:       rl.Texture2D,
	texEnemyLaser:        rl.Texture2D,
	texAsteroid:          rl.Texture2D,
	texBox:               rl.Texture2D,
}

// ============================================================================
// Entity Spawner for LDtk Level
// ============================================================================

DeepSpaceStation_EntitySpawner :: proc(
	levelNode: ^e.LdtkLevelNode,
	entity: ^e.LdtkEntityInstance,
	scene: ^e.Scene,
	ctx: ^e.GameContext,
) -> ^e.Node {
	stNode := cast(^DeepSpaceStationNode)levelNode.resource
	if stNode == nil do return nil

	switch entity.identifier {
	case "PlayerStart":
		stNode.playerPos = entity.px
		if stNode.playerShip != nil {
			stNode.playerShip.position = entity.px
			stNode.playerShip.globalPosition = entity.px
		}

	case "StationGoal":
		stNode.goalPos = entity.px
		stNode.goalRadius = max(entity.size.x, entity.size.y) * 0.5

	case "Turret":
		hp := e.Ldtk_GetFieldFloat(entity, "health", 150.0)
		rate := e.Ldtk_GetFieldFloat(entity, "fireRate", 1.2)
		append(&stNode.turrets, StationTurret{
			position     = entity.px,
			gunRotation  = 0.0,
			health       = hp,
			maxHealth    = hp,
			alive        = true,
			fireTimer    = rate,
			fireInterval = rate,
			detectRange  = 550.0,
			radius       = 24.0,
		})

	case "PatrolEnemy":
		hp := e.Ldtk_GetFieldFloat(entity, "health", 90.0)
		rad := e.Ldtk_GetFieldFloat(entity, "patrolRadius", 150.0)
		append(&stNode.patrols, StationPatrol{
			position     = entity.px,
			velocity     = {0, 0},
			rotation     = 0.0,
			health       = hp,
			maxHealth    = hp,
			alive        = true,
			patrolAnchor = entity.px,
			patrolAngle  = 0.0,
			patrolRadius = rad,
			speed        = 110.0,
			fireTimer    = 1.5,
			radius       = 22.0,
		})

	case "AsteroidHazard":
		rotSpeed := e.Ldtk_GetFieldFloat(entity, "rotSpeed", 30.0)
		append(&stNode.asteroids, StationAsteroid{
			position = entity.px,
			rotation = 0.0,
			rotSpeed = rotSpeed,
			scale    = 0.7,
			radius   = 24.0,
		})

	case "EnergyCell":
		append(&stNode.energyCores, StationEnergyCore{
			position  = entity.px,
			collected = false,
			radius    = 24.0,
			floatTime = f32(len(stNode.energyCores)) * 0.75,
		})
		stNode.coresTotal += 1
	}

	return nil
}

// ============================================================================
// Scene Setup & Builder
// ============================================================================

DeepSpaceStationScene_Build :: proc(scene: ^e.Scene, ctx: ^e.GameContext) {
	if ctx == nil || ctx.game == nil do return
	game := ctx.game

	// 1. Root Level Manager Node
	stationNode := e.CreateNodeScene(scene, DeepSpaceStationNode, true)
	stationNode.name = "DeepSpaceStationManager"
	stationNode.layer = .Layer3
	stationNode.turrets = make([dynamic]StationTurret, stationNode.allocator)
	stationNode.patrols = make([dynamic]StationPatrol, stationNode.allocator)
	stationNode.asteroids = make([dynamic]StationAsteroid, stationNode.allocator)
	stationNode.energyCores = make([dynamic]StationEnergyCore, stationNode.allocator)
	stationNode.bullets = make([dynamic]StationBullet, stationNode.allocator)

	stationNode.playerPos = {240, 544}
	stationNode.playerVel = {0, 0}
	stationNode.playerAngle = 0.0
	stationNode.playerHealth = 100.0
	stationNode.playerMaxHealth = 100.0
	stationNode.playerShield = 100.0
	stationNode.playerMaxShield = 100.0
	stationNode.playerFireTimer = 0.0
	stationNode.score = 0
	stationNode.coresCollected = 0
	stationNode.coresTotal = 0
	stationNode.missionComplete = false
	stationNode.gameOver = false
	stationNode.goalPos = {1760, 544}
	stationNode.goalRadius = 36.0

	// 2. Player Ship Node (World Node)
	playerShip := e.CreateNodeScene(scene, e.Node, true)
	playerShip.name = "PlayerStationShip"
	playerShip.position = stationNode.playerPos
	playerShip.layer = .Layer3
	stationNode.playerShip = playerShip

	// 3. LDtk Level Node (Loads deep_space_station.ldtk)
	ldtkNode := e.LdtkLevelNode_Create(
		scene,
		"DeepSpaceStationMap",
		"assets/levels/deep_space_station.ldtk",
		"Deep_Space_Station",
	)
	ldtkNode.resource = stationNode
	ldtkNode.entitySpawner = DeepSpaceStation_EntitySpawner
	stationNode.ldtkNode = ldtkNode

	// Build Box2D static collision bodies from IntGrid layer
	e.LdtkLevelNode_BuildCollisionBodies(ldtkNode, "Collisions", []int{1}, ctx)

	// Spawn LDtk entities into the level manager
	e.LdtkLevelNode_SpawnEntities(ldtkNode, ctx)

	// 4. Smooth Tracking Camera
	cameraNode := e.CameraNode_Create(scene, "StationCamera", true)
	cameraNode.position = stationNode.playerPos
	cameraNode.dragType = .SmoothDamp
	cameraNode.zoom = 1.0
	cameraNode.hasLimits = true
	cameraNode.leftLimit = 0.0
	cameraNode.rightLimit = 1920.0
	cameraNode.topLimit = 0.0
	cameraNode.bottomLimit = 1088.0
	e.CameraNode_SetTarget(cameraNode, playerShip)
	stationNode.camera = cameraNode

	// 5. Load Textures
	rm := &game.resourceManager
	if rl.IsWindowReady() {
		if t, ok := rm->loadTexture("assets/graphics/Ship_01/Ship_LVL_1.png"); ok && t != nil {
			stationNode.texPlayer = t.texture
		}
		if t, ok := rm->loadTexture("assets/graphics/Space Pack/Ships/Spaceship_2.png"); ok && t != nil {
			stationNode.texEnemyScout = t.texture
		}
		if t, ok := rm->loadTexture("assets/graphics/Space Pack/Ships/Spaceship_1.png"); ok && t != nil {
			stationNode.texEnemyFighter = t.texture
		}
		if t, ok := rm->loadTexture("assets/graphics/Space Pack/Turrets/Base_1.png"); ok && t != nil {
			stationNode.texTurretBase = t.texture
		}
		if t, ok := rm->loadTexture("assets/graphics/Space Pack/Turrets/Gun_1.png"); ok && t != nil {
			stationNode.texTurretGun = t.texture
		}
		if t, ok := rm->loadTexture("assets/graphics/Ship_Effects/Laser_1_1.png"); ok && t != nil {
			stationNode.texPlayerLaser = t.texture
		}
		if t, ok := rm->loadTexture("assets/graphics/Ship_Effects/Fire_Shot_1_1.png"); ok && t != nil {
			stationNode.texEnemyLaser = t.texture
		}
		if t, ok := rm->loadTexture("assets/graphics/Space Pack/Asteroids/Asteroid_1.png"); ok && t != nil {
			stationNode.texAsteroid = t.texture
		}
		if t, ok := rm->loadTexture("assets/graphics/Space Pack/Box/Cube_1.png"); ok && t != nil {
			stationNode.texBox = t.texture
		}
	}

	stationNode.update = DeepSpaceStationNode_Update
	stationNode.render = DeepSpaceStationNode_Render
	stationNode.onDestroy = DeepSpaceStationNode_Destroy

}

// ============================================================================
// Level Lifecycle & Physics / Combat Simulation
// ============================================================================

DeepSpaceStationNode_Update :: proc(node: ^e.Node, ctx: ^e.GameContext, deltaTime: f32) {
	st := cast(^DeepSpaceStationNode)node
	if !st.enabled do return
	dt := deltaTime if deltaTime > 0.0 else 0.016

	// 1. Player Ship Controls via Two-Tier Input System
	if !st.gameOver && !st.missionComplete {
		axis := e.GetActionVector2(ctx, .MoveLeft, .MoveRight, .MoveUp, .MoveDown)
		thrustSpeed: f32 = 420.0
		if e.IsActionDown(ctx, .Boost) || rl.IsKeyDown(.LEFT_SHIFT) {
			thrustSpeed *= 1.45
		}

		if axis.x != 0.0 || axis.y != 0.0 {
			targetVel := axis * thrustSpeed
			st.playerVel += (targetVel - st.playerVel) * min(dt * 7.5, 1.0)
			st.playerAngle = math.atan2(st.playerVel.y, st.playerVel.x) * (180.0 / math.PI) + 90.0
		} else {
			st.playerVel *= max(1.0 - dt * 2.8, 0.0)
		}

		// Proposed new position
		newPos := st.playerPos + st.playerVel * dt

		// IntGrid collision resolution with LDtk station walls
		if st.ldtkNode != nil && st.ldtkNode.level != nil {
			colLayer := e.Ldtk_GetLayer(st.ldtkNode.level, "Collisions")
			if colLayer != nil {
				shipRadius: f32 = 18.0
				checkOffsets := [4][2]f32{
					{newPos.x + shipRadius, newPos.y},
					{newPos.x - shipRadius, newPos.y},
					{newPos.x, newPos.y + shipRadius},
					{newPos.x, newPos.y - shipRadius},
				}
				collided := false
				for pt in checkOffsets {
					val := e.Ldtk_GetIntGridValueAtPixel(colLayer, pt.x, pt.y)
					if val == 1 {
						collided = true
						break
					} else if val == 2 {
						// Hazard barrier damage!
						st.playerShield = max(st.playerShield - 40.0 * dt, 0.0)
						if st.playerShield <= 0.0 {
							st.playerHealth = max(st.playerHealth - 30.0 * dt, 0.0)
						}
					}
				}
				if !collided {
					st.playerPos = newPos
				} else {
					st.playerVel = -st.playerVel * 0.4
					if st.camera != nil {
						e.CameraNode_ApplyShakePreset(st.camera, .Impact)
					}
				}
			} else {
				st.playerPos = newPos
			}
		} else {
			st.playerPos = newPos
		}

		// Clamp player inside station canvas
		st.playerPos.x = clamp(st.playerPos.x, 32.0, 1888.0)
		st.playerPos.y = clamp(st.playerPos.y, 32.0, 1056.0)

		if st.playerShip != nil {
			st.playerShip.position = st.playerPos
			st.playerShip.globalPosition = st.playerPos
			st.playerShip.rotation = st.playerAngle
		}

		// Player laser firing
		st.playerFireTimer -= dt
		isFirePressed := e.IsActionPressed(ctx, .Fire) || rl.IsKeyPressed(.SPACE) || e.IsActionDown(ctx, .Fire) || rl.IsKeyDown(.SPACE)
		if isFirePressed && st.playerFireTimer <= 0.0 {
			st.playerFireTimer = 0.18

			rad := (st.playerAngle - 90.0) * (math.PI / 180.0)
			fwd := [2]f32{math.cos(rad), math.sin(rad)}
			spawnPt := st.playerPos + fwd * 26.0

			append(&st.bullets, StationBullet{
				position = spawnPt,
				velocity = fwd * 620.0,
				rotation = st.playerAngle,
				damage   = 35.0,
				lifetime = 1.6,
				isPlayer = true,
				alive    = true,
				radius   = 10.0,
				tex      = st.texPlayerLaser,
			})
		}
	}

	// 2. Turrets Behavior (Aim at player & fire)
	for &turret in st.turrets {
		if !turret.alive do continue
		diff := st.playerPos - turret.position
		dist := math.sqrt(diff.x * diff.x + diff.y * diff.y)

		if !st.gameOver && dist <= turret.detectRange {
			turret.gunRotation = math.atan2(diff.y, diff.x) * (180.0 / math.PI)
			turret.fireTimer -= dt
			if turret.fireTimer <= 0.0 {
				turret.fireTimer = turret.fireInterval
				rad := turret.gunRotation * (math.PI / 180.0)
				fwd := [2]f32{math.cos(rad), math.sin(rad)}
				spawnPt := turret.position + fwd * 32.0

				append(&st.bullets, StationBullet{
					position = spawnPt,
					velocity = fwd * 380.0,
					rotation = turret.gunRotation + 90.0,
					damage   = 15.0,
					lifetime = 2.0,
					isPlayer = false,
					alive    = true,
					radius   = 10.0,
					tex      = st.texEnemyLaser,
				})
			}
		}
	}

	// 3. Patrol Enemies Behavior
	for &patrol in st.patrols {
		if !patrol.alive do continue
		patrol.patrolAngle += dt * 0.85
		targetX := patrol.patrolAnchor.x + math.cos(patrol.patrolAngle) * patrol.patrolRadius
		targetY := patrol.patrolAnchor.y + math.sin(patrol.patrolAngle) * patrol.patrolRadius
		diff := [2]f32{targetX, targetY} - patrol.position
		patrol.position += diff * min(dt * 3.0, 1.0)
		patrol.rotation = math.atan2(diff.y, diff.x) * (180.0 / math.PI) + 90.0
	}

	// 4. Asteroid Hazards Rotation
	for &ast in st.asteroids {
		ast.rotation += ast.rotSpeed * dt
	}

	// 5. Energy Core Collection
	for &core in st.energyCores {
		if core.collected do continue
		core.floatTime += dt
		diff := st.playerPos - core.position
		dist := math.sqrt(diff.x * diff.x + diff.y * diff.y)
		if dist <= (core.radius + 20.0) {
			core.collected = true
			st.coresCollected += 1
			st.score += 250
			st.playerShield = min(st.playerShield + 25.0, st.playerMaxShield)
			if st.camera != nil {
				e.CameraNode_ApplyShakePreset(st.camera, .Impact)
			}
		}
	}

	// 6. Extraction Gate Reach Condition
	if st.coresCollected >= st.coresTotal && !st.missionComplete {
		diff := st.playerPos - st.goalPos
		dist := math.sqrt(diff.x * diff.x + diff.y * diff.y)
		if dist <= (st.goalRadius + 28.0) {
			st.missionComplete = true
			st.score += 1000
		}
	}

	// 7. Bullets Update & Hit Registration
	colLayer: ^e.LdtkLayerInstance = nil
	if st.ldtkNode != nil && st.ldtkNode.level != nil {
		colLayer = e.Ldtk_GetLayer(st.ldtkNode.level, "Collisions")
	}

	for i := len(st.bullets) - 1; i >= 0; i -= 1 {
		b := &st.bullets[i]
		if !b.alive {
			ordered_remove(&st.bullets, i)
			continue
		}

		b.position += b.velocity * dt
		b.lifetime -= dt
		if b.lifetime <= 0.0 {
			ordered_remove(&st.bullets, i)
			continue
		}

		// Bullet hitting station wall
		if colLayer != nil {
			if e.Ldtk_GetIntGridValueAtPixel(colLayer, b.position.x, b.position.y) == 1 {
				ordered_remove(&st.bullets, i)
				continue
			}
		}

		// Player bullets hitting Turrets or Patrols
		if b.isPlayer {
			hitTarget := false
			for &turret in st.turrets {
				if !turret.alive do continue
				diff := b.position - turret.position
				if (diff.x * diff.x + diff.y * diff.y) <= (b.radius + turret.radius) * (b.radius + turret.radius) {
					turret.health -= b.damage
					if turret.health <= 0.0 {
						turret.alive = false
						st.score += 200
					}
					hitTarget = true
					break
				}
			}
			if !hitTarget {
				for &patrol in st.patrols {
					if !patrol.alive do continue
					diff := b.position - patrol.position
					if (diff.x * diff.x + diff.y * diff.y) <= (b.radius + patrol.radius) * (b.radius + patrol.radius) {
						patrol.health -= b.damage
						if patrol.health <= 0.0 {
							patrol.alive = false
							st.score += 150
						}
						hitTarget = true
						break
					}
				}
			}
			if hitTarget {
				ordered_remove(&st.bullets, i)
				continue
			}
		} else {
			// Hostile bullet hitting player
			diff := b.position - st.playerPos
			if (diff.x * diff.x + diff.y * diff.y) <= (b.radius + 18.0) * (b.radius + 18.0) {
				if st.playerShield > 0.0 {
					st.playerShield = max(st.playerShield - b.damage, 0.0)
				} else {
					st.playerHealth = max(st.playerHealth - b.damage, 0.0)
					if st.playerHealth <= 0.0 {
						st.gameOver = true
					}
				}
				if st.camera != nil {
					e.CameraNode_ApplyShakePreset(st.camera, .Impact)
				}
				ordered_remove(&st.bullets, i)
				continue
			}
		}
	}
}

DeepSpaceStationNode_Render :: proc(node: ^e.Node, ctx: ^e.GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	st := cast(^DeepSpaceStationNode)node

	// 1. Draw Extraction Goal Gate
	goalColor := rl.Color{34, 197, 94, 180} if st.coresCollected >= st.coresTotal else rl.Color{234, 179, 8, 140}
	rl.DrawCircleLines(i32(st.goalPos.x), i32(st.goalPos.y), st.goalRadius, goalColor)
	rl.DrawCircle(i32(st.goalPos.x), i32(st.goalPos.y), st.goalRadius * 0.45, rl.ColorAlpha(goalColor, 0.4))

	// 2. Draw Floating Energy Cores
	for core in st.energyCores {
		if core.collected do continue
		pulse := 1.0 + math.sin(core.floatTime * 4.0) * 0.15
		coreR := core.radius * pulse
		rl.DrawCircleGradient(i32(core.position.x), i32(core.position.y), coreR, rl.Color{56, 189, 248, 255}, rl.Color{14, 165, 233, 40})
		rl.DrawCircleLines(i32(core.position.x), i32(core.position.y), coreR, rl.Color{186, 230, 253, 240})
	}

	// 3. Draw Asteroids
	for ast in st.asteroids {
		if st.texAsteroid.id > 0 {
			src := rl.Rectangle{0, 0, f32(st.texAsteroid.width), f32(st.texAsteroid.height)}
			dest := rl.Rectangle{ast.position.x, ast.position.y, f32(st.texAsteroid.width) * ast.scale, f32(st.texAsteroid.height) * ast.scale}
			orig := rl.Vector2{dest.width * 0.5, dest.height * 0.5}
			rl.DrawTexturePro(st.texAsteroid, src, dest, orig, ast.rotation, rl.WHITE)
		} else {
			rl.DrawCircle(i32(ast.position.x), i32(ast.position.y), ast.radius, rl.GRAY)
		}
	}

	// 4. Draw Turrets
	for turret in st.turrets {
		if !turret.alive do continue
		if st.texTurretBase.id > 0 {
			src := rl.Rectangle{0, 0, f32(st.texTurretBase.width), f32(st.texTurretBase.height)}
			dest := rl.Rectangle{turret.position.x, turret.position.y, 44, 44}
			rl.DrawTexturePro(st.texTurretBase, src, dest, {22, 22}, 0, rl.WHITE)
		}
		if st.texTurretGun.id > 0 {
			src := rl.Rectangle{0, 0, f32(st.texTurretGun.width), f32(st.texTurretGun.height)}
			dest := rl.Rectangle{turret.position.x, turret.position.y, 44, 44}
			rl.DrawTexturePro(st.texTurretGun, src, dest, {22, 22}, turret.gunRotation + 90.0, rl.WHITE)
		}
	}

	// 5. Draw Patrol Enemies
	for patrol in st.patrols {
		if !patrol.alive do continue
		if st.texEnemyScout.id > 0 {
			src := rl.Rectangle{0, 0, f32(st.texEnemyScout.width), f32(st.texEnemyScout.height)}
			dest := rl.Rectangle{patrol.position.x, patrol.position.y, 40, 40}
			rl.DrawTexturePro(st.texEnemyScout, src, dest, {20, 20}, patrol.rotation, rl.WHITE)
		}
	}

	// 6. Draw Bullets
	for b in st.bullets {
		if !b.alive do continue
		if b.tex.id > 0 {
			src := rl.Rectangle{0, 0, f32(b.tex.width), f32(b.tex.height)}
			dest := rl.Rectangle{b.position.x, b.position.y, 16, 28}
			rl.DrawTexturePro(b.tex, src, dest, {8, 14}, b.rotation, rl.WHITE)
		} else {
			col := rl.Color{56, 189, 248, 255} if b.isPlayer else rl.Color{239, 68, 68, 255}
			rl.DrawCircle(i32(b.position.x), i32(b.position.y), b.radius, col)
		}
	}

	// 7. Draw Player Ship
	if st.texPlayer.id > 0 {
		src := rl.Rectangle{0, 0, f32(st.texPlayer.width), f32(st.texPlayer.height)}
		dest := rl.Rectangle{st.playerPos.x, st.playerPos.y, 48, 48}
		rl.DrawTexturePro(st.texPlayer, src, dest, {24, 24}, st.playerAngle, rl.WHITE)
	}

	// 8. Screen-Space Combat / Telemetry HUD
	e.CameraNode_End()
	defer if st.camera != nil && st.camera.isCurrent {
		e.CameraNode_Begin(st.camera)
	}

	// Status Overlay Banner
	rl.DrawRectangle(14, 76, 380, 84, rl.Color{16, 20, 28, 230})
	rl.DrawRectangleLinesEx(rl.Rectangle{14, 76, 380, 84}, 1, rl.Color{48, 56, 75, 255})

	statusText := fmt.tprintf("CORES SECURED: %d / %d   |   SCORE: %d", st.coresCollected, st.coresTotal, st.score)
	cstrStatus := strings.clone_to_cstring(statusText, context.temp_allocator)
	rl.DrawText(cstrStatus, 26, 88, 14, rl.Color{147, 197, 253, 255})

	// Health & Shield Bars
	rl.DrawText("SHIELD", 26, 110, 11, rl.Color{180, 190, 210, 255})
	rl.DrawRectangle(74, 112, 120, 8, rl.Color{30, 36, 48, 255})
	rl.DrawRectangle(74, 112, i32((st.playerShield / st.playerMaxShield) * 120.0), 8, rl.Color{56, 189, 248, 255})

	rl.DrawText("HULL", 26, 126, 11, rl.Color{180, 190, 210, 255})
	rl.DrawRectangle(74, 128, 120, 8, rl.Color{30, 36, 48, 255})
	rl.DrawRectangle(74, 128, i32((st.playerHealth / st.playerMaxHealth) * 120.0), 8, rl.Color{34, 197, 94, 255})

	if st.missionComplete {
		rl.DrawText("MISSION ACCOMPLISHED! ALL CORES EXTRACTED", 26, 142, 12, rl.Color{74, 222, 128, 255})
	} else if st.coresCollected >= st.coresTotal {
		rl.DrawText("WARP GATE ONLINE! REACH EXTRACTION POINT", 26, 142, 12, rl.Color{250, 204, 21, 255})
	} else {
		rl.DrawText("INFILTRATE & EXTRACT ALL 4 ENERGY CORES", 26, 142, 12, rl.Color{156, 163, 175, 255})
	}
}

DeepSpaceStationNode_Destroy :: proc(node: ^e.Node, ctx: ^e.GameContext) {
	st := cast(^DeepSpaceStationNode)node
	delete(st.turrets)
	delete(st.patrols)
	delete(st.asteroids)
	delete(st.energyCores)
	delete(st.bullets)
}
