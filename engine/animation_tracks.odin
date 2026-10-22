package engine

import "core:math"
import "core:slice"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Property tracks: keyframed animation of node properties.
//
// An Animation (frame or sprite-sheet) can carry tracks; each animates one
// reflected property ("position", "rotation", "scale", "tintColor",
// "emitter.amount", ...) of a target node (path relative to the player:
// "." = the AnimationPlayerNode itself, "Sprite", "../Ship"). Keys sit on
// frames and are interpolated linearly as the animation plays. Floats, ints,
// vectors and colours can be animated.
//
// Saved with the animation: "tracks": [{"target", "property",
// "keys": [[frame, a, b, c, d], ...]}].
// ============================================================================

Track_Key :: struct {
	frame: f32,
	value: [4]f32, // float: [0]; vec2: [0..1]; colour: rgba 0..255
}

Property_Track :: struct {
	target:   string, // relative node path ("." = the player)
	property: string, // reflected property path
	keys:     [dynamic]Track_Key,
}

// Animation_AddTrack adds (or finds) the track for target/property.
Animation_AddTrack :: proc(apn: ^AnimationPlayerNode, anim: ^Animation, target, property: string) -> ^Property_Track {
	for &t in anim.tracks do if t.target == target && t.property == property do return &t
	if anim.tracks == nil do anim.tracks = make([dynamic]Property_Track, apn.allocator)
	append(&anim.tracks, Property_Track{
		target   = strings.clone(target, apn.allocator),
		property = strings.clone(property, apn.allocator),
		keys     = make([dynamic]Track_Key, apn.allocator),
	})
	return &anim.tracks[len(anim.tracks) - 1]
}

Animation_RemoveTrack :: proc(anim: ^Animation, index: int) {
	if index >= 0 && index < len(anim.tracks) do ordered_remove(&anim.tracks, index)
}

// Track_SetKey sets (or adds) the key at `frame`; keys stay sorted.
Track_SetKey :: proc(track: ^Property_Track, frame: f32, value: [4]f32) {
	for &k in track.keys {
		if math.abs(k.frame - frame) < 0.001 {
			k.value = value
			return
		}
	}
	append(&track.keys, Track_Key{frame, value})
	slice.sort_by(track.keys[:], proc(a, b: Track_Key) -> bool {return a.frame < b.frame})
}

Track_RemoveKey :: proc(track: ^Property_Track, frame: f32) -> bool {
	for k, i in track.keys {
		if math.abs(k.frame - frame) < 0.001 {
			ordered_remove(&track.keys, i)
			return true
		}
	}
	return false
}

// Track_Sample interpolates the track's value at `frame`.
Track_Sample :: proc(track: ^Property_Track, frame: f32) -> (value: [4]f32, ok: bool) {
	n := len(track.keys)
	if n == 0 do return {}, false
	if frame <= track.keys[0].frame do return track.keys[0].value, true
	if frame >= track.keys[n - 1].frame do return track.keys[n - 1].value, true
	for i in 0 ..< n - 1 {
		a, b := track.keys[i], track.keys[i + 1]
		if frame >= a.frame && frame <= b.frame {
			t := (frame - a.frame) / max(b.frame - a.frame, 0.0001)
			return a.value + (b.value - a.value) * t, true
		}
	}
	return track.keys[n - 1].value, true
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
	}
	return {}, false
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
	}
}

// Track_FindProperty: a reflected property, or a base transform field
// ("position", "scale", "rotation").
Track_FindProperty :: proc(node: ^Node, name: string) -> (Node_Property, bool) {
	switch name {
	case "position": return {name = "position", kind = .Vec2, ptr = &node.position, type = type_info_of([2]f32)}, true
	case "scale":    return {name = "scale", kind = .Vec2, ptr = &node.scale, type = type_info_of([2]f32)}, true
	case "rotation": return {name = "rotation", kind = .Float, ptr = &node.rotation, type = type_info_of(f32)}, true
	}
	return Node_FindProperty(node, name)
}

// Track_IsAnimatable: kinds a track can drive.
Track_IsAnimatable :: proc(p: Node_Property) -> bool {
	#partial switch p.kind {
	case .Float, .Int, .Vec2, .Color: return true
	}
	return false
}

// AnimationPlayerNode_ApplyTracks writes the current animation's track
// values for `frame` into their target nodes (called while playing, and by
// the editor when scrubbing).
AnimationPlayerNode_ApplyTracks :: proc(apn: ^AnimationPlayerNode, frame: f32) {
	anim := AnimationPlayerNode_GetAnimation(apn)
	if anim == nil || len(anim.tracks) == 0 do return
	mgr: ^NodeManager
	if apn.gameContext != nil && apn.gameContext.scene != nil do mgr = apn.gameContext.scene.manager
	for &track in anim.tracks {
		target: ^Node = apn
		if track.target != "" && track.target != "." {
			target = Node_ResolvePath(mgr, apn, track.target) if mgr != nil else nil
		}
		if target == nil do continue
		p, found := Track_FindProperty(target, track.property)
		if !found do continue
		if v, ok := Track_Sample(&track, frame); ok do Property_SetTrackValue(p, v)
	}
}

// Animation_Length: frames in the animation's timeline (frames or the last key).
Animation_Length :: proc(anim: ^Animation) -> int {
	n := 0
	if anim.frameCount != nil do n = anim->frameCount()
	for t in anim.tracks do for k in t.keys do n = max(n, int(k.frame) + 1)
	return max(n, 1)
}
