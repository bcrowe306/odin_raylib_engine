package engine

import "core:math"
import "core:testing"
import rl "vendor:raylib"

// #129: GPU mode's maths (ParticleGPU_Evaluate: the vertex shader's
// formulas on the CPU) agree with the CPU simulation, with the same seed.

@(private = "file")
gpu_pair :: proc(gpu: bool, setup: proc(e: ^ParticleEmitter)) -> ParticleEmitter {
	e: ParticleEmitter
	ParticleEmitter_Init(&e)
	e.seed, e.amount, e.burst, e.continuous, e.lifetime = 7, 20, 1, false, 3
	e.spread, e.velocity, e.velocityVariance, e.velocitySpread = {30, 10}, 120, 1, 60
	e.angle, e.angleSpread, e.angleVariance = -60, 40, 1
	e.gpu = gpu
	setup(&e)
	ParticleEmitter_Start(&e)
	return e
}

@(private = "file")
agree :: proc(t: ^testing.T, name: string, setup: proc(e: ^ParticleEmitter)) {
	cpu := gpu_pair(false, setup)
	gpu := gpu_pair(true, setup)
	defer {ParticleEmitter_Destroy(&cpu); ParticleEmitter_Destroy(&gpu)}
	DT :: f32(1.0 / 240)
	for _ in 0 ..< 240 { // one second
		ParticleEmitter_Update(&cpu, DT)
		ParticleEmitter_Update(&gpu, DT)
	}
	testing.expectf(t, gpu.aliveCount == cpu.aliveCount && cpu.aliveCount == 20, "%s: alive %v / %v", name, gpu.aliveCount, cpu.aliveCount)
	worst: f32
	for i in 0 ..< 20 {
		c := cpu.particles[i]
		s := ParticleGPU_Evaluate(&gpu, gpu.gpuData.records[i], gpu.gpuData.clock)
		if !testing.expectf(t, s.alive, "%s: %d alive on the GPU", name, i) do return
		w := particle_to_world(&cpu, c.position) if cpu.localSpace else c.position
		d := s.position - w
		worst = max(worst, math.sqrt(d.x * d.x + d.y * d.y))
		testing.expectf(t, abs(s.scale.x - c.scale.x) < 0.02, "%s: scale %v / %v", name, s.scale, c.scale)
		testing.expectf(t, abs(i32(s.color.a) - i32(c.color.a)) <= 2 && abs(i32(s.color.r) - i32(c.color.r)) <= 2, "%s: colour %v / %v", name, s.color, c.color)
	}
	// (The CPU steps: semi-implicit Euler at 1/240 s, so a fraction of a pixel apart.)
	testing.expectf(t, worst < 1.5, "%s: positions within 1.5 px (worst %v)", name, worst)
}

@(test)
test_particle_gpu_matches_cpu :: proc(t: ^testing.T) {
	agree(t, "gravity", proc(e: ^ParticleEmitter) {})
	agree(t, "wind + damping", proc(e: ^ParticleEmitter) {e.wind, e.damping = {40, -20}, 1.5})
	agree(t, "acceleration", proc(e: ^ParticleEmitter) {e.acceleration, e.gravityVelocity = 80, 0})
	agree(t, "curves + scale", proc(e: ^ParticleEmitter) {
		e.scaleStart, e.scaleEnd = {1, 1}, {0.2, 0.2}
		e.alphaCurve = {count = 2}
		e.alphaCurve.points[0], e.alphaCurve.points[1] = {0, 1}, {1, 0}
	})
	agree(t, "local, turned and scaled", proc(e: ^ParticleEmitter) {
		e.position, e.originRotation, e.originScale = {300, 200}, 30, {0.5, 0.5}
	})
	agree(t, "world", proc(e: ^ParticleEmitter) {e.localSpace = false; e.position = {-400, 50}})
}

@(test)
test_particle_gpu_records :: proc(t: ^testing.T) {
	e: ParticleEmitter
	ParticleEmitter_Init(&e)
	defer ParticleEmitter_Destroy(&e)
	e.gpu, e.amount, e.lifetime = true, 100000, 1 // (past the CPU ring's 20000)
	ParticleEmitter_Update(&e, 0.5)
	testing.expectf(t, e.aliveCount > 20000, "GPU emitters go past the CPU cap: %v alive", e.aliveCount)
	testing.expect_value(t, len(e.particles), 0) // (no CPU particles)
	ParticleEmitter_Restart(&e)
	testing.expect_value(t, ParticleGPU_AliveCount(&e), 0)
	// Back to CPU mode: the GPU's particles go.
	ParticleEmitter_Update(&e, 0.1)
	e.gpu = false
	ParticleEmitter_Update(&e, 0.0001)
	testing.expect_value(t, ParticleGPU_AliveCount(&e), 0)
}

// The shader's matrix under a moved camera (the editor's viewport): the
// camera's target lands in the middle of the view, not off-screen.
@(test)
test_particle_gpu_mvp :: proc(t: ^testing.T) {
	cam := rl.Camera2D{offset = {400, 300}, target = {640, 352}, zoom = 1}
	proj := rl.MatrixOrtho(0, 800, 600, 0, 0, 1)
	mvp := ParticleGPU_MVP(rl.GetCameraMatrix2D(cam), proj)
	clip := mvp * [4]f32{640, 352, 0, 1}
	testing.expectf(t, abs(clip.x) < 0.001 && abs(clip.y) < 0.001, "the target in the middle: %v", clip)
	corner := mvp * [4]f32{640 - 400, 352 - 300, 0, 1}
	testing.expectf(t, abs(corner.x + 1) < 0.001 && abs(corner.y - 1) < 0.001, "the view's top left: %v", corner)
}
