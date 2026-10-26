package engine

import "core:math"
import os "osx"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// Cached vector meshes and drawing them (vector_tess.odin makes them).
//
// A Vector_Cache holds one tessellation of some shapes for a scale bucket
// (powers of two of the screen-pixel size): moving, rotating and scaling
// within the bucket only changes the transform; zooming past it
// re-tessellates (so curves stay smooth and fringes one pixel wide).
//
// Two ways to draw (Vector_Draw_Mode; RAYZR_VECTOR_MODE=immediate|gpu
// overrides it for benchmarks):
//   .GPU        the mesh is uploaded once (vertex buffers, split at 65535
//               vertices) and drawn with a matrix: no per-frame vertex work
//   .Immediate  the triangles go through raylib's batch every frame
//               (rlgl: transformed on the CPU)
// Both work wherever raylib draws: the game, the editor's viewport, render
// textures and the web (WebGL 2).
// ============================================================================

Vector_Draw_Mode :: enum u8 {
	GPU,
	Immediate,
}

vectorDrawMode: Vector_Draw_Mode = .GPU

@(private = "file")
vector_mode_checked: bool

Vector_DrawModeNow :: proc() -> Vector_Draw_Mode {
	if !vector_mode_checked {
		vector_mode_checked = true
		switch os.get_env("RAYZR_VECTOR_MODE", context.temp_allocator) {
		case "immediate": vectorDrawMode = .Immediate
		case "gpu": vectorDrawMode = .GPU
		}
	}
	return vectorDrawMode
}

Vector_Cache :: struct {
	mesh:     Vector_Mesh,
	gpu:      [dynamic]rl.Mesh,
	bucket:   f32, // the screen-pixel size it was tessellated for (0: never)
	dirty:    bool,
	uploaded: bool,
	stats:    struct {tessellations: int},
}

@(private = "file")
vectorMaterial: rl.Material
@(private = "file")
vectorMaterialReady: bool

// Vector_Cache_Destroy frees the mesh and its GPU buffers.
Vector_Cache_Destroy :: proc(c: ^Vector_Cache) {
	vector_cache_unload(c)
	delete(c.gpu)
	Vector_Mesh_Destroy(&c.mesh)
	c^ = {}
}

@(private = "file")
vector_cache_unload :: proc(c: ^Vector_Cache) {
	for &m in c.gpu {
		if rl.IsWindowReady() do rl.UnloadMesh(m)
		else {
			// (No GL context: only the CPU copies.)
			free_mesh_cpu(&m)
		}
	}
	clear(&c.gpu)
	c.uploaded = false
}

@(private = "file")
free_mesh_cpu :: proc(m: ^rl.Mesh) {
	rl.MemFree(m.vertices)
	rl.MemFree(m.colors)
	rl.MemFree(m.indices)
	m^ = {}
}

// Vector_PixelBucket: the screen-pixel size rounded to a power of two.
Vector_PixelBucket :: proc(pixel: f32) -> f32 {
	return math.pow(2, math.round(math.log2(max(pixel, 1e-4))))
}

// Vector_Cache_Ensure (re)tessellates when the shapes changed (dirty) or the
// drawing scale left the bucket; then uploads for GPU drawing.
Vector_Cache_Ensure :: proc(c: ^Vector_Cache, t: ^Vector_Tess, shapes: []Vector_Shape, pixel: f32) {
	b := Vector_PixelBucket(pixel)
	if c.dirty || c.bucket != b {
		Vector_Tessellate(t, shapes, b, &c.mesh)
		c.bucket = b
		c.dirty = false
		c.stats.tessellations += 1
		vector_cache_unload(c)
	}
	if Vector_DrawModeNow() == .GPU && !c.uploaded && rl.IsWindowReady() do vector_cache_upload(c)
}

// vector_cache_upload: the mesh as raylib meshes of at most 65535 vertices
// (16-bit indices). Triangles never straddle chunks: a chunk takes whole
// triangles and copies the vertices they use.
@(private = "file")
vector_cache_upload :: proc(c: ^Vector_Cache) {
	m := &c.mesh
	if len(m.idx) == 0 {c.uploaded = true; return}
	remap := make([]i32, len(m.verts), context.temp_allocator)
	tri := 0
	ntri := len(m.idx) / 3
	for tri < ntri {
		for &r in remap do r = -1
		verts := make([dynamic][3]f32, context.temp_allocator)
		cols := make([dynamic][4]u8, context.temp_allocator)
		idx := make([dynamic]u16, context.temp_allocator)
		for tri < ntri {
			if len(verts) + 3 > 65535 do break
			for k in 0 ..< 3 {
				v := m.idx[tri * 3 + k]
				if remap[v] < 0 {
					remap[v] = i32(len(verts))
					append(&verts, [3]f32{m.verts[v].x, m.verts[v].y, 0})
					append(&cols, m.cols[v])
				}
				append(&idx, u16(remap[v]))
			}
			tri += 1
		}
		mesh: rl.Mesh
		mesh.vertexCount = i32(len(verts))
		mesh.triangleCount = i32(len(idx) / 3)
		mesh.vertices = cast([^]f32)rl.MemAlloc(u32(len(verts) * 12))
		mesh.colors = cast([^]u8)rl.MemAlloc(u32(len(cols) * 4))
		mesh.indices = cast([^]u16)rl.MemAlloc(u32(len(idx) * 2))
		copy((cast([^][3]f32)mesh.vertices)[:len(verts)], verts[:])
		copy((cast([^][4]u8)mesh.colors)[:len(cols)], cols[:])
		copy(mesh.indices[:len(idx)], idx[:])
		rl.UploadMesh(&mesh, false)
		append(&c.gpu, mesh)
	}
	c.uploaded = true
}

// Vector_ScreenPixel: the size of a screen pixel in a node's local units now
// (the current camera / viewport transform times the node's scale).
Vector_ScreenPixel :: proc(nodeScale: [2]f32) -> f32 {
	mv := rlgl.GetMatrixModelview()
	sx := math.sqrt(mv[0, 0] * mv[0, 0] + mv[1, 0] * mv[1, 0])
	s := sx * max(abs(nodeScale.x), abs(nodeScale.y))
	return 1 / max(s, 1e-4)
}

// Vector_Cache_Draw draws the cached mesh at a transform (degrees), tinted.
Vector_Cache_Draw :: proc(c: ^Vector_Cache, pos: [2]f32, rotation: f32, scale: [2]f32, tint: rl.Color = rl.WHITE) {
	if !rl.IsWindowReady() || len(c.mesh.idx) == 0 do return
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling() // (the tessellator doesn't keep one winding)
	defer {
		rlgl.DrawRenderBatchActive()
		rlgl.EnableBackfaceCulling()
	}
	if Vector_DrawModeNow() == .GPU && c.uploaded {
		if !vectorMaterialReady {
			vectorMaterial = rl.LoadMaterialDefault()
			vectorMaterialReady = true
		}
		vectorMaterial.maps[rl.MaterialMapIndex.ALBEDO].color = tint
		xf := rl.MatrixTranslate(pos.x, pos.y, 0) * rl.MatrixRotateZ(rotation * rl.DEG2RAD) * rl.MatrixScale(scale.x, scale.y, 1)
		for m in c.gpu do rl.DrawMesh(m, vectorMaterial, xf)
		return
	}
	rlgl.PushMatrix()
	rlgl.Translatef(pos.x, pos.y, 0)
	rlgl.Rotatef(rotation, 0, 0, 1)
	rlgl.Scalef(scale.x, scale.y, 1)
	rlgl.Begin(rlgl.TRIANGLES)
	tr, tg, tb, ta := u32(tint.r), u32(tint.g), u32(tint.b), u32(tint.a)
	m := &c.mesh
	for i := 0; i < len(m.idx); i += 3 {
		_ = rlgl.CheckRenderBatchLimit(3) // (flushes when full; raylib keeps the mode)
		for k in 0 ..< 3 {
			v := m.idx[i + k]
			col := m.cols[v]
			rlgl.Color4ub(u8(u32(col.r) * tr / 255), u8(u32(col.g) * tg / 255), u8(u32(col.b) * tb / 255), u8(u32(col.a) * ta / 255))
			rlgl.Vertex2f(m.verts[v].x, m.verts[v].y)
		}
	}
	rlgl.End()
	rlgl.PopMatrix()
}
