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
// "keys": [[frame, a, b, c, d], ...]}] - a 6th element names the easing
// from that key to the next ("out_quad"; linear when absent).
// ============================================================================

Track_Key :: struct {
	frame: f32,
	value: [4]f32, // float: [0]; vec2: [0..1]; colour: rgba 0..255
	ease:  Ease,   // curve from this key to the next (saved as a 6th element)
	text:  string, // Method tracks: the method; Audio tracks: the sound path
}

// Property tracks interpolate values; Method and Audio tracks fire their
// keys when playback reaches the key's frame (a script method on the
// target, or a sound).
Track_Kind :: enum {
	Property,
	Method,
	Audio,
}

TRACK_METHOD_PROPERTY :: "@call"
TRACK_AUDIO_PROPERTY :: "@audio"

Property_Track :: struct {
	target:   string, // relative node path ("." = the player)
	property: string, // reflected property path ("@call" / "@audio" for event tracks)
	kind:     Track_Kind,
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

// Animation_AddEventTrack adds (or finds) a Method or Audio track for target.
Animation_AddEventTrack :: proc(apn: ^AnimationPlayerNode, anim: ^Animation, target: string, kind: Track_Kind) -> ^Property_Track {
	prop := TRACK_METHOD_PROPERTY if kind == .Method else TRACK_AUDIO_PROPERTY
	tr := Animation_AddTrack(apn, anim, target, prop)
	tr.kind = kind
	return tr
}

// Track_SetEventKey sets (or adds) an event key's text at `frame`.
Track_SetEventKey :: proc(track: ^Property_Track, frame: f32, text: string, allocator := context.allocator) {
	for &k in track.keys {
		if math.abs(k.frame - frame) < 0.001 {
			k.text = strings.clone(text, allocator)
			return
		}
	}
	append(&track.keys, Track_Key{frame = frame, text = strings.clone(text, allocator)})
	slice.sort_by(track.keys[:], proc(a, b: Track_Key) -> bool {return a.frame < b.frame})
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
	append(&track.keys, Track_Key{frame = frame, value = value})
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
			t := Ease_Apply(a.ease, (frame - a.frame) / max(b.frame - a.frame, 0.0001))
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

@(private = "file")
track_target :: proc(apn: ^AnimationPlayerNode, track: ^Property_Track) -> ^Node {
	if track.target == "" || track.target == "." do return apn
	mgr: ^NodeManager
	if apn.gameContext != nil && apn.gameContext.scene != nil do mgr = apn.gameContext.scene.manager
	return Node_ResolvePath(mgr, apn, track.target) if mgr != nil else nil
}

// AnimationPlayerNode_ApplyTracks writes the current animation's property
// track values for `frame` into their target nodes (called while playing,
// and by the editor when scrubbing). While crossfading (Play with a blend
// time), tracks the previous animation also has are blended from it.
AnimationPlayerNode_ApplyTracks :: proc(apn: ^AnimationPlayerNode, frame: f32) {
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
		v, ok := Track_Sample(&track, frame)
		if !ok do continue
		if from != nil && blendW < 1 {
			for &old in from.tracks {
				if old.kind != .Property || old.target != track.target || old.property != track.property do continue
				if ov, ook := Track_Sample(&old, apn.blendFromFrame); ook do v = ov + (v - ov) * blendW
				break
			}
		}
		Property_SetTrackValue(p, v)
	}
}

// AnimationPlayerNode_FireEvents runs the Method and Audio keys on `frame`
// (playback reached it; scrubbing in the editor doesn't fire them).
AnimationPlayerNode_FireEvents :: proc(apn: ^AnimationPlayerNode, frame: int) {
	anim := AnimationPlayerNode_GetAnimation(apn)
	if anim == nil do return
	ctx := apn.gameContext
	for &track in anim.tracks {
		if track.kind == .Property do continue
		for &k in track.keys {
			if int(k.frame) != frame || k.text == "" do continue
			switch track.kind {
			case .Property:
			case .Method:
				target := track_target(apn, &track)
				if target == nil || ctx == nil || ctx.scriptManager == nil do continue
				Script_CallMethod(ctx.scriptManager, target, k.text, frame)
			case .Audio:
				if ctx == nil || ctx.game == nil || !Audio_Ready() do continue
				rm := &ctx.game.resourceManager
				if s, ok := rm.loadAudioSound(rm, Project_ResolveAssetPath(ctx, k.text)); ok {
					Mixer_PlaySound(s.pcm, Audio_BusFor(rm, s.filePath, "SFX"), owner = s)
				}
			}
		}
	}
}

// Animation_Length: frames in the animation's timeline (frames or the last key).
Animation_Length :: proc(anim: ^Animation) -> int {
	n := 0
	if anim.frameCount != nil do n = anim->frameCount()
	for t in anim.tracks do for k in t.keys do n = max(n, int(k.frame) + 1)
	return max(n, 1)
}
