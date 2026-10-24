package engine

import "core:encoding/json"
import "core:fmt"
import "core:strings"

// ============================================================================
// The mixer's layout in project.json ("audio": {"buses": [...]}):
//
//   {"name": "Master", "volume": 1, "pan": 0, "mute": false, "solo": false,
//    "effects": [{"type": "limiter", "enabled": true, "ceiling": -0.3, "release": 80}]},
//   {"name": "Music", "output": "Master", "volume": 0.8, ...}
//
// The first bus is Master. Volumes are linear (1 = 0 dB); effect parameters
// by name (docs/audio_mixer.md lists them).
// ============================================================================

// Mixer_ToJSON: the buses as a JSON array (temp-allocated by default).
Mixer_ToJSON :: proc(allocator := context.temp_allocator) -> string {
	sb := strings.builder_make(allocator)
	strings.write_byte(&sb, '[')
	first := true
	for b in Mixer_Buses() {
		if !first do strings.write_string(&sb, ",")
		first = false
		fmt.sbprintf(&sb, "\n    {{\"name\": %q", b.name)
		if b.index != 0 {
			out := "Master"
			for o in Mixer_Buses() do if o.index == b.output do out = o.name
			fmt.sbprintf(&sb, ", \"output\": %q", out)
		}
		fmt.sbprintf(&sb, ", \"volume\": %.4g, \"pan\": %.3g", b.volume, b.pan)
		if b.mute do strings.write_string(&sb, ", \"mute\": true")
		if b.solo do strings.write_string(&sb, ", \"solo\": true")
		if len(b.effects) > 0 {
			strings.write_string(&sb, ", \"effects\": [")
			for e, k in b.effects {
				if k > 0 do strings.write_string(&sb, ", ")
				fmt.sbprintf(&sb, "{{\"type\": %q, \"enabled\": %t", MIXER_EFFECT_NAMES[e.type], e.enabled)
				for d, i in MIXER_EFFECT_PARAMS[e.type] do fmt.sbprintf(&sb, ", %q: %.4g", d.name, e.params[i])
				strings.write_byte(&sb, '}')
			}
			strings.write_byte(&sb, ']')
		}
		strings.write_byte(&sb, '}')
	}
	strings.write_string(&sb, "\n  ]")
	return strings.to_string(sb)
}

// Mixer_LoadJSON replaces the buses with a saved layout ("" or bad JSON:
// Master / Music / SFX). Voices keep playing (on Master if their bus went).
Mixer_LoadJSON :: proc(text: string) -> bool {
	Mixer_Init()
	Mixer_ResetBuses()
	if text == "" do return true
	v, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != nil do return false
	arr, ok := v.(json.Array)
	if !ok || len(arr) == 0 do return false
	num :: proc(o: json.Object, k: string, def: f32) -> f32 {
		#partial switch x in o[k] {
		case json.Float: return f32(x)
		case json.Integer: return f32(x)
		}
		return def
	}
	str :: proc(o: json.Object, k: string) -> string {
		s, _ := o[k].(json.String)
		return string(s)
	}
	flag :: proc(o: json.Object, k: string) -> bool {
		b, _ := o[k].(json.Boolean)
		return bool(b)
	}
	// Buses first (outputs by name come after, once they all exist).
	Mixer_RemoveBus(Mixer_BusIndex("Music"))
	Mixer_RemoveBus(Mixer_BusIndex("SFX"))
	indexOf := make([]int, len(arr), context.temp_allocator)
	for bv, k in arr {
		o, isObj := bv.(json.Object)
		if !isObj {
			indexOf[k] = -1
			continue
		}
		i := 0 // (the first is Master; it keeps its name)
		if k > 0 do i = Mixer_AddBus(str(o, "name"), 0)
		indexOf[k] = i
		if i < 0 do continue
		Mixer_SetBusVolume(i, num(o, "volume", 1))
		Mixer_SetBusPan(i, num(o, "pan", 0))
		Mixer_SetBusMute(i, flag(o, "mute"))
		Mixer_SetBusSolo(i, flag(o, "solo"))
		if effs, eok := o["effects"].(json.Array); eok {
			for ev in effs {
				eo, eIsObj := ev.(json.Object)
				if !eIsObj do continue
				t, tok := Effect_ParseType(str(eo, "type"))
				if !tok do continue
				slot := Mixer_AddEffect(i, t)
				e := Mixer_EffectRef(i, slot)
				if e == nil do continue
				for d, pi in MIXER_EFFECT_PARAMS[t] do e.params[pi] = clamp(num(eo, d.name, d.def), d.min, d.max)
				if en, has := eo["enabled"].(json.Boolean); has do e.enabled = bool(en)
			}
		}
	}
	for bv, k in arr {
		o, isObj := bv.(json.Object)
		if !isObj || k == 0 || indexOf[k] < 0 do continue
		if out := str(o, "output"); out != "" {
			if j := Mixer_BusIndex(out); j >= 0 do Mixer_SetBusOutput(indexOf[k], j)
		}
	}
	return true
}

// Mixer_ApplyProject: a project's buses, or the default three with the
// project's master / music / sound-effects volumes.
Mixer_ApplyProject :: proc(cfg: ^ProjectConfig) {
	Mixer_LoadJSON(cfg.mixerBuses)
	if cfg.mixerBuses == "" {
		Mixer_SetBusVolume(0, cfg.masterVolume)
		if i := Mixer_BusIndex("Music"); i >= 0 do Mixer_SetBusVolume(i, cfg.musicVolume)
		if i := Mixer_BusIndex("SFX"); i >= 0 do Mixer_SetBusVolume(i, cfg.sfxVolume)
	}
}
