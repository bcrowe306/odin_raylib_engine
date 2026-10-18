package asteroids

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import e "../engine"

// ============================================================================
// Battle Level Constants & Configuration
// ============================================================================

ARENA_MIN_X: f32 : -1000.0
ARENA_MAX_X: f32 :  2280.0
ARENA_MIN_Y: f32 : -1000.0
ARENA_MAX_Y: f32 :  1720.0

MAX_BULLETS :: 128
MAX_ENEMIES :: 6
MAX_TURRETS :: 4
MAX_ASTEROIDS :: 8

BattleBullet :: struct {
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

BattleEnemy :: struct {
	position:     [2]f32,
	velocity:     [2]f32,
	rotation:     f32,
	health:       f32,
	maxHealth:    f32,
	alive:        bool,
	tex:          rl.Texture2D,
	scale:        f32,
	speed:        f32,
	fireTimer:    f32,
	fireInterval: f32,
	radius:       f32,
	patrolAnchor: [2]f32,
	patrolAngle:  f32,
	name:         string,
}

BattleTurret :: struct {
	position:     [2]f32,
	gunRotation:  f32,
	health:       f32,
	maxHealth:    f32,
	alive:        bool,
	texBase:      rl.Texture2D,
	texGun:       rl.Texture2D,
	fireTimer:    f32,
	fireInterval: f32,
	detectRange:  f32,
	radius:       f32,
}

BattleAsteroid :: struct {
	position: [2]f32,
	rotation: f32,
	rotSpeed: f32,
	scale:    f32,
	radius:   f32,
	tex:      rl.Texture2D,
}

BattleLevelNode :: struct {
	using node: e.Node,

	// Camera & Player references
	camera:           ^e.CameraNode,
	playerShip:       ^e.Node,
	playerPos:        [2]f32,
	playerVel:        [2]f32,
	playerAngle:      f32,
	playerHealth:     f32,
	playerMaxHealth:  f32,
	playerShield:     f32,
	playerMaxShield:  f32,
	shieldRegenDelay: f32,
	playerFireTimer:  f32,

	// Textures
	texPlayer:       rl.Texture2D,
	texEnemyScout:   rl.Texture2D,
	texEnemyFighter: rl.Texture2D,
	texEnemyCruiser: rl.Texture2D,
	texTurretBase:   rl.Texture2D,
	texTurretGun:    rl.Texture2D,
	texPlayerLaser:  rl.Texture2D,
	texEnemyLaser:   rl.Texture2D,
	texTurretLaser:  rl.Texture2D,
	texAsteroid1:    rl.Texture2D,
	texAsteroid2:    rl.Texture2D,
	texAsteroid3:    rl.Texture2D,

	// Game entities
	bullets:    [MAX_BULLETS]BattleBullet,
	enemies:    [MAX_ENEMIES]BattleEnemy,
	turrets:    [MAX_TURRETS]BattleTurret,
	asteroids:  [MAX_ASTEROIDS]BattleAsteroid,

	// Game stats
	score:        int,
	gameOver:     bool,
	victory:      bool,
	sceneRef:     ^e.Scene,
	cannonSound:  ^e.AudioSound,
}

// ============================================================================
// Particle Explosion Helper
// ============================================================================

SpawnBattleExplosion :: proc(scene: ^e.Scene, position: [2]f32, scale: f32 = 1.0) {
	if scene == nil do return
	emitterNode := e.ParticleEmitterNode_Create(scene, "ExplosionEffect")
	emitterNode.position = position
	emitterNode.layer = .Layer3

	emitter := &emitterNode.emitter
	emitter.amount = int(45 * scale)
	emitter.burst = f32(45 * scale)
	emitter.continuous = false
	emitter.lifetime = 0.55
	emitter.velocity = 180.0 * scale
	emitter.size = {6 * scale, 6 * scale}
	emitter.useColorRamp = true

	// Fiery blast: White -> Bright Yellow -> Orange -> Smoke
	emitter.colorRamp.count = 4
	emitter.colorRamp.stops[0] = {position = 0.0, color = rl.Color{255, 255, 240, 255}}
	emitter.colorRamp.stops[1] = {position = 0.25, color = rl.Color{255, 215, 0, 255}}
	emitter.colorRamp.stops[2] = {position = 0.65, color = rl.Color{235, 65, 20, 255}}
	emitter.colorRamp.stops[3] = {position = 1.0, color = rl.Color{50, 50, 55, 0}}

	e.ParticleEmitterNode_Start(emitterNode)
}

// ============================================================================
// Battle Level Initialization & Build
// ============================================================================

BattleArenaScene_Build :: proc(scene: ^e.Scene, ctx: ^e.GameContext) {
	if ctx == nil || ctx.game == nil do return
	game := ctx.game

	// 1. Background Starfield Particle Emitter (simulating continuous drifting stars)
	starEmitterNode := e.ParticleEmitterNode_Create(scene, "CosmicStarfield")
	starEmitterNode.position = {640, 360}
	starEmitterNode.layer = .Layer1

	starEmitter := &starEmitterNode.emitter
	starEmitter.amount = 140
	starEmitter.lifetime = 4.0
	starEmitter.velocity = 60.0
	starEmitter.continuous = true
	starEmitter.burst = 0.0
	starEmitter.size = {3, 3}
	starEmitter.useColorRamp = true

	// Deep space star colors: Cyan/White -> Pale Yellow -> Soft Blue
	starEmitter.colorRamp.count = 3
	starEmitter.colorRamp.stops[0] = {position = 0.0, color = rl.Color{200, 235, 255, 180}}
	starEmitter.colorRamp.stops[1] = {position = 0.5, color = rl.Color{255, 255, 255, 255}}
	starEmitter.colorRamp.stops[2] = {position = 1.0, color = rl.Color{160, 190, 240, 0}}
	e.ParticleEmitterNode_Start(starEmitterNode)

	// 2. Player Ship Node (World Layer 3)
	playerShip := e.CreateNodeScene(scene, e.Node, true)
	playerShip.name = "PlayerSpaceship"
	playerShip.position = {640, 360}
	playerShip.layer = .Layer3

	// 3. CameraNode (Smoothly follows player with boundaries and deadzones!)
	cam := e.CameraNode_Create(scene, "BattleCamera", isCurrent = true)
	e.CameraNode_SetTarget(cam, playerShip)
	cam.dragType = .SmoothDamp
	cam.smoothDragSpeed = {0.22, 0.22}
	cam.zoom = 1.0
	cam.targetZoom = 1.0
	e.CameraNode_SetLimits(cam, ARENA_MIN_X, ARENA_MAX_X, ARENA_MIN_Y, ARENA_MAX_Y)
	e.CameraNode_SetDeadzones(cam, left = 0.18, right = 0.18, top = 0.18, bottom = 0.18)

	// 4. Battle Level Manager Node
	battleNode := e.CreateNodeScene(scene, BattleLevelNode, true)
	battleNode.name = "BattleManager"
	battleNode.layer = .Layer3
	battleNode.renderable = true
	battleNode.sceneRef = scene
	battleNode.camera = cam
	battleNode.playerShip = playerShip
	battleNode.playerPos = {640, 360}
	battleNode.playerVel = {0, 0}
	battleNode.playerAngle = 0.0
	battleNode.playerHealth = 100.0
	battleNode.playerMaxHealth = 100.0
	battleNode.playerShield = 100.0
	battleNode.playerMaxShield = 100.0
	battleNode.shieldRegenDelay = 0.0
	battleNode.playerFireTimer = 0.0
	battleNode.score = 0
	battleNode.gameOver = false
	battleNode.victory = false

	// Load Textures via ResourceManager
	rm := &game.resourceManager
	if rl.IsWindowReady() {
		if t, ok := rm->loadTexture("assets/graphics/Ship_01/Ship_LVL_1.png"); ok && t != nil {
			battleNode.texPlayer = t.texture
		}
		if t, ok := rm->loadTexture("assets/graphics/Space Pack/Ships/Spaceship_2.png"); ok && t != nil {
			battleNode.texEnemyScout = t.texture
		}
		if t, ok := rm->loadTexture("assets/graphics/Space Pack/Ships/Spaceship_1.png"); ok && t != nil {
			battleNode.texEnemyFighter = t.texture
		}
		if t, ok := rm->loadTexture("assets/graphics/Ship_02/Ship_LVL_1.png"); ok && t != nil {
			battleNode.texEnemyCruiser = t.texture
		}
		if t, ok := rm->loadTexture("assets/graphics/Space Pack/Turrets/Base_1.png"); ok && t != nil {
			battleNode.texTurretBase = t.texture
		}
		if t, ok := rm->loadTexture("assets/graphics/Space Pack/Turrets/Gun_1.png"); ok && t != nil {
			battleNode.texTurretGun = t.texture
		}
		if t, ok := rm->loadTexture("assets/graphics/Ship_Effects/Laser_1_1.png"); ok && t != nil {
			battleNode.texPlayerLaser = t.texture
		}
		if t, ok := rm->loadTexture("assets/graphics/Ship_Effects/Fire_Shot_1_1.png"); ok && t != nil {
			battleNode.texEnemyLaser = t.texture
		}
		if t, ok := rm->loadTexture("assets/graphics/Ship_Effects/Fire_Shot_2_1.png"); ok && t != nil {
			battleNode.texTurretLaser = t.texture
		}
		if t, ok := rm->loadTexture("assets/graphics/Space Pack/Asteroids/Asteroid_1.png"); ok && t != nil {
			battleNode.texAsteroid1 = t.texture
		}
		if t, ok := rm->loadTexture("assets/graphics/Space Pack/Asteroids/Asteroid_2.png"); ok && t != nil {
			battleNode.texAsteroid2 = t.texture
		}
		if t, ok := rm->loadTexture("assets/graphics/Space Pack/Asteroids/Asteroid_3.png"); ok && t != nil {
			battleNode.texAsteroid3 = t.texture
		}
	}

	// Audio
	if s, ok := rm->loadAudioSound("assets/audio/cannon-gunshot-1.wav"); ok && s != nil {
		battleNode.cannonSound = s
	}

	// 5. Initialize Asteroid Obstacles
	astPositions := [MAX_ASTEROIDS][2]f32{
		{-350, -200}, {1600, -300}, {-400, 1000}, {1700, 1100},
		{640, -550}, {640, 1250}, {-200, 400}, {1500, 400},
	}
	for i in 0..<MAX_ASTEROIDS {
		astTex := battleNode.texAsteroid1
		if i % 3 == 1 do astTex = battleNode.texAsteroid2
		if i % 3 == 2 do astTex = battleNode.texAsteroid3
		battleNode.asteroids[i] = BattleAsteroid{
			position = astPositions[i],
			rotation = f32(i * 45),
			rotSpeed = f32(i % 2 == 0 ? 1 : -1) * f32(15 + i * 5),
			scale    = 0.45 + f32(i % 3) * 0.15,
			radius   = 55.0,
			tex      = astTex,
		}
	}

	// 6. Initialize Enemy Ships
	// Scout (Fast, agile)
	battleNode.enemies[0] = BattleEnemy{
		position = {-150, 150},
		rotation = 90,
		health = 50,
		maxHealth = 50,
		alive = true,
		tex = battleNode.texEnemyScout,
		scale = 0.14,
		speed = 260,
		fireTimer = 1.0,
		fireInterval = 1.6,
		radius = 28.0,
		patrolAnchor = {-150, 150},
		name = "Enemy Scout Alpha",
	}
	battleNode.enemies[1] = BattleEnemy{
		position = {1450, 200},
		rotation = -90,
		health = 50,
		maxHealth = 50,
		alive = true,
		tex = battleNode.texEnemyScout,
		scale = 0.14,
		speed = 260,
		fireTimer = 1.5,
		fireInterval = 1.6,
		radius = 28.0,
		patrolAnchor = {1450, 200},
		name = "Enemy Scout Beta",
	}
	// Fighter (Medium, tactical)
	battleNode.enemies[2] = BattleEnemy{
		position = {200, -450},
		rotation = 180,
		health = 80,
		maxHealth = 80,
		alive = true,
		tex = battleNode.texEnemyFighter,
		scale = 0.15,
		speed = 220,
		fireTimer = 0.8,
		fireInterval = 1.4,
		radius = 32.0,
		patrolAnchor = {200, -450},
		name = "Enemy Fighter Gamma",
	}
	battleNode.enemies[3] = BattleEnemy{
		position = {1100, 950},
		rotation = 0,
		health = 80,
		maxHealth = 80,
		alive = true,
		tex = battleNode.texEnemyFighter,
		scale = 0.15,
		speed = 220,
		fireTimer = 1.2,
		fireInterval = 1.4,
		radius = 32.0,
		patrolAnchor = {1100, 950},
		name = "Enemy Fighter Delta",
	}
	// Cruiser (Heavy flagship)
	battleNode.enemies[4] = BattleEnemy{
		position = {640, -750},
		rotation = 180,
		health = 160,
		maxHealth = 160,
		alive = true,
		tex = battleNode.texEnemyCruiser,
		scale = 0.10,
		speed = 150,
		fireTimer = 0.5,
		fireInterval = 1.1,
		radius = 45.0,
		patrolAnchor = {640, -750},
		name = "Enemy Heavy Cruiser Omega",
	}
	battleNode.enemies[5] = BattleEnemy{
		position = {640, 1400},
		rotation = 0,
		health = 160,
		maxHealth = 160,
		alive = true,
		tex = battleNode.texEnemyCruiser,
		scale = 0.10,
		speed = 150,
		fireTimer = 1.4,
		fireInterval = 1.1,
		radius = 45.0,
		patrolAnchor = {640, 1400},
		name = "Enemy Heavy Cruiser Titan",
	}

	// 7. Initialize Defense Turrets
	turretPositions := [MAX_TURRETS][2]f32{
		{-450, -400},
		{1750, -400},
		{-450, 1150},
		{1750, 1150},
	}
	for i in 0..<MAX_TURRETS {
		battleNode.turrets[i] = BattleTurret{
			position     = turretPositions[i],
			gunRotation  = 0.0,
			health       = 120.0,
			maxHealth    = 120.0,
			alive        = true,
			texBase      = battleNode.texTurretBase,
			texGun       = battleNode.texTurretGun,
			fireTimer    = 0.5 + f32(i) * 0.4,
			fireInterval = 1.5,
			detectRange  = 820.0,
			radius       = 38.0,
		}
	}

	// Hook Lifecycle Procs
	battleNode.update = BattleLevelNode_Update
	battleNode.render = BattleLevelNode_Render
}

// ============================================================================
// Battle Level Update Loop
// ============================================================================

BattleLevelNode_Update :: proc(node: ^e.Node, ctx: ^e.GameContext, deltaTime: f32) {
	b := cast(^BattleLevelNode)node
	if b == nil || !b.enabled do return

	dt := max(0.0001, deltaTime)

	// Return to menu on [M] or Escape
	if rl.IsKeyPressed(.M) || rl.IsKeyPressed(.ESCAPE) {
		if ctx != nil && ctx.game != nil {
			ctx.game->changeScene("title_menu")
			return
		}
	}

	// Restart on [R] if game over or victory
	if (b.gameOver || b.victory) && rl.IsKeyPressed(.R) {
		if ctx != nil && ctx.game != nil {
			ctx.game->changeScene("battle_arena")
			return
		}
	}

	// ------------------------------------------------------------------------
	// 1. Player Controls & Flight Simulation
	// ------------------------------------------------------------------------
	if !b.gameOver {
		axis := [2]f32{0, 0}
		if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP) do axis.y -= 1.0
		if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN) do axis.y += 1.0
		if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) do axis.x -= 1.0
		if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) do axis.x += 1.0

		// Boost speed
		isBoosting := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
		maxSpeed: f32 = isBoosting ? 600.0 : 380.0
		accel: f32 = isBoosting ? 2200.0 : 1400.0

		if axis.x != 0 || axis.y != 0 {
			targetAngle := math.atan2(axis.y, axis.x) * (180.0 / math.PI) + 90.0
			b.playerAngle = e.Camera_SmoothDampAngle(b.playerAngle, targetAngle, &b.node.rotation, 0.08, 1000.0, dt)

			norm := [2]f32{axis.x, axis.y}
			lenAxis := math.sqrt(norm.x * norm.x + norm.y * norm.y)
			if lenAxis > 0.001 do norm /= lenAxis

			b.playerVel += norm * (accel * dt)
			curSpeed := math.sqrt(b.playerVel.x * b.playerVel.x + b.playerVel.y * b.playerVel.y)
			if curSpeed > maxSpeed {
				b.playerVel = (b.playerVel / curSpeed) * maxSpeed
			}
		} else {
			// Passive inertial damping
			b.playerVel *= (1.0 - math.clamp(3.0 * dt, 0.0, 1.0))
		}

		b.playerPos += b.playerVel * dt
		b.playerPos.x = math.clamp(b.playerPos.x, ARENA_MIN_X + 80, ARENA_MAX_X - 80)
		b.playerPos.y = math.clamp(b.playerPos.y, ARENA_MIN_Y + 80, ARENA_MAX_Y - 80)

		if b.playerShip != nil {
			b.playerShip.position = b.playerPos
			b.playerShip.rotation = b.playerAngle
		}

		// Shield Regeneration
		if b.shieldRegenDelay > 0.0 {
			b.shieldRegenDelay -= dt
		} else if b.playerShield < b.playerMaxShield {
			b.playerShield = min(b.playerMaxShield, b.playerShield + 22.0 * dt)
		}

		// --------------------------------------------------------------------
		// 2. Spacebar Weapon Firing
		// --------------------------------------------------------------------
		if b.playerFireTimer > 0.0 {
			b.playerFireTimer -= dt
		}

		if rl.IsKeyDown(.SPACE) && b.playerFireTimer <= 0.0 {
			b.playerFireTimer = 0.16

			// Direction vector from player's facing angle
			rad := (b.playerAngle - 90.0) * (math.PI / 180.0)
			dir := [2]f32{math.cos(rad), math.sin(rad)}
			spawnPt := b.playerPos + dir * 36.0
			bulletVel := dir * 960.0 + b.playerVel * 0.25

			// Spawn bullet in free slot
			for &bullet in b.bullets {
				if !bullet.alive {
					bullet.position = spawnPt
					bullet.velocity = bulletVel
					bullet.rotation = b.playerAngle
					bullet.damage = 25.0
					bullet.lifetime = 1.8
					bullet.isPlayer = true
					bullet.alive = true
					bullet.radius = 12.0
					bullet.tex = b.texPlayerLaser
					break
				}
			}

			// Cannon gunshot sound
			if b.cannonSound != nil && rl.IsAudioDeviceReady() && rl.IsSoundReady(b.cannonSound.sound) {
				rl.PlaySound(b.cannonSound.sound)
			}

			// Gentle recoil screen shake
			if b.camera != nil {
				e.CameraNode_ApplyShakePreset(b.camera, .Gunshot)
			}
		}
	}

	// ------------------------------------------------------------------------
	// 3. Asteroid Rotation
	// ------------------------------------------------------------------------
	for &ast in b.asteroids {
		ast.rotation += ast.rotSpeed * dt
	}

	// ------------------------------------------------------------------------
	// 4. Enemy Ships AI & Weapon Firing
	// ------------------------------------------------------------------------
	activeEnemiesCount := 0
	for &enemy in b.enemies {
		if !enemy.alive do continue
		activeEnemiesCount += 1

		diff := b.playerPos - enemy.position
		dist := math.sqrt(diff.x * diff.x + diff.y * diff.y)

		if !b.gameOver && dist < 1200.0 {
			// Aggro: Rotate towards player
			aimAngle := math.atan2(diff.y, diff.x) * (180.0 / math.PI) + 90.0
			enemy.rotation = e.Camera_SmoothDampAngle(enemy.rotation, aimAngle, &enemy.patrolAngle, 0.12, 1000.0, dt)

			norm := diff / max(0.001, dist)
			if dist > 320.0 {
				enemy.velocity += norm * (400.0 * dt)
			} else if dist < 180.0 {
				enemy.velocity -= norm * (350.0 * dt)
			}
			curSpd := math.sqrt(enemy.velocity.x * enemy.velocity.x + enemy.velocity.y * enemy.velocity.y)
			if curSpd > enemy.speed {
				enemy.velocity = (enemy.velocity / curSpd) * enemy.speed
			}

			// Fire at player
			enemy.fireTimer -= dt
			if enemy.fireTimer <= 0.0 && dist < 750.0 {
				enemy.fireTimer = enemy.fireInterval

				rad := (enemy.rotation - 90.0) * (math.PI / 180.0)
				fwd := [2]f32{math.cos(rad), math.sin(rad)}
				spawnPt := enemy.position + fwd * 30.0

				for &bullet in b.bullets {
					if !bullet.alive {
						bullet.position = spawnPt
						bullet.velocity = fwd * 520.0
						bullet.rotation = enemy.rotation
						bullet.damage = 15.0
						bullet.lifetime = 2.2
						bullet.isPlayer = false
						bullet.alive = true
						bullet.radius = 10.0
						bullet.tex = b.texEnemyLaser
						break
					}
				}
			}
		} else {
			// Idle patrol orbit around anchor
			enemy.patrolAngle += 0.8 * dt
			targetPatrol := enemy.patrolAnchor + [2]f32{math.cos(enemy.patrolAngle) * 120.0, math.sin(enemy.patrolAngle) * 120.0}
			toPatrol := targetPatrol - enemy.position
			enemy.velocity += toPatrol * (2.0 * dt)
			enemy.rotation = math.atan2(enemy.velocity.y, enemy.velocity.x) * (180.0 / math.PI) + 90.0
		}

		enemy.position += enemy.velocity * dt
		enemy.position.x = math.clamp(enemy.position.x, ARENA_MIN_X + 80, ARENA_MAX_X - 80)
		enemy.position.y = math.clamp(enemy.position.y, ARENA_MIN_Y + 80, ARENA_MAX_Y - 80)
	}

	// ------------------------------------------------------------------------
	// 5. Turrets AI & Weapon Firing
	// ------------------------------------------------------------------------
	activeTurretsCount := 0
	for &turret in b.turrets {
		if !turret.alive do continue
		activeTurretsCount += 1

		diff := b.playerPos - turret.position
		dist := math.sqrt(diff.x * diff.x + diff.y * diff.y)

		if !b.gameOver && dist <= turret.detectRange {
			aimAngle := math.atan2(diff.y, diff.x) * (180.0 / math.PI)
			turret.gunRotation = aimAngle

			turret.fireTimer -= dt
			if turret.fireTimer <= 0.0 {
				turret.fireTimer = turret.fireInterval

				rad := turret.gunRotation * (math.PI / 180.0)
				fwd := [2]f32{math.cos(rad), math.sin(rad)}
				spawnPt := turret.position + fwd * 38.0

				for &bullet in b.bullets {
					if !bullet.alive {
						bullet.position = spawnPt
						bullet.velocity = fwd * 460.0
						bullet.rotation = turret.gunRotation + 90.0
						bullet.damage = 20.0
						bullet.lifetime = 2.4
						bullet.isPlayer = false
						bullet.alive = true
						bullet.radius = 12.0
						bullet.tex = b.texTurretLaser
						break
					}
				}
			}
		}
	}

	// ------------------------------------------------------------------------
	// 6. Projectiles Simulation & Hit Registration
	// ------------------------------------------------------------------------
	for &bullet in b.bullets {
		if !bullet.alive do continue

		bullet.position += bullet.velocity * dt
		bullet.lifetime -= dt
		if bullet.lifetime <= 0.0 {
			bullet.alive = false
			continue
		}

		// Player bullet hitting enemies or turrets
		if bullet.isPlayer {
			hit := false
			// Check against enemy ships
			for &enemy in b.enemies {
				if !enemy.alive do continue
				diff := bullet.position - enemy.position
				if (diff.x * diff.x + diff.y * diff.y) <= (bullet.radius + enemy.radius) * (bullet.radius + enemy.radius) {
					bullet.alive = false
					hit = true
					enemy.health -= bullet.damage
					if enemy.health <= 0.0 {
						enemy.alive = false
						enemy.health = 0.0
						b.score += 100
						SpawnBattleExplosion(b.sceneRef, enemy.position, 1.2)
						if b.camera != nil {
							e.CameraNode_ApplyShakePreset(b.camera, .Explosion)
						}
					}
					break
				}
			}
			if hit do continue

			// Check against turrets
			for &turret in b.turrets {
				if !turret.alive do continue
				diff := bullet.position - turret.position
				if (diff.x * diff.x + diff.y * diff.y) <= (bullet.radius + turret.radius) * (bullet.radius + turret.radius) {
					bullet.alive = false
					turret.health -= bullet.damage
					if turret.health <= 0.0 {
						turret.alive = false
						turret.health = 0.0
						b.score += 150
						SpawnBattleExplosion(b.sceneRef, turret.position, 1.4)
						if b.camera != nil {
							e.CameraNode_ApplyShakePreset(b.camera, .Explosion)
						}
					}
					break
				}
			}
		} else {
			// Enemy / Turret bullet hitting player
			if !b.gameOver {
				diff := bullet.position - b.playerPos
				if (diff.x * diff.x + diff.y * diff.y) <= (bullet.radius + 28.0) * (bullet.radius + 28.0) {
					bullet.alive = false
					b.shieldRegenDelay = 3.0

					if b.playerShield > 0.0 {
						absorbed := min(b.playerShield, bullet.damage)
						b.playerShield -= absorbed
						remDamage := bullet.damage - absorbed
						b.playerHealth = max(0.0, b.playerHealth - remDamage)
					} else {
						b.playerHealth = max(0.0, b.playerHealth - bullet.damage)
					}

					if b.camera != nil {
						e.CameraNode_ApplyShakePreset(b.camera, .Impact)
					}

					if b.playerHealth <= 0.0 {
						b.playerHealth = 0.0
						b.gameOver = true
						SpawnBattleExplosion(b.sceneRef, b.playerPos, 1.8)
						if b.camera != nil {
							e.CameraNode_ApplyShakePreset(b.camera, .Explosion)
						}
					}
				}
			}
		}
	}

	// Check victory condition
	if !b.gameOver && activeEnemiesCount == 0 && activeTurretsCount == 0 {
		b.victory = true
	}
}

// ============================================================================
// Battle Level Render Loop
// ============================================================================

BattleLevelNode_Render :: proc(node: ^e.Node, ctx: ^e.GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	b := cast(^BattleLevelNode)node
	if b == nil || !b.renderable do return

	// ------------------------------------------------------------------------
	// A. World Space Rendering (Layer 2 - Layer 4)
	// (Under camera transform)
	// ------------------------------------------------------------------------

	// 1. Arena Boundary Grid
	rl.DrawRectangleLinesEx(
		rl.Rectangle{
			x      = ARENA_MIN_X,
			y      = ARENA_MIN_Y,
			width  = ARENA_MAX_X - ARENA_MIN_X,
			height = ARENA_MAX_Y - ARENA_MIN_Y,
		},
		4.0,
		rl.Color{30, 58, 90, 180},
	)

	// 2. Render Asteroids
	for ast in b.asteroids {
		if ast.tex.id > 0 {
			src := rl.Rectangle{0, 0, f32(ast.tex.width), f32(ast.tex.height)}
			destW := f32(ast.tex.width) * ast.scale
			destH := f32(ast.tex.height) * ast.scale
			dest := rl.Rectangle{ast.position.x, ast.position.y, destW, destH}
			origin := [2]f32{destW * 0.5, destH * 0.5}
			rl.DrawTexturePro(ast.tex, src, dest, origin, ast.rotation, rl.WHITE)
		} else {
			rl.DrawCircleV(ast.position, ast.radius, rl.Color{90, 85, 95, 255})
		}
	}

	// 3. Render Turrets (Base + Rotating Gun + Health Bar)
	for turret in b.turrets {
		if !turret.alive do continue

		// Base
		if turret.texBase.id > 0 {
			src := rl.Rectangle{0, 0, f32(turret.texBase.width), f32(turret.texBase.height)}
			destW := f32(turret.texBase.width) * 0.18
			destH := f32(turret.texBase.height) * 0.18
			dest := rl.Rectangle{turret.position.x, turret.position.y, destW, destH}
			rl.DrawTexturePro(turret.texBase, src, dest, {destW * 0.5, destH * 0.5}, 0.0, rl.WHITE)
		} else {
			rl.DrawCircleV(turret.position, turret.radius, rl.Color{55, 65, 80, 255})
		}

		// Gun barrel
		if turret.texGun.id > 0 {
			src := rl.Rectangle{0, 0, f32(turret.texGun.width), f32(turret.texGun.height)}
			destW := f32(turret.texGun.width) * 0.18
			destH := f32(turret.texGun.height) * 0.18
			dest := rl.Rectangle{turret.position.x, turret.position.y, destW, destH}
			// Gun pivots from base center
			rl.DrawTexturePro(turret.texGun, src, dest, {destW * 0.25, destH * 0.5}, turret.gunRotation, rl.WHITE)
		} else {
			gunRad := turret.gunRotation * (math.PI / 180.0)
			gunEnd := turret.position + [2]f32{math.cos(gunRad) * 40.0, math.sin(gunRad) * 40.0}
			rl.DrawLineEx(turret.position, gunEnd, 6.0, rl.Color{200, 70, 60, 255})
		}

		// Floating Health Bar over Turret
		barW: f32 = 52.0
		barH: f32 = 6.0
		barX := turret.position.x - barW * 0.5
		barY := turret.position.y - turret.radius - 16.0
		fillPct := math.clamp(turret.health / turret.maxHealth, 0.0, 1.0)

		rl.DrawRectangleRec(rl.Rectangle{barX - 1, barY - 1, barW + 2, barH + 2}, rl.Color{20, 22, 28, 220})
		rl.DrawRectangleRec(rl.Rectangle{barX, barY, barW * fillPct, barH}, rl.Color{248, 113, 113, 255})
		rl.DrawRectangleLinesEx(rl.Rectangle{barX - 1, barY - 1, barW + 2, barH + 2}, 1.0, rl.Color{90, 95, 110, 255})
	}

	// 4. Render Enemy Ships (Ship Sprite + Floating Health Bar)
	for enemy in b.enemies {
		if !enemy.alive do continue

		if enemy.tex.id > 0 {
			src := rl.Rectangle{0, 0, f32(enemy.tex.width), f32(enemy.tex.height)}
			destW := f32(enemy.tex.width) * enemy.scale
			destH := f32(enemy.tex.height) * enemy.scale
			dest := rl.Rectangle{enemy.position.x, enemy.position.y, destW, destH}
			rl.DrawTexturePro(enemy.tex, src, dest, {destW * 0.5, destH * 0.5}, enemy.rotation, rl.WHITE)
		} else {
			rl.DrawCircleV(enemy.position, enemy.radius, rl.Color{220, 38, 38, 255})
		}

		// Floating Health Bar over Enemy
		barW: f32 = 46.0
		barH: f32 = 5.0
		barX := enemy.position.x - barW * 0.5
		barY := enemy.position.y - enemy.radius - 14.0
		fillPct := math.clamp(enemy.health / enemy.maxHealth, 0.0, 1.0)

		barColor := rl.Color{52, 211, 153, 255}
		if fillPct < 0.35 {
			barColor = rl.Color{239, 68, 68, 255}
		} else if fillPct < 0.65 {
			barColor = rl.Color{251, 191, 36, 255}
		}

		rl.DrawRectangleRec(rl.Rectangle{barX - 1, barY - 1, barW + 2, barH + 2}, rl.Color{18, 20, 26, 220})
		rl.DrawRectangleRec(rl.Rectangle{barX, barY, barW * fillPct, barH}, barColor)
		rl.DrawRectangleLinesEx(rl.Rectangle{barX - 1, barY - 1, barW + 2, barH + 2}, 1.0, rl.Color{75, 85, 100, 255})
	}

	// 5. Render Projectiles
	for bullet in b.bullets {
		if !bullet.alive do continue

		if bullet.tex.id > 0 {
			src := rl.Rectangle{0, 0, f32(bullet.tex.width), f32(bullet.tex.height)}
			scale: f32 = bullet.isPlayer ? 0.25 : 0.20
			destW := f32(bullet.tex.width) * scale
			destH := f32(bullet.tex.height) * scale
			dest := rl.Rectangle{bullet.position.x, bullet.position.y, destW, destH}
			rl.DrawTexturePro(bullet.tex, src, dest, {destW * 0.5, destH * 0.5}, bullet.rotation, rl.WHITE)
		} else {
			col := bullet.isPlayer ? rl.Color{56, 189, 248, 255} : rl.Color{248, 113, 113, 255}
			rl.DrawCircleV(bullet.position, bullet.radius, col)
		}
	}

	// 6. Render Player Ship (if alive)
	if !b.gameOver {
		if b.texPlayer.id > 0 {
			src := rl.Rectangle{0, 0, f32(b.texPlayer.width), f32(b.texPlayer.height)}
			destW := f32(b.texPlayer.width) * 0.08
			destH := f32(b.texPlayer.height) * 0.08
			dest := rl.Rectangle{b.playerPos.x, b.playerPos.y, destW, destH}
			rl.DrawTexturePro(b.texPlayer, src, dest, {destW * 0.5, destH * 0.5}, b.playerAngle, rl.WHITE)
		} else {
			rl.DrawCircleV(b.playerPos, 24.0, rl.Color{59, 130, 246, 255})
		}

		// Shield Aura (translucent blue bubble around player when shield is active)
		if b.playerShield > 0.0 {
			shieldAlpha := u8(math.clamp((b.playerShield / b.playerMaxShield) * 90.0 + 30.0, 30.0, 120.0))
			rl.DrawCircleLines(i32(b.playerPos.x), i32(b.playerPos.y), 36.0, rl.Color{34, 211, 238, shieldAlpha})
		}
	}

	// ------------------------------------------------------------------------
	// B. Screen Space HUD Rendering (Layer 8)
	// (Always pinned to viewport, unaffected by camera zoom/pan)
	// ------------------------------------------------------------------------

	// 1. Top-Left Vital Status Card (Hull & Shield Bars)
	hudCard := rl.Rectangle{x = 24, y = 20, width = 290, height = 95}
	rl.DrawRectangleRec(hudCard, rl.Color{14, 18, 26, 220})
	rl.DrawRectangleLinesEx(hudCard, 1.5, rl.Color{40, 60, 90, 255})

	// Shield Bar
	shieldPct := math.clamp(b.playerShield / b.playerMaxShield, 0.0, 1.0)
	shieldBarRect := rl.Rectangle{x = 36, y = 46, width = 266, height = 14}
	rl.DrawRectangleRec(shieldBarRect, rl.Color{22, 30, 44, 255})
	rl.DrawRectangleRec(
		rl.Rectangle{x = shieldBarRect.x, y = shieldBarRect.y, width = shieldBarRect.width * shieldPct, height = shieldBarRect.height},
		rl.Color{34, 211, 238, 255},
	)
	rl.DrawRectangleLinesEx(shieldBarRect, 1.0, rl.Color{6, 182, 212, 180})

	shieldText := fmt.ctprintf("SHIELD: %d / %d", i32(b.playerShield), i32(b.playerMaxShield))
	e.DrawEngineText(shieldText, 36, 28, 12, rl.Color{165, 243, 252, 255})
	if b.shieldRegenDelay <= 0.0 && b.playerShield < b.playerMaxShield {
		e.DrawEngineText("[RECHARGING]", 215, 28, 11, rl.Color{103, 232, 249, 255})
	}

	// Hull (Health) Bar
	healthPct := math.clamp(b.playerHealth / b.playerMaxHealth, 0.0, 1.0)
	healthBarRect := rl.Rectangle{x = 36, y = 88, width = 266, height = 14}
	hullColor := rl.Color{52, 211, 153, 255}
	if healthPct < 0.35 {
		hullColor = rl.Color{239, 68, 68, 255}
	} else if healthPct < 0.65 {
		hullColor = rl.Color{251, 191, 36, 255}
	}

	rl.DrawRectangleRec(healthBarRect, rl.Color{22, 30, 44, 255})
	rl.DrawRectangleRec(
		rl.Rectangle{x = healthBarRect.x, y = healthBarRect.y, width = healthBarRect.width * healthPct, height = healthBarRect.height},
		hullColor,
	)
	rl.DrawRectangleLinesEx(healthBarRect, 1.0, rl.Color{16, 185, 129, 180})

	healthText := fmt.ctprintf("HULL: %d / %d", i32(b.playerHealth), i32(b.playerMaxHealth))
	e.DrawEngineText(healthText, 36, 70, 12, rl.Color{209, 250, 229, 255})

	// 2. Top-Right Mission Intel & Targets Card
	intelCard := rl.Rectangle{x = 970, y = 20, width = 286, height = 80}
	rl.DrawRectangleRec(intelCard, rl.Color{14, 18, 26, 220})
	rl.DrawRectangleLinesEx(intelCard, 1.5, rl.Color{40, 60, 90, 255})

	aliveEnemies := 0
	for enemy in b.enemies do if enemy.alive do aliveEnemies += 1
	aliveTurrets := 0
	for turret in b.turrets do if turret.alive do aliveTurrets += 1
	totalTargets := aliveEnemies + aliveTurrets

	targetsText := fmt.ctprintf("TARGETS: %d (Enemies: %d | Turrets: %d)", totalTargets, aliveEnemies, aliveTurrets)
	e.DrawEngineText(targetsText, 982, 30, 13, rl.Color{253, 224, 71, 255})

	scoreText := fmt.ctprintf("SCORE: %d", b.score)
	e.DrawEngineText(scoreText, 982, 54, 18, rl.Color{255, 255, 255, 255})

	// 3. Return to Menu Button & Navigation Hint
	menuBtnRect := rl.Rectangle{x = 1080, y = 110, width = 176, height = 32}
	mousePos := rl.GetMousePosition()
	isHover := rl.CheckCollisionPointRec(mousePos, menuBtnRect)
	btnCol := isHover ? rl.Color{45, 65, 100, 240} : rl.Color{25, 35, 55, 220}
	rl.DrawRectangleRec(menuBtnRect, btnCol)
	rl.DrawRectangleLinesEx(menuBtnRect, 1.2, rl.Color{80, 110, 160, 255})
	e.DrawEngineText("[M] TITLE MENU", 1104, 118, 13, rl.Color{220, 230, 250, 255})

	if isHover && rl.IsMouseButtonPressed(.LEFT) {
		if ctx != nil && ctx.game != nil {
			ctx.game->changeScene("title_menu")
		}
	}

	// 4. Bottom Controls Helper Banner
	ctrlCard := rl.Rectangle{x = 340, y = 675, width = 600, height = 32}
	rl.DrawRectangleRec(ctrlCard, rl.Color{10, 14, 20, 200})
	rl.DrawRectangleLinesEx(ctrlCard, 1.0, rl.Color{35, 50, 75, 200})
	e.DrawEngineText("[WASD / ARROWS] Fly  |  [SPACE] Fire Lasers  |  [LSHIFT] Boost Engine  |  [M] Menu", 365, 683, 12, rl.Color{170, 185, 210, 255})

	// 5. Victory or Game Over Overlay Banner
	if b.victory {
		banner := rl.Rectangle{x = 340, y = 280, width = 600, height = 160}
		rl.DrawRectangleRec(banner, rl.Color{12, 28, 20, 240})
		rl.DrawRectangleLinesEx(banner, 2.5, rl.Color{16, 185, 129, 255})
		e.DrawEngineText("VICTORY - SECTOR SECURED!", 420, 310, 26, rl.Color{52, 211, 153, 255})
		finalScore := fmt.ctprintf("All hostile fleets eliminated! Final Score: %d", b.score)
		e.DrawEngineText(finalScore, 430, 355, 15, rl.Color{209, 250, 229, 255})
		e.DrawEngineText("Press [R] to Play Again  |  [M] Return to Title Deck", 435, 395, 13, rl.Color{110, 231, 183, 255})
	} else if b.gameOver {
		banner := rl.Rectangle{x = 340, y = 280, width = 600, height = 160}
		rl.DrawRectangleRec(banner, rl.Color{32, 12, 16, 240})
		rl.DrawRectangleLinesEx(banner, 2.5, rl.Color{239, 68, 68, 255})
		e.DrawEngineText("HULL CRITICAL - SHIP DESTROYED", 380, 310, 25, rl.Color{248, 113, 113, 255})
		e.DrawEngineText("Your spaceship was obliterated in combat.", 470, 355, 15, rl.Color{254, 202, 202, 255})
		e.DrawEngineText("Press [R] to Respawn  |  [M] Return to Title Deck", 440, 395, 13, rl.Color{252, 165, 165, 255})
	}
}
