package engine

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:reflect"
import "core:slice"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Property tracks: keyframed animation of node properties.
//
// An Animation (frame or sprite-sheet) can carry tracks; each animates one
// reflected property ("position", "rotation", "scale", "tintColor",
// "emitter.amount", ...) of a target node (path relative to the player:
// "." = the AnimationPlayerNode itself, "Sprite", "../Ship"). Keys sit at
// times in seconds (#176) and are sampled continuously as the animation
// plays: floats, ints, vectors and colours are interpolated; enums, strings
// (and a sprite's "texture") step - each key holds until the next.
//
// The curve from a key to the next: its easing (linear, out_quad, ...,
// constant), or - `bezier` - a cubic in time / value per component: the
// key's out handle and the next key's in handle (dt seconds, dv value),
// as After Effects' and Resolve's value graphs.
//
// Saved with the animation: "tracks": [{"target", "property", "units":
// "seconds", "keys": [{"t": 0.25, "v": [x, y, z, w], "ease": "out_quad",
// "out": [[dt, dv] x4], "in": [[dt, dv] x4], "text": ..., "arg": ...}]}].
// Older files have keys [frame, a, b, c, d(, "ease")(, [x1, y1, x2, y2])]
// (and event keys [frame, "text"(, "arg")]): converted with the
// animation's frame durations - they play as they did.
// ============================================================================

Track_Key :: struct {
	time:   f32,    // seconds from the animation's start
	value:  [4]f32, // float / int / bool / enum index: [0]; vec2: [0..1]; colour: rgba 0..255
	ease:   Ease,   // curve from this key to the next (when not bezier)
	bezier: bool,   // the curve to the next key: this key's out handle, the next key's in handle
	outTan: [4][2]f32, // per component: (dt seconds, dv) from the key - the curve leaving it
	inTan:  [4][2]f32, // per component: (dt <= 0, dv) - the curve arriving at it
	text:   string, // String / texture tracks: the value; Method: the method; Audio: the sound; Particles: the action; Spawn: the component; Enable: on / off
	arg:    string, // Method tracks: the value passed to the method ("" = the key's frame); a number when it reads as one
}

// TRACK_KEY_EPS: keys closer than this (seconds) are the same key.
TRACK_KEY_EPS :: f32(0.0005)

// Curve_Eval: a cubic Bezier easing curve (P0 = (0,0), P3 = (1,1), control
// points (x1,y1), (x2,y2), x1 / x2 in 0..1) at x = t: x solved for the
// curve parameter (Newton steps, bisection fallback), then y.
Curve_Eval :: proc(c: [4]f32, t: f32) -> f32 {
	t := clamp(t, 0, 1)
	x1, y1, x2, y2 := clamp(c[0], 0, 1), c[1], clamp(c[2], 0, 1), c[3]
	bez :: proc(a, b, u: f32) -> f32 {
		// B(u) with P0 = 0, P1 = a, P2 = b, P3 = 1
		v := 1 - u
		return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u
	}
	dbez :: proc(a, b, u: f32) -> f32 {
		v := 1 - u
		return 3 * v * v * a + 6 * v * u * (b - a) + 3 * u * u * (1 - b)
	}
	u := t
	for _ in 0 ..< 8 {
		d := dbez(x1, x2, u)
		if abs(d) < 1e-5 do break
		u = clamp(u - (bez(x1, x2, u) - t) / d, 0, 1)
	}
	if abs(bez(x1, x2, u) - t) > 1e-4 {
		lo, hi: f32 = 0, 1
		for _ in 0 ..< 30 {
			u = (lo + hi) * 0.5
			if bez(x1, x2, u) < t do lo = u
			else do hi = u
		}
	}
	return bez(y1, y2, u)
}

// cubic_at_x: a cubic Bezier from (0, y0) to (1, y3) with control points
// (x1, y1), (x2, y2) (x1, x2 in 0..1) at x = u: x solved for the curve
// parameter (Newton steps, bisection fallback), then y.
@(private)
cubic_at_x :: proc(x1, x2, y0, y1, y2, y3, u: f32) -> f32 {
	u := clamp(u, 0, 1)
	x1, x2 := clamp(x1, 0, 1), clamp(x2, 0, 1)
	bx :: proc(a, b, s: f32) -> f32 {v := 1 - s; return 3 * v * v * s * a + 3 * v * s * s * b + s * s * s}
	dbx :: proc(a, b, s: f32) -> f32 {v := 1 - s; return 3 * v * v * a + 6 * v * s * (b - a) + 3 * s * s * (1 - b)}
	s := u
	for _ in 0 ..< 8 {
		d := dbx(x1, x2, s)
		if abs(d) < 1e-5 do break
		s = clamp(s - (bx(x1, x2, s) - u) / d, 0, 1)
	}
	if abs(bx(x1, x2, s) - u) > 1e-4 {
		lo, hi: f32 = 0, 1
		for _ in 0 ..< 30 {
			s = (lo + hi) * 0.5
			if bx(x1, x2, s) < u do lo = s
			else do hi = s
		}
	}
	v := 1 - s
	return v * v * v * y0 + 3 * v * v * s * y1 + 3 * v * s * s * y2 + s * s * s * y3
}

// Track_SegmentValue: the value between keys a and b at time t.
Track_SegmentValue :: proc(a, b: Track_Key, t: f32) -> [4]f32 {
	dt := max(b.time - a.time, 0.000001)
	u := clamp((t - a.time) / dt, 0, 1)
	if !a.bezier {
		f := Ease_Apply(a.ease, u)
		return a.value + (b.value - a.value) * f
	}
	out: [4]f32
	for c in 0 ..< 4 {
		out[c] = cubic_at_x(a.outTan[c].x / dt, 1 + b.inTan[c].x / dt, a.value[c], a.value[c] + a.outTan[c].y, b.value[c] + b.inTan[c].y, b.value[c], u)
	}
	return out
}

// Track_SetSegmentCurve makes the curve from key i to the next a bezier of
// the normalized shape (x1, y1, x2, y2) - CSS cubic-bezier, from (0,0) to
// (1,1) - in every component (the old per-key custom curves; presets).
Track_SetSegmentCurve :: proc(track: ^Property_Track, i: int, c: [4]f32) {
	if i < 0 || i + 1 >= len(track.keys) do return
	a, b := &track.keys[i], &track.keys[i + 1]
	dt := b.time - a.time
	a.bezier = true
	for k in 0 ..< 4 {
		dv := b.value[k] - a.value[k]
		a.outTan[k] = {c[0] * dt, c[1] * dv}
		b.inTan[k] = {(c[2] - 1) * dt, (c[3] - 1) * dv}
	}
}

// Track_SegmentCurve: the curve from key i to the next as a normalized shape
// (x1, y1, x2, y2) - from its handles (the component that changes most), or
// ok = false when it's an easing.
Track_SegmentCurve :: proc(track: ^Property_Track, i: int) -> (c: [4]f32, ok: bool) {
	if i < 0 || i + 1 >= len(track.keys) || !track.keys[i].bezier do return {}, false
	a, b := track.keys[i], track.keys[i + 1]
	dt := max(b.time - a.time, 0.000001)
	best, bestDv := 0, f32(0)
	for k in 0 ..< 4 do if abs(b.value[k] - a.value[k]) > abs(bestDv) {best, bestDv = k, b.value[k] - a.value[k]}
	dv := bestDv if bestDv != 0 else 1
	return {a.outTan[best].x / dt, a.outTan[best].y / dv, 1 + b.inTan[best].x / dt, 1 + b.inTan[best].y / dv}, true
}

// Track_SegmentFactor: the 0..1 progress from key i to the next at u (0..1
// of the time between them) - for drawing a segment's shape.
Track_SegmentFactor :: proc(track: ^Property_Track, i: int, u: f32) -> f32 {
	if i < 0 || i + 1 >= len(track.keys) do return u
	a := track.keys[i]
	if c, ok := Track_SegmentCurve(track, i); ok do return Curve_Eval(c, u)
	return Ease_Apply(a.ease, u)
}

// Property tracks interpolate values; Method, Audio, Particle, Spawn and
// Enable tracks fire their keys when playback reaches the key's frame.
Track_Kind :: enum {
	Property,
	Method,
	Audio,
	EmitParticles,
	InstantiateComponent,
	SetEnabled,
}

TRACK_METHOD_PROPERTY    :: "@call"
TRACK_AUDIO_PROPERTY     :: "@audio"
TRACK_PARTICLES_PROPERTY :: "@particles"
TRACK_SPAWN_PROPERTY     :: "@spawn"
TRACK_ENABLE_PROPERTY    :: "@enable"

Audio_Track_Settings :: struct {
	bus:         string, // mixer bus ("" = SFX or asset import bus)
	volumeMin:   f32,    // default 1.0
	volumeMax:   f32,    // default 1.0
	pitchMin:    f32,    // default 1.0
	pitchMax:    f32,    // default 1.0
	panMin:      f32,    // default 0.0 (-1 left, 0 center, +1 right)
	panMax:      f32,    // default 0.0
	positional:  bool,
	minDistance: f32,    // default 100
	maxDistance: f32,    // default 900
	voices:      int,    // default 1 (max AUDIO_MAX_VOICES)
	sfxNode:     string, // optional target SoundNode path in scene
}

Audio_Track_Settings_Default :: proc() -> Audio_Track_Settings {
	return {
		volumeMin   = 1.0,
		volumeMax   = 1.0,
		pitchMin    = 1.0,
		pitchMax    = 1.0,
		panMin      = 0.0,
		panMax      = 0.0,
		minDistance = 100,
		maxDistance = 900,
		voices      = 1,
	}
}

Property_Track :: struct {
	target:        string, // relative node path ("." = the player)
	property:      string, // reflected property path ("@call" / "@audio" for event tracks)
	name:          string, // user-visible track label (optional, e.g. "Footsteps")
	kind:          Track_Kind,
	keys:          [dynamic]Track_Key,
	audioSettings: Audio_Track_Settings,
	voiceHandles:  [AUDIO_MAX_VOICES]Mixer_Voice_Handle,
	nextVoice:     int,
}

// Animation_AddTrack adds (or finds) the track for target/property.
Animation_AddTrack :: proc(apn: ^AnimationPlayerNode, anim: ^Animation, target, property: string) -> ^Property_Track {
	for &t in anim.tracks do if t.target == target && t.property == property do return &t
	if anim.tracks == nil do anim.tracks = make([dynamic]Property_Track, apn.allocator)
	append(&anim.tracks, Property_Track{
		target        = strings.clone(target, apn.allocator),
		property      = strings.clone(property, apn.allocator),
		keys          = make([dynamic]Track_Key, apn.allocator),
		audioSettings = Audio_Track_Settings_Default(),
	})
	return &anim.tracks[len(anim.tracks) - 1]
}

// Animation_AddEventTrack adds (or finds) an event track for target.
// For Audio, if an audio track already exists for this target, a new numbered audio track
// is created, allowing multiple audio tracks on the same animation (Issue #27).
Animation_AddEventTrack :: proc(apn: ^AnimationPlayerNode, anim: ^Animation, target: string, kind: Track_Kind) -> ^Property_Track {
	switch kind {
	case .Method:
		prop := TRACK_METHOD_PROPERTY
		tr := Animation_AddTrack(apn, anim, target, prop)
		tr.kind = kind
		return tr
	case .EmitParticles:
		prop := TRACK_PARTICLES_PROPERTY
		tr := Animation_AddTrack(apn, anim, target, prop)
		tr.kind = kind
		if tr.name == "" do tr.name = strings.clone("particles", apn.allocator)
		return tr
	case .InstantiateComponent:
		prop := TRACK_SPAWN_PROPERTY
		tr := Animation_AddTrack(apn, anim, target, prop)
		tr.kind = kind
		if tr.name == "" do tr.name = strings.clone("spawn", apn.allocator)
		return tr
	case .SetEnabled:
		prop := TRACK_ENABLE_PROPERTY
		tr := Animation_AddTrack(apn, anim, target, prop)
		tr.kind = kind
		if tr.name == "" do tr.name = strings.clone("enable", apn.allocator)
		return tr
	case .Audio:
		prop := TRACK_AUDIO_PROPERTY
		hasDefaultAudio := false
		maxIndex := 1
		for t in anim.tracks {
			if t.target == target && (t.kind == .Audio || strings.has_prefix(t.property, "@audio")) {
				if t.property == TRACK_AUDIO_PROPERTY {
					hasDefaultAudio = true
				} else if strings.has_prefix(t.property, "@audio_") {
					if idx, ok := strconv.parse_int(t.property[len("@audio_"):]); ok {
						maxIndex = max(maxIndex, idx)
					}
				}
			}
		}
		trackName := "sounds"
		if hasDefaultAudio {
			prop = fmt.tprintf("%s_%d", TRACK_AUDIO_PROPERTY, maxIndex + 1)
			trackName = fmt.tprintf("sounds %d", maxIndex + 1)
		}

		tr := Animation_AddTrack(apn, anim, target, prop)
		tr.kind = .Audio
		if tr.name == "" do tr.name = strings.clone(trackName, apn.allocator)
		return tr
	case .Property:
		return nil
	}
	return nil
}

// Track_SetEventKey sets (or adds) a key's text at `time` (event tracks;
// String / texture values).
Track_SetEventKey :: proc(track: ^Property_Track, time: f32, text: string, allocator := context.allocator) {
	for &k in track.keys {
		if math.abs(k.time - time) < TRACK_KEY_EPS {
			k.text = strings.clone(text, allocator)
			return
		}
	}
	append(&track.keys, Track_Key{time = time, text = strings.clone(text, allocator), ease = .Constant})
	Track_SortKeys(track)
}

// Track_SortKeys keeps the keys in time order.
Track_SortKeys :: proc(track: ^Property_Track) {
	slice.stable_sort_by(track.keys[:], proc(a, b: Track_Key) -> bool {return a.time < b.time})
}

Animation_RemoveTrack :: proc(anim: ^Animation, index: int) {
	if index >= 0 && index < len(anim.tracks) {
		tr := &anim.tracks[index]
		if tr.kind == .Audio {
			for h in tr.voiceHandles do if Mixer_VoicePlaying(h) do Mixer_StopVoice(h)
		}
		ordered_remove(&anim.tracks, index)
	}
}

// Track_SetKey sets (or adds) the key at `time` (seconds); keys stay sorted.
Track_SetKey :: proc(track: ^Property_Track, time: f32, value: [4]f32) {
	for &k in track.keys {
		if math.abs(k.time - time) < TRACK_KEY_EPS {
			k.value = value
			return
		}
	}
	// (Frame indices - part swaps, sprite frames - hold until the next key.)
	append(&track.keys, Track_Key{time = time, value = value, ease = .Constant if track.property == "frame" else .Linear})
	Track_SortKeys(track)
}

Track_RemoveKey :: proc(track: ^Property_Track, time: f32) -> bool {
	for k, i in track.keys {
		if math.abs(k.time - time) < TRACK_KEY_EPS {
			ordered_remove(&track.keys, i)
			return true
		}
	}
	return false
}

// Track_MoveKeys moves the keys at `times` by `delta` seconds together (the
// group stops at 0); a key they land on is replaced (#177).
Track_MoveKeys :: proc(track: ^Property_Track, times: []f32, delta: f32) {
	moving := make([]bool, len(track.keys), context.temp_allocator)
	earliest := max(f32)
	for k, i in track.keys {
		for t in times do if math.abs(k.time - t) < TRACK_KEY_EPS {
			moving[i] = true
			earliest = min(earliest, k.time)
			break
		}
	}
	if earliest == max(f32) do return
	d := max(delta, -earliest)
	for &k, i in track.keys do if moving[i] do k.time += d
	// The keys the moved ones landed on go.
	#reverse for k, i in track.keys {
		if moving[i] do continue
		for m, j in track.keys do if moving[j] && math.abs(m.time - k.time) < TRACK_KEY_EPS {
			ordered_remove(&track.keys, i)
			break
		}
	}
	Track_SortKeys(track)
}

// Track_PutKey puts a whole key (value, curve, text) at its time, replacing
// the key there (pastes, duplicates).
Track_PutKey :: proc(track: ^Property_Track, key: Track_Key) {
	if i := Track_KeyAt(track, key.time); i >= 0 {
		track.keys[i] = key
		return
	}
	append(&track.keys, key)
	Track_SortKeys(track)
}

// Track_KeyAt: the index of the key at `time` (-1: none).
Track_KeyAt :: proc(track: ^Property_Track, time: f32) -> int {
	for k, i in track.keys do if math.abs(k.time - time) < TRACK_KEY_EPS do return i
	return -1
}

// Track_Sample: the track's value at `time` (seconds).
Track_Sample :: proc(track: ^Property_Track, time: f32) -> (value: [4]f32, ok: bool) {
	n := len(track.keys)
	if n == 0 do return {}, false
	if time <= track.keys[0].time do return track.keys[0].value, true
	if time >= track.keys[n - 1].time do return track.keys[n - 1].value, true
	for i in 0 ..< n - 1 {
		a, b := track.keys[i], track.keys[i + 1]
		if time >= a.time && time <= b.time do return Track_SegmentValue(a, b, time), true
	}
	return track.keys[n - 1].value, true
}

// Track_SampleStep: the key holding at `time` (the last at or before it;
// the first before it) - stepped tracks (enums, strings, textures).
Track_SampleStep :: proc(track: ^Property_Track, time: f32) -> (key: Track_Key, ok: bool) {
	if len(track.keys) == 0 do return {}, false
	key = track.keys[0]
	for k in track.keys {
		if k.time > time + TRACK_KEY_EPS do break
		key = k
	}
	return key, true
}

// Property_GetTrackValue reads a property as a track value.
Property_GetTrackValue :: proc(p: Node_Property) -> (v: [4]f32, ok: bool) {
	#partial switch p.kind {
	case .Float:
		v[0] = (cast(^f32)p.ptr)^
		return v, true
	case .Int:
		v[0] = f32((cast(^int)p.ptr)^) if p.type.size == size_of(int) else f32((cast(^i32)p.ptr)^)
		return v, true
	case .Vec2:
		xy := (cast(^[2]f32)p.ptr)^
		return {xy.x, xy.y, 0, 0}, true
	case .Color:
		c := (cast(^rl.Color)p.ptr)^
		return {f32(c.r), f32(c.g), f32(c.b), f32(c.a)}, true
	case .Bool:
		v[0] = 1.0 if (cast(^bool)p.ptr)^ else 0.0
		return v, true
	case .Enum:
		v[0] = f32(enum_index(p))
		return v, true
	}
	return {}, false
}

// enum_index / enum_set_index: an enum property as its value's index.
@(private = "file")
enum_index :: proc(p: Node_Property) -> int {
	ti := reflect.type_info_base(p.type)
	e, ok := ti.variant.(reflect.Type_Info_Enum)
	if !ok do return 0
	raw: i64
	switch ti.size {
	case 1: raw = i64((cast(^u8)p.ptr)^)
	case 2: raw = i64((cast(^u16)p.ptr)^)
	case 4: raw = i64((cast(^u32)p.ptr)^)
	case:   raw = (cast(^i64)p.ptr)^
	}
	for v, i in e.values do if i64(v) == raw do return i
	return 0
}

@(private = "file")
enum_set_index :: proc(p: Node_Property, index: int) {
	ti := reflect.type_info_base(p.type)
	e, ok := ti.variant.(reflect.Type_Info_Enum)
	if !ok || len(e.values) == 0 do return
	raw := i64(e.values[clamp(index, 0, len(e.values) - 1)])
	switch ti.size {
	case 1: (cast(^u8)p.ptr)^ = u8(raw)
	case 2: (cast(^u16)p.ptr)^ = u16(raw)
	case 4: (cast(^u32)p.ptr)^ = u32(raw)
	case:   (cast(^i64)p.ptr)^ = raw
	}
}

// Track_IsStepped: a property whose keys hold until the next (enums,
// strings, a sprite's texture) - no in-between values.
Track_IsStepped :: proc(p: Node_Property) -> bool {
	return p.kind == .Enum || p.kind == .String
}

// Property_GetTrackText: a String property's value (stepped tracks).
Property_GetTrackText :: proc(p: Node_Property) -> (string, bool) {
	if p.kind != .String do return "", false
	return (cast(^string)p.ptr)^, true
}

// Property_SetTrackValue writes a track value into a property.
Property_SetTrackValue :: proc(p: Node_Property, v: [4]f32) {
	#partial switch p.kind {
	case .Float:
		(cast(^f32)p.ptr)^ = v[0]
	case .Int:
		if p.type.size == size_of(int) do (cast(^int)p.ptr)^ = int(math.round(v[0]))
		else do (cast(^i32)p.ptr)^ = i32(math.round(v[0]))
	case .Vec2:
		(cast(^[2]f32)p.ptr)^ = {v[0], v[1]}
	case .Color:
		(cast(^rl.Color)p.ptr)^ = {u8(clamp(v[0], 0, 255)), u8(clamp(v[1], 0, 255)), u8(clamp(v[2], 0, 255)), u8(clamp(v[3], 0, 255))}
	case .Bool:
		(cast(^bool)p.ptr)^ = v[0] >= 0.5
	case .Enum:
		enum_set_index(p, int(math.round(v[0])))
	}
}

// Track_FindProperty: a reflected property, or a base transform field
// ("position", "scale", "rotation").
Track_FindProperty :: proc(node: ^Node, name: string) -> (Node_Property, bool) {
	switch name {
	case "position": return {name = "position", kind = .Vec2, ptr = &node.position, type = type_info_of([2]f32)}, true
	case "scale":    return {name = "scale", kind = .Vec2, ptr = &node.scale, type = type_info_of([2]f32)}, true
	case "rotation": return {name = "rotation", kind = .Float, ptr = &node.rotation, type = type_info_of(f32)}, true
	case "texture":
		// A sprite's picture (stepped: the file swaps at each key).
		if node.typeId == TextureNode do return {name = "texture", kind = .String, ptr = &(cast(^TextureNode)node).filePath, type = type_info_of(string)}, true
	}
	return Node_FindProperty(node, name)
}

// Track_IsAnimatable: kinds a track can drive.
Track_IsAnimatable :: proc(p: Node_Property) -> bool {
	#partial switch p.kind {
	case .Float, .Int, .Vec2, .Color, .Bool, .Enum, .String: return true
	}
	return false
}

@(private = "file")
safe_float_range :: proc(a, b: f32) -> f32 {
	low := min(a, b)
	high := max(a, b)
	if low >= high do return low
	return rand.float32_range(low, high)
}

@(private = "file")
resolve_path :: proc(apn: ^AnimationPlayerNode, path: string) -> ^Node {
	if path == "" || path == "." do return apn
	mgr: ^NodeManager
	if apn.gameContext != nil && apn.gameContext.scene != nil do mgr = apn.gameContext.scene.manager
	if mgr == nil {
		for cur := cast(^Node)apn; cur != nil; cur = cur.parent {
			if cur.gameContext != nil && cur.gameContext.scene != nil {
				mgr = cur.gameContext.scene.manager
				break
			}
		}
	}
	return Node_ResolvePath(mgr, apn, path) if mgr != nil else nil
}

@(private = "file")
track_target :: proc(apn: ^AnimationPlayerNode, track: ^Property_Track) -> ^Node {
	return resolve_path(apn, track.target)
}

// AnimationPlayerNode_ApplyTracks writes the current animation's property
// track values for `time` (seconds) into their target nodes (called while
// playing, and by the editor when scrubbing). While crossfading (Play with
// a blend time), tracks the previous animation also has are blended from it.
AnimationPlayerNode_ApplyTracks :: proc(apn: ^AnimationPlayerNode, time: f32) {
	anim := AnimationPlayerNode_GetAnimation(apn)
	if anim == nil || len(anim.tracks) == 0 do return
	blendW: f32 = 1
	from := apn.blendFrom
	if from != nil && apn.blendTime > 0 do blendW = clamp(apn.blendElapsed / apn.blendTime, 0, 1)
	for &track in anim.tracks {
		if track.kind != .Property do continue
		target := track_target(apn, &track)
		if target == nil do continue
		p, found := Track_FindProperty(target, track.property)
		if !found do continue
		if Track_IsStepped(p) {
			k, ok := Track_SampleStep(&track, time)
			if !ok do continue
			if p.kind == .Enum {
				Property_SetTrackValue(p, k.value)
			} else {
				track_set_text(apn, target, p, k.text)
			}
			continue
		}
		v, ok := Track_Sample(&track, time)
		if !ok do continue
		if from != nil && blendW < 1 {
			for &old in from.tracks {
				if old.kind != .Property || old.target != track.target || old.property != track.property do continue
				if ov, ook := Track_Sample(&old, apn.blendFromTime); ook do v = ov + (v - ov) * blendW
				break
			}
		}
		Property_SetTrackValue(p, v)
	}
}

// track_set_text: a String property's (or a sprite's texture's) value from
// a stepped key - only when it changes (a texture loads).
@(private = "file")
track_set_text :: proc(apn: ^AnimationPlayerNode, target: ^Node, p: Node_Property, text: string) {
	cur := (cast(^string)p.ptr)^
	if cur == text do return
	if p.name == "texture" && target.typeId == TextureNode {
		if text != "" do load_texture_into(cast(^TextureNode)target, text, target.gameContext if target.gameContext != nil else apn.gameContext)
		return
	}
	(cast(^string)p.ptr)^ = strings.clone(text, target.allocator)
}

// AnimationPlayerNode_FireEvents runs the event keys (Method, Audio,
// Particles, Spawn, Enable) between two times of the playback: after
// `from`, up to `to` (from `from` too when `inclusive`: the start). Going
// backwards (reverse) the other way. Scrubbing in the editor doesn't fire.
AnimationPlayerNode_FireEvents :: proc(apn: ^AnimationPlayerNode, from, to: f32, inclusive := false) {
	anim := AnimationPlayerNode_GetAnimation(apn)
	if anim == nil do return
	ctx := apn.gameContext
	lo, hi := min(from, to), max(from, to)
	for &track in anim.tracks {
		if track.kind == .Property do continue
		for &k in track.keys {
			if k.text == "" do continue
			in_range := k.time > lo - TRACK_KEY_EPS && k.time <= hi + TRACK_KEY_EPS if inclusive else (k.time > lo + TRACK_KEY_EPS && k.time <= hi + TRACK_KEY_EPS if to >= from else k.time >= lo - TRACK_KEY_EPS && k.time < hi - TRACK_KEY_EPS)
			if !in_range do continue
			frame := int(math.round(Animation_TimeFrame(apn, anim, k.time)))
			switch track.kind {
			case .Property:
			case .Method:
				apn.onEvent->notify(apn, k.text, ctx)
				target := track_target(apn, &track)
				if target == nil || ctx == nil || ctx.scriptManager == nil do continue
				Script_CallMethod(ctx.scriptManager, target, k.text, Track_EventArg(k, frame), quiet = target.scriptInstance == nil)
			case .Audio:
				if ctx == nil || ctx.game == nil || !Audio_Ready() do continue
				rm := &ctx.game.resourceManager
				if s, ok := rm.loadAudioSound(rm, Project_ResolveAssetPath(ctx, k.text)); ok {
					cfg := &track.audioSettings
					if cfg.sfxNode != "" {
						targetNode := resolve_path(apn, cfg.sfxNode)
						if targetNode != nil && targetNode.typeId == SoundNode {
							sn := cast(^SoundNode)targetNode
							sn.audio = s
							SoundNode_Play(sn)
							continue
						}
					}

					vol := safe_float_range(cfg.volumeMin, cfg.volumeMax) if cfg.volumeMin != cfg.volumeMax else cfg.volumeMin
					pitch := safe_float_range(cfg.pitchMin, cfg.pitchMax) if cfg.pitchMin != cfg.pitchMax else cfg.pitchMin
					pan := safe_float_range(cfg.panMin, cfg.panMax) if cfg.panMin != cfg.panMax else cfg.panMin

					if cfg.positional {
						if listener, ok := Audio_ListenerPosition(ctx); ok {
							v, p := Audio_Spatialize(apn.globalPosition, listener, cfg.minDistance, cfg.maxDistance, max(cfg.maxDistance * 0.5, 1))
							vol *= v
							pan = Audio_RaylibPanToMixer(p)
						}
					}

					bus := Audio_BusFor(rm, s.filePath, "SFX")
					if cfg.bus != "" {
						if b := Mixer_BusIndex(cfg.bus); b >= 0 do bus = b
					}

					n := clamp(cfg.voices, 1, AUDIO_MAX_VOICES)
					slot := -1
					for i in 0 ..< n do if !Mixer_VoicePlaying(track.voiceHandles[i]) { slot = i; break }
					if slot < 0 {
						slot = track.nextVoice % n
						Mixer_StopVoice(track.voiceHandles[slot])
					}
					track.nextVoice = (slot + 1) % n
					track.voiceHandles[slot] = Mixer_PlaySound(s.pcm, bus, vol, pan, pitch, owner = s)
				}
			case .EmitParticles:
				pen := track_emitter(apn, &track)
				if pen == nil do continue
				action, count := Particle_KeyAction(k.text)
				switch action {
				case .Emit:    ParticleEmitterNode_EmitBurst(pen, count)
				case .Start:   pen.emitter.emitting = true
				case .Stop:    ParticleEmitterNode_Stop(pen)
				case .Restart: ParticleEmitterNode_Start(pen)
				}
			case .InstantiateComponent:
				ctx := apn.gameContext
				if ctx == nil || ctx.scene == nil do continue
				target := track_target(apn, &track)
				parent := target.parent if (target != nil && target.parent != nil) else ctx.scene.rootNode
				// (The project-relative path, as Scene.instantiate takes it: it's
				// the instance's link. Next to the target: in its parent's space.)
				spawned := Scene_InstantiateComponent(ctx.scene, k.text, parent, ctx)
				if spawned != nil && target != nil {
					spawned.position = target.position
				}
			case .SetEnabled:
				target := track_target(apn, &track)
				if target == nil do continue
				enable := k.text != "disable" && k.text != "false" && k.text != "off" && k.text != "0"
				target.enabled = enable // (bodies, areas and rays follow it on their next update)
			}
		}
	}
}

// track_emitter: a Particles track's emitter - its target, or the target's
// first emitter child.
@(private = "file")
track_emitter :: proc(apn: ^AnimationPlayerNode, track: ^Property_Track) -> ^ParticleEmitterNode {
	target := track_target(apn, track)
	if target == nil do return nil
	if target.typeId == ParticleEmitterNode do return cast(^ParticleEmitterNode)target
	mgr := apn.gameContext.scene.manager if apn.gameContext != nil && apn.gameContext.scene != nil else nil
	if mgr == nil do return nil
	for c in GetChildrenView(mgr, target) do if c != nil && c.typeId == ParticleEmitterNode do return cast(^ParticleEmitterNode)c
	return nil
}

// Particle_Key_Action: what a Particles key does (its text).
Particle_Key_Action :: enum u8 {
	Restart, // start again from scratch ("restart"; older keys: any text)
	Emit,    // a burst of N particles ("emit 20")
	Start,   // start emitting ("start")
	Stop,    // stop emitting; the live particles finish ("stop")
}

// Particle_KeyAction reads a Particles key's text: "emit 20" (or
// "emit:20"), "start", "stop", "restart" - anything else (keys saved
// before actions: "burst") restarts, as it did.
Particle_KeyAction :: proc(text: string) -> (action: Particle_Key_Action, count: int) {
	t := strings.trim_space(text)
	switch {
	case t == "start": return .Start, 0
	case t == "stop": return .Stop, 0
	case strings.has_prefix(t, "emit"):
		rest := strings.trim_space(strings.trim_left(t[4:], ": "))
		n, ok := strconv.parse_int(rest)
		return .Emit, n if ok && n > 0 else 10
	}
	return .Restart, 0
}

// Particle_KeyText: a Particles key's text for an action.
Particle_KeyText :: proc(action: Particle_Key_Action, count: int, allocator := context.temp_allocator) -> string {
	switch action {
	case .Emit:    return fmt.aprintf("emit %d", max(count, 1), allocator = allocator)
	case .Start:   return strings.clone("start", allocator)
	case .Stop:    return strings.clone("stop", allocator)
	case .Restart: return strings.clone("restart", allocator)
	}
	return ""
}

// --- time and frames -------------------------------------------------------------
// Keys are timed in seconds; the sprite frames have durations (the
// animation's fps, the player's, or per-frame overrides). These convert
// between a frame of the animation (relative to its range's start;
// fractional: in between) and its time.

// animation_fps: the animation's frames per second.
@(private = "file")
animation_fps :: proc(apn: ^AnimationPlayerNode, anim: ^Animation) -> f32 {
	if anim != nil && anim.fps > 0 do return anim.fps
	if apn != nil && apn.fps > 0 do return apn.fps
	return 12
}

// frame_duration: how long relative frame `f` of the animation shows.
@(private = "file")
frame_duration :: proc(apn: ^AnimationPlayerNode, anim: ^Animation, f: int) -> f32 {
	return Animation_GetFrameDuration(anim, anim.startFrame + f, animation_fps(apn, anim)) if anim != nil else 1.0 / 12
}

// Animation_FrameTime: the time (seconds) at relative frame `frame`
// (fractions: part of that frame's duration; past the frames: the
// animation's fps).
Animation_FrameTime :: proc(apn: ^AnimationPlayerNode, anim: ^Animation, frame: f32) -> f32 {
	if frame <= 0 do return frame / animation_fps(apn, anim)
	t: f32
	whole := int(frame)
	for f in 0 ..< whole do t += frame_duration(apn, anim, f)
	return t + (frame - f32(whole)) * frame_duration(apn, anim, whole)
}

// Animation_TimeFrame: the (fractional) relative frame at `time`.
Animation_TimeFrame :: proc(apn: ^AnimationPlayerNode, anim: ^Animation, time: f32) -> f32 {
	if time <= 0 do return time * animation_fps(apn, anim)
	t: f32
	for f in 0 ..< 1_000_000 {
		d := max(frame_duration(apn, anim, f), 0.00001)
		if time < t + d do return f32(f) + (time - t) / d
		t += d
	}
	return 0
}

// Animation_FramesDuration: how long the animation's sprite frames take
// (its range, once).
Animation_FramesDuration :: proc(apn: ^AnimationPlayerNode, anim: ^Animation) -> f32 {
	if anim == nil do return 0
	n := anim->frameCount() if anim.frameCount != nil else 1
	t: f32
	for f in 0 ..< max(n, 1) do t += frame_duration(apn, anim, f)
	return t
}

// Animation_LastKeyTime: the latest key of the animation's tracks (0: none).
Animation_LastKeyTime :: proc(anim: ^Animation) -> f32 {
	t: f32
	if anim != nil do for tr in anim.tracks do for k in tr.keys do t = max(t, k.time)
	return t
}

// Animation_Duration: the animation's length in seconds - its frames, or
// its last key when the tracks run longer.
Animation_Duration :: proc(apn: ^AnimationPlayerNode, anim: ^Animation) -> f32 {
	return max(Animation_FramesDuration(apn, anim), Animation_LastKeyTime(anim))
}

// Animation_TracksLonger: the tracks outlast the sprite frames - the track
// clock decides the loops and the end (else the frames do).
Animation_TracksLonger :: proc(apn: ^AnimationPlayerNode, anim: ^Animation) -> bool {
	return Animation_LastKeyTime(anim) > Animation_FramesDuration(apn, anim) + TRACK_KEY_EPS
}

// Animation_Length: frames in the animation's timeline (frames, or the
// last key's frame) - the editor's frame columns.
Animation_Length :: proc(anim: ^Animation, apn: ^AnimationPlayerNode = nil) -> int {
	n := 0
	if anim.frameCount != nil do n = anim->frameCount()
	for t in anim.tracks do for k in t.keys do n = max(n, int(math.round(Animation_TimeFrame(apn, anim, k.time))) + 1)
	return max(n, 1)
}

// Track_EventArg: the value a Method key passes - its argument (a number
// when it reads as one, else the text), else the frame.
Track_EventArg :: proc(k: Track_Key, frame: int) -> EventValue {
	if k.arg == "" do return frame
	if f, ok := strconv.parse_f64(k.arg); ok do return f
	if k.arg == "true" || k.arg == "false" do return k.arg == "true"
	return k.arg
}
