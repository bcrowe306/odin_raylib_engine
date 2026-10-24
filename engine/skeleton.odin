package engine

import "base:runtime"
import "core:math"
import "core:slice"
import "core:strings"
import vmem "core:mem/virtual"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// Skeletal (cutout) animation runtime (docs/skeletal_animation.md). A
// Skeleton_Data is the shared, read-only description loaded from a Spine
// or DragonBones export (skeleton_spine.odin / skeleton_dragonbones.odin):
//
//   bones        a tree; each with a setup (rest) transform in its parent's
//                space: x, y, rotation (degrees, clockwise - screen space,
//                y down), scale, shear, and its length
//   slots        what is drawn, in draw order: a bone, a colour and the
//                attachment showing now
//   skins        attachment sets per slot: regions (a textured quad) and
//                meshes (textured triangles; weighted meshes bend with
//                several bones)
//   animations   timelines per bone (rotate, translate, scale, shear) with
//                curves (linear, stepped, Bezier), per slot (attachment,
//                colour), draw order and events
//   ik           one- or two-bone constraints reaching for a target bone
//
// A Skeleton_Pose is one instance's state: the bones' local values (setup
// + animation), their world transforms, the slots' current attachment and
// colour. Data lives in one arena (freed with the data); poses are small
// arrays owned by their node.
// ============================================================================

Skel_Curve_Kind :: enum u8 {Linear, Stepped, Bezier}

Skel_Curve :: struct {
	kind: Skel_Curve_Kind,
	c:    [4]f32, // Bezier (normalized: time and value 0..1 between the keys)
}

Skel_Key :: struct {
	time:  f32,
	v:     [4]f32, // rotate: [0]; translate / scale / shear: [0..1]; colour: rgba 0..1
	curve: Skel_Curve,
	name:  string, // attachment keys: the attachment ("" = none); event keys: the event
	order: []int,  // draw order keys: slot indices front to back (nil = setup order)
	ivalue: i32,   // event keys: their int
	fvalue: f32,   // event keys: their float
	svalue: string,
}

Skel_Timeline_Kind :: enum u8 {Rotate, Translate, Scale, Shear, Attachment, Color}

Skel_Timeline :: struct {
	kind:   Skel_Timeline_Kind,
	target: int, // bone or slot index
	keys:   []Skel_Key,
}

Skel_Animation :: struct {
	name:      string,
	duration:  f32,
	timelines: []Skel_Timeline,
	drawOrder: []Skel_Key,
	events:    []Skel_Key,
}

Skel_Bone :: struct {
	name:     string,
	parent:   int, // -1 = root
	x, y:     f32,
	rotation: f32,
	scaleX, scaleY: f32,
	shearX, shearY: f32,
	length:   f32,
	inheritRotation, inheritScale: bool,
}

Skel_Slot :: struct {
	name:       string,
	bone:       int,
	color:      [4]f32,
	attachment: string, // setup attachment ("" = none)
	additive:   bool,   // blend mode "additive"
}

Skel_Region :: struct {
	texture:   ^Texture,
	uv:        rl.Rectangle, // the region in its page (px; rotated regions are stored rotated)
	rotated:   bool,         // packed rotated 90 degrees in the atlas
	x, y:      f32,          // offset in the bone's space
	rotation:  f32,
	scaleX, scaleY: f32,
	width, height:  f32,
}

Skel_Mesh :: struct {
	texture:   ^Texture,
	uv:        rl.Rectangle, // its region in the page
	rotated:   bool,
	uvs:       [][2]f32,     // 0..1 within the region
	triangles: []u16,
	vertices:  [][2]f32,     // unweighted: in the slot's bone space
	// Weighted: per vertex, its bones (indices into bones / offsets / weights).
	bonesOf:   [][]int,
	offsets:   [][][2]f32,
	weights:   [][]f32,
}

Skel_Attachment :: union {Skel_Region, Skel_Mesh}

Skel_Skin :: struct {
	name:        string,
	attachments: map[string]Skel_Attachment, // "slotIndex/attachmentName"
}

Skel_IK :: struct {
	name:         string,
	bones:        []int, // 1 or 2 (parent, child)
	target:       int,
	mix:          f32,
	bendPositive: bool,
}

Skeleton_Data :: struct {
	arena:      vmem.Arena,
	name:       string,
	bones:      []Skel_Bone,
	slots:      []Skel_Slot,
	skins:      []Skel_Skin,
	animations: []Skel_Animation,
	ik:         []Skel_IK,
	fps:        f32, // DragonBones' frame rate (0 = times in seconds)
	textures:   [dynamic]^Texture, // held references (released with the data)
}

Skel_BonePose :: struct {
	x, y, rotation, scaleX, scaleY, shearX, shearY: f32,
	// World: [a b; c d] and the origin.
	a, b, c, d, wx, wy: f32,
}

Skeleton_Pose :: struct {
	bones:       []Skel_BonePose,
	attachments: []string, // per slot ("" = none)
	colors:      [][4]f32,
	drawOrder:   []int,
	skin:        int,
}

// --- data lifetime -----------------------------------------------------------------------

Skeleton_DataAllocator :: proc(d: ^Skeleton_Data) -> runtime.Allocator {return vmem.arena_allocator(&d.arena)}

Skeleton_DataDestroy :: proc(d: ^Skeleton_Data, rm: ^ResourceManager) {
	if d == nil do return
	for t in d.textures do if t != nil do ResourceManager_ReleaseTexture(rm, t)
	delete(d.textures)
	vmem.arena_destroy(&d.arena)
	free(d)
}

Skeleton_BoneIndex :: proc(d: ^Skeleton_Data, name: string) -> int {
	for b, i in d.bones do if b.name == name do return i
	return -1
}

Skeleton_SlotIndex :: proc(d: ^Skeleton_Data, name: string) -> int {
	for s, i in d.slots do if s.name == name do return i
	return -1
}

Skeleton_AnimationIndex :: proc(d: ^Skeleton_Data, name: string) -> int {
	for a, i in d.animations do if a.name == name do return i
	return -1
}

Skeleton_SkinIndex :: proc(d: ^Skeleton_Data, name: string) -> int {
	for s, i in d.skins do if s.name == name do return i
	return -1
}

// skel_attach_key: a skin map key ("slot/attachment").
skel_attach_key :: proc(slot: int, name: string, allocator := context.temp_allocator) -> string {
	return strings.concatenate({u32_str(u32(slot)), "/", name}, allocator)
}

@(private = "file")
u32_str :: proc(v: u32) -> string {
	buf: [16]u8
	i := len(buf)
	n := v
	for {
		i -= 1
		buf[i] = u8('0' + n % 10)
		n /= 10
		if n == 0 do break
	}
	return strings.clone(string(buf[i:]), context.temp_allocator)
}

// Skeleton_Attachment: a slot's attachment by name - the skin's, else the
// default skin's (skin 0).
Skeleton_Attachment :: proc(d: ^Skeleton_Data, skin, slot: int, name: string) -> (Skel_Attachment, bool) {
	if name == "" do return nil, false
	key := skel_attach_key(slot, name)
	if skin >= 0 && skin < len(d.skins) {
		if a, ok := d.skins[skin].attachments[key]; ok do return a, true
	}
	if len(d.skins) > 0 {
		if a, ok := d.skins[0].attachments[key]; ok do return a, true
	}
	return nil, false
}

// --- pose ----------------------------------------------------------------------------------

Skeleton_PoseInit :: proc(p: ^Skeleton_Pose, d: ^Skeleton_Data, allocator := context.allocator) {
	p.bones = make([]Skel_BonePose, len(d.bones), allocator)
	p.attachments = make([]string, len(d.slots), allocator)
	p.colors = make([][4]f32, len(d.slots), allocator)
	p.drawOrder = make([]int, len(d.slots), allocator)
	Skeleton_SetupPose(p, d)
}

Skeleton_PoseDestroy :: proc(p: ^Skeleton_Pose, allocator := context.allocator) {
	delete(p.bones, allocator)
	delete(p.attachments, allocator)
	delete(p.colors, allocator)
	delete(p.drawOrder, allocator)
	p^ = {}
}

// Skeleton_SetupPose: every bone and slot back to its setup values.
Skeleton_SetupPose :: proc(p: ^Skeleton_Pose, d: ^Skeleton_Data) {
	for b, i in d.bones {
		p.bones[i] = {x = b.x, y = b.y, rotation = b.rotation, scaleX = b.scaleX, scaleY = b.scaleY, shearX = b.shearX, shearY = b.shearY}
	}
	for s, i in d.slots {
		p.attachments[i] = s.attachment
		p.colors[i] = s.color
		p.drawOrder[i] = i
	}
}

// skel_curve: the eased fraction u (0..1) between two keys.
@(private = "file")
skel_curve :: proc(c: Skel_Curve, u: f32) -> f32 {
	switch c.kind {
	case .Linear: return u
	case .Stepped: return 0
	case .Bezier: return Curve_Eval(c.c, u)
	}
	return u
}

// skel_sample: a timeline's value at time t (keys sorted).
@(private = "file")
skel_sample :: proc(keys: []Skel_Key, t: f32) -> [4]f32 {
	if len(keys) == 0 do return {}
	if t <= keys[0].time do return keys[0].v
	last := keys[len(keys) - 1]
	if t >= last.time do return last.v
	for i in 0 ..< len(keys) - 1 {
		a, b := keys[i], keys[i + 1]
		if t >= a.time && t < b.time {
			u := skel_curve(a.curve, (t - a.time) / max(b.time - a.time, 1e-6))
			return a.v + (b.v - a.v) * u
		}
	}
	return last.v
}

@(private = "file")
skel_key_at :: proc(keys: []Skel_Key, t: f32) -> int {
	idx := -1
	for k, i in keys {
		if k.time <= t do idx = i
		else do break
	}
	return idx
}

// skel_angle_lerp: from a to b the short way round (degrees).
@(private = "file")
skel_angle_lerp :: proc(a, b, alpha: f32) -> f32 {
	d := math.mod(b - a, 360)
	if d > 180 do d -= 360
	if d < -180 do d += 360
	return a + d * alpha
}

// Skeleton_Apply poses the skeleton with an animation at time t, mixed by
// alpha (1 = fully; a crossfade applies the new one over the old with a
// growing alpha). Bone timelines are relative to the setup pose (Spine's
// rule; DragonBones offsets are imported the same way).
Skeleton_Apply :: proc(p: ^Skeleton_Pose, d: ^Skeleton_Data, anim: int, t: f32, alpha: f32 = 1) {
	if anim < 0 || anim >= len(d.animations) do return
	a := &d.animations[anim]
	for &tl in a.timelines {
		switch tl.kind {
		case .Rotate:
			b := &p.bones[tl.target]
			v := skel_sample(tl.keys, t)
			b.rotation = skel_angle_lerp(b.rotation, d.bones[tl.target].rotation + v[0], alpha)
		case .Translate:
			b := &p.bones[tl.target]
			v := skel_sample(tl.keys, t)
			setup := d.bones[tl.target]
			b.x += (setup.x + v[0] - b.x) * alpha
			b.y += (setup.y + v[1] - b.y) * alpha
		case .Scale:
			b := &p.bones[tl.target]
			v := skel_sample(tl.keys, t)
			setup := d.bones[tl.target]
			b.scaleX += (setup.scaleX * v[0] - b.scaleX) * alpha
			b.scaleY += (setup.scaleY * v[1] - b.scaleY) * alpha
		case .Shear:
			b := &p.bones[tl.target]
			v := skel_sample(tl.keys, t)
			setup := d.bones[tl.target]
			b.shearX += (setup.shearX + v[0] - b.shearX) * alpha
			b.shearY += (setup.shearY + v[1] - b.shearY) * alpha
		case .Attachment:
			if alpha < 0.5 do continue // (switches happen once the new animation dominates)
			if i := skel_key_at(tl.keys, t); i >= 0 do p.attachments[tl.target] = tl.keys[i].name
		case .Color:
			v := skel_sample(tl.keys, t)
			p.colors[tl.target] += (v - p.colors[tl.target]) * alpha
		}
	}
	if len(a.drawOrder) > 0 && alpha >= 0.5 {
		if i := skel_key_at(a.drawOrder, t); i >= 0 {
			if order := a.drawOrder[i].order; order != nil && len(order) == len(p.drawOrder) do copy(p.drawOrder, order)
			else do for j in 0 ..< len(p.drawOrder) do p.drawOrder[j] = j
		}
	}
}

// Skeleton_EventsBetween: the events with from < time <= to (wrapping
// past the end of a looping animation when to < from).
Skeleton_EventsBetween :: proc(d: ^Skeleton_Data, anim: int, from, to: f32, out: ^[dynamic]Skel_Key) {
	if anim < 0 || anim >= len(d.animations) do return
	for e in d.animations[anim].events {
		if (to >= from && e.time > from && e.time <= to) || (to < from && (e.time > from || e.time <= to)) do append(out, e)
	}
}

// Skeleton_UpdateWorld computes the bones' world transforms from their
// local values (parents first: bones are stored parents before children),
// then applies the IK constraints and recomputes.
Skeleton_UpdateWorld :: proc(p: ^Skeleton_Pose, d: ^Skeleton_Data, origin: [2]f32, scale: [2]f32 = {1, 1}, rotation: f32 = 0) {
	skel_world(p, d, origin, scale, rotation)
	if len(d.ik) > 0 {
		for ik in d.ik do skel_apply_ik(p, d, ik)
		skel_world(p, d, origin, scale, rotation)
	}
}

@(private = "file")
skel_world :: proc(p: ^Skeleton_Pose, d: ^Skeleton_Data, origin: [2]f32, scale: [2]f32, rotation: f32) {
	for i in 0 ..< len(d.bones) {
		b := &p.bones[i]
		rx := math.to_radians(b.rotation + b.shearX)
		ry := math.to_radians(b.rotation + 90 + b.shearY)
		la := math.cos(rx) * b.scaleX
		lb := math.cos(ry) * b.scaleY
		lc := math.sin(rx) * b.scaleX
		ld := math.sin(ry) * b.scaleY
		parent := d.bones[i].parent
		if parent < 0 {
			// The node's transform is the root's parent.
			r := math.to_radians(rotation)
			cr, sr := math.cos(r), math.sin(r)
			pa, pb, pc, pd := cr * scale.x, -sr * scale.y, sr * scale.x, cr * scale.y
			b.a = pa * la + pb * lc
			b.b = pa * lb + pb * ld
			b.c = pc * la + pd * lc
			b.d = pc * lb + pd * ld
			b.wx = origin.x + pa * b.x + pb * b.y
			b.wy = origin.y + pc * b.x + pd * b.y
			continue
		}
		pp := p.bones[parent]
		b.wx = pp.a * b.x + pp.b * b.y + pp.wx
		b.wy = pp.c * b.x + pp.d * b.y + pp.wy
		pa, pb, pc, pd := pp.a, pp.b, pp.c, pp.d
		if !d.bones[i].inheritScale {
			// Keep the parent's rotation, drop its scale.
			sx := math.sqrt(pa * pa + pc * pc)
			sy := math.sqrt(pb * pb + pd * pd)
			if sx > 1e-5 {pa /= sx; pc /= sx}
			if sy > 1e-5 {pb /= sy; pd /= sy}
		}
		if !d.bones[i].inheritRotation {
			pa, pb, pc, pd = 1, 0, 0, 1
		}
		b.a = pa * la + pb * lc
		b.b = pa * lb + pb * ld
		b.c = pc * la + pd * lc
		b.d = pc * lb + pd * ld
	}
}

// Skeleton_BoneWorldRotation: a bone's world rotation (degrees).
Skeleton_BoneWorldRotation :: proc(b: Skel_BonePose) -> f32 {
	return math.to_degrees(math.atan2(b.c, b.a))
}

// Skeleton_BoneWorldScale: a bone's world scale.
Skeleton_BoneWorldScale :: proc(b: Skel_BonePose) -> [2]f32 {
	return {math.sqrt(b.a * b.a + b.c * b.c), math.sqrt(b.b * b.b + b.d * b.d)}
}

// Skeleton_LocalToWorld: a point in a bone's space in the world.
Skeleton_LocalToWorld :: proc(b: Skel_BonePose, p: [2]f32) -> [2]f32 {
	return {b.a * p.x + b.b * p.y + b.wx, b.c * p.x + b.d * p.y + b.wy}
}

// skel_apply_ik: points a one-bone chain at the target, or bends a
// two-bone chain (law of cosines) so its tip reaches it; mixed by mix.
@(private = "file")
skel_apply_ik :: proc(p: ^Skeleton_Pose, d: ^Skeleton_Data, ik: Skel_IK) {
	if ik.mix <= 0 || ik.target < 0 do return
	t := p.bones[ik.target]
	target := [2]f32{t.wx, t.wy}
	parent_rot :: proc(p: ^Skeleton_Pose, d: ^Skeleton_Data, bone: int) -> f32 {
		pi := d.bones[bone].parent
		return Skeleton_BoneWorldRotation(p.bones[pi]) if pi >= 0 else 0
	}
	if len(ik.bones) == 1 {
		bi := ik.bones[0]
		b := &p.bones[bi]
		want := math.to_degrees(math.atan2(target.y - b.wy, target.x - b.wx)) - parent_rot(p, d, bi) - b.shearX
		b.rotation = skel_angle_lerp(b.rotation, want, ik.mix)
		return
	}
	if len(ik.bones) < 2 do return
	pi, ci := ik.bones[0], ik.bones[1]
	pb := &p.bones[pi]
	cb := &p.bones[ci]
	sp := Skeleton_BoneWorldScale(pb^)
	l1 := math.sqrt(cb.x * cb.x + cb.y * cb.y) * sp.x // parent -> child joint
	l2 := d.bones[ci].length * Skeleton_BoneWorldScale(cb^).x
	dx, dy := target.x - pb.wx, target.y - pb.wy
	dist := clamp(math.sqrt(dx * dx + dy * dy), 1e-4, l1 + l2 - 1e-4)
	if l1 < 1e-4 || l2 < 1e-4 do return
	cosA := clamp((l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist), -1, 1)
	cosB := clamp((l1 * l1 + l2 * l2 - dist * dist) / (2 * l1 * l2), -1, 1)
	bend: f32 = 1 if ik.bendPositive else -1
	toTarget := math.to_degrees(math.atan2(dy, dx))
	a1 := toTarget - bend * math.to_degrees(math.acos(cosA))
	a2 := bend * (180 - math.to_degrees(math.acos(cosB)))
	// The child's joint angle from the parent's direction to the child bone.
	jointOff := math.to_degrees(math.atan2(cb.y, cb.x))
	pb.rotation = skel_angle_lerp(pb.rotation, a1 - parent_rot(p, d, pi) - jointOff, ik.mix)
	cb.rotation = skel_angle_lerp(cb.rotation, a2 + jointOff, ik.mix)
}

// --- drawing ----------------------------------------------------------------------------

// Skeleton_Draw draws the slots in draw order (regions as quads, meshes as
// triangles, deformed by their bones) tinted by `tint`.
Skeleton_Draw :: proc(p: ^Skeleton_Pose, d: ^Skeleton_Data, tint: rl.Color) {
	if !rl.IsWindowReady() do return
	base := [4]f32{f32(tint.r) / 255, f32(tint.g) / 255, f32(tint.b) / 255, f32(tint.a) / 255}
	// Mirrored bones and the exporters' triangle winding: draw both faces.
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	defer {
		rlgl.DrawRenderBatchActive()
		rlgl.EnableBackfaceCulling()
	}
	for si in p.drawOrder {
		att, ok := Skeleton_Attachment(d, p.skin, si, p.attachments[si])
		if !ok do continue
		slot := d.slots[si]
		bone := p.bones[slot.bone]
		col := p.colors[si] * base
		c := rl.Color{u8(clamp(col[0], 0, 1) * 255), u8(clamp(col[1], 0, 1) * 255), u8(clamp(col[2], 0, 1) * 255), u8(clamp(col[3], 0, 1) * 255)}
		if slot.additive do rl.BeginBlendMode(.ADDITIVE)
		switch a in att {
		case Skel_Region: skel_draw_region(bone, a, c)
		case Skel_Mesh: skel_draw_mesh(p, bone, a, c)
		}
		if slot.additive do rl.EndBlendMode()
	}
}

// skel_region_uv: a point (0..1 across, 0..1 down the image) in the page
// (texture coordinates 0..1), for regions packed rotated or not.
@(private = "file")
skel_region_uv :: proc(tex: ^Texture, uv: rl.Rectangle, rotated: bool, u, v: f32) -> [2]f32 {
	tw, th := f32(max(tex.texture.width, 1)), f32(max(tex.texture.height, 1))
	src := Texture_Src(tex, uv) // (an atlas page from export)
	if rotated {
		// Packed turned 90 degrees clockwise: the image's x runs down the page.
		return {(src.x + (1 - v) * src.width) / tw, (src.y + u * src.height) / th}
	}
	return {(src.x + u * src.width) / tw, (src.y + v * src.height) / th}
}

@(private = "file")
skel_draw_region :: proc(bone: Skel_BonePose, r: Skel_Region, col: rl.Color) {
	if r.texture == nil || r.texture.texture.id == 0 do return
	// The region's corners in bone space (its offset, rotation and scale).
	rad := math.to_radians(r.rotation)
	cr, sr := math.cos(rad), math.sin(rad)
	hw, hh := r.width * r.scaleX * 0.5, r.height * r.scaleY * 0.5
	local :: proc(cr, sr, x, y, ox, oy: f32) -> [2]f32 {return {ox + cr * x - sr * y, oy + sr * x + cr * y}}
	corners := [4][2]f32{
		local(cr, sr, -hw, -hh, r.x, r.y), local(cr, sr, -hw, hh, r.x, r.y),
		local(cr, sr, hw, hh, r.x, r.y), local(cr, sr, hw, -hh, r.x, r.y),
	}
	uvs := [4][2]f32{
		skel_region_uv(r.texture, r.uv, r.rotated, 0, 0), skel_region_uv(r.texture, r.uv, r.rotated, 0, 1),
		skel_region_uv(r.texture, r.uv, r.rotated, 1, 1), skel_region_uv(r.texture, r.uv, r.rotated, 1, 0),
	}
	rlgl_quad(r.texture.texture.id, corners, uvs, bone, col)
}

@(private = "file")
skel_draw_mesh :: proc(p: ^Skeleton_Pose, bone: Skel_BonePose, m: Skel_Mesh, col: rl.Color) {
	if m.texture == nil || m.texture.texture.id == 0 || len(m.triangles) < 3 do return
	world := make([][2]f32, len(m.uvs), context.temp_allocator)
	if len(m.bonesOf) > 0 {
		for vi in 0 ..< len(world) {
			acc: [2]f32
			for bi, k in m.bonesOf[vi] {
				acc += Skeleton_LocalToWorld(p.bones[bi], m.offsets[vi][k]) * m.weights[vi][k]
			}
			world[vi] = acc
		}
	} else {
		for vi in 0 ..< min(len(world), len(m.vertices)) do world[vi] = Skeleton_LocalToWorld(bone, m.vertices[vi])
	}
	rlgl_triangles(m.texture, m.uv, m.rotated, world, m.uvs, m.triangles, col)
}

// rlgl_quad: a textured quad, corners in a bone's space.
@(private = "file")
rlgl_quad :: proc(tex: u32, corners: [4][2]f32, uvs: [4][2]f32, bone: Skel_BonePose, col: rl.Color) {
	rlgl.CheckRenderBatchLimit(4)
	rlgl.Begin(rlgl.QUADS)
	rlgl.SetTexture(tex) // (after Begin: a mode change resets the draw's texture)
	rlgl.Color4ub(col.r, col.g, col.b, col.a)
	for i in 0 ..< 4 {
		w := Skeleton_LocalToWorld(bone, corners[i])
		rlgl.TexCoord2f(uvs[i].x, uvs[i].y)
		rlgl.Vertex2f(w.x, w.y)
	}
	rlgl.End()
	rlgl.SetTexture(0)
}

// rlgl_triangles: textured triangles (world positions, uvs within the
// region).
@(private = "file")
rlgl_triangles :: proc(tex: ^Texture, region: rl.Rectangle, rotated: bool, world: [][2]f32, uvs: [][2]f32, tris: []u16, col: rl.Color) {
	for i := 0; i + 2 < len(tris); i += 3 {
		rlgl.CheckRenderBatchLimit(3)
		rlgl.Begin(rlgl.TRIANGLES)
		rlgl.SetTexture(tex.texture.id) // (after Begin: a mode change resets the draw's texture)
		rlgl.Color4ub(col.r, col.g, col.b, col.a)
		for k in 0 ..< 3 {
			vi := int(tris[i + k])
			if vi >= len(world) || vi >= len(uvs) do continue
			t := skel_region_uv(tex, region, rotated, uvs[vi].x, uvs[vi].y)
			rlgl.TexCoord2f(t.x, t.y)
			rlgl.Vertex2f(world[vi].x, world[vi].y)
		}
		rlgl.End()
	}
	rlgl.SetTexture(0)
}

// Skeleton_DrawBones: the bones as lines with joints (editor overlay).
Skeleton_DrawBones :: proc(p: ^Skeleton_Pose, d: ^Skeleton_Data, thickness: f32, highlight := -1) {
	for b, i in p.bones {
		tip := Skeleton_LocalToWorld(b, {max(d.bones[i].length, 0), 0})
		col := rl.Color{255, 196, 0, 255} if i == highlight else rl.Color{92, 200, 255, 200}
		rl.DrawLineEx({b.wx, b.wy}, tip, thickness, col)
		rl.DrawCircleV({b.wx, b.wy}, thickness * 1.6, col)
	}
}
