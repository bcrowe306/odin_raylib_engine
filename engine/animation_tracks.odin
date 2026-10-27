package engine

import "core:fmt"
import "core:math"
import "core:math/rand"
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
// "." = the AnimationPlayerNode itself, "Sprite", "../Ship"). Keys sit on
// frames and are interpolated linearly as the animation plays. Floats, ints,
// vectors and colours can be animated.
//
// Saved with the animation: "tracks": [{"target", "property",
// "keys": [[frame, a, b, c, d], ...]}] - a 6th element names the easing
// from that key to the next ("out_quad"; linear when absent), a 7th is a
// custom curve [x1, y1, x2, y2] (a cubic Bezier like CSS cubic-bezier,
// from (0,0) to (1,1); y may overshoot) that replaces the easing.
// Event keys: [frame, "method or sound"(, "argument")].
// ============================================================================

Track_Key :: struct {
	frame: f32,
	value: [4]f32, // float: [0]; vec2: [0..1]; colour: rgba 0..255
	ease:  Ease,   // curve from this key to the next (saved as a 6th element)
	curve: [4]f32, // custom curve to the next key: cubic Bezier x1, y1, x2, y2 (when hasCurve)
	hasCurve: bool,
	text:  string, // Method tracks: the method; Audio tracks: the sound path
	arg:   string, // Method tracks: the value passed to the method ("" = the frame); a number when it reads as one
}

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

// Track_KeyCurve: a key's interpolation factor at u (0..1 between it and
// the next key) - its custom curve, else its easing.
Track_KeyCurve :: proc(k: Track_Key, u: f32) -> f32 {
	return Curve_Eval(k.curve, u) if k.hasCurve else Ease_Apply(k.ease, u)
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

// Animation_AddEventTrack adds (or finds) a Method or Audio track for target.
// For Audio, if an audio track already exists for this target, a new numbered audio track
// is created, allowing multiple audio tracks on the same animation (Issue #27).
Animation_AddEventTrack :: proc(apn: ^AnimationPlayerNode, anim: ^Animation, target: string, kind: Track_Kind) -> ^Property_Track {
	if kind == .Method {
		prop := TRACK_METHOD_PROPERTY
		tr := Animation_AddTrack(apn, anim, target, prop)
		tr.kind = kind
		return tr
	}

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
	if index >= 0 && index < len(anim.tracks) {
		tr := &anim.tracks[index]
		if tr.kind == .Audio {
			for h in tr.voiceHandles do if Mixer_VoicePlaying(h) do Mixer_StopVoice(h)
		}
		ordered_remove(&anim.tracks, index)
	}
}

// Track_SetKey sets (or adds) the key at `frame`; keys stay sorted.
Track_SetKey :: proc(track: ^Property_Track, frame: f32, value: [4]f32) {
	for &k in track.keys {
		if math.abs(k.frame - frame) < 0.001 {
			k.value = value
			return
		}
	}
	// (Frame indices - part swaps, sprite frames - hold until the next key.)
	append(&track.keys, Track_Key{frame = frame, value = value, ease = .Constant if track.property == "frame" else .Linear})
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
			t := Track_KeyCurve(a, (frame - a.frame) / max(b.frame - a.frame, 0.0001))
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
	return Node_ResolvePath(mgr, apn, path) if mgr != nil else nil
}

@(private = "file")
track_target :: proc(apn: ^AnimationPlayerNode, track: ^Property_Track) -> ^Node {
	return resolve_path(apn, track.target)
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

// Track_EventArg: the value a Method key passes - its argument (a number
// when it reads as one, else the text), else the frame.
Track_EventArg :: proc(k: Track_Key, frame: int) -> EventValue {
	if k.arg == "" do return frame
	if f, ok := strconv.parse_f64(k.arg); ok do return f
	if k.arg == "true" || k.arg == "false" do return k.arg == "true"
	return k.arg
}
