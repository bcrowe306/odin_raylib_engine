package editor

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"
import "core:time"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Mixer (bottom panel tab): the project's buses as a console - one strip
// per bus left to right, Master pinned at the far right.
//
//   strip    name (double-click to rename; right-click: rename / delete),
//            effects (click: edit; the dot: bypass; right-click: move /
//            remove; + adds one), output, pan, fader + stereo meter, M / S
//   + Bus    a new bus into Master
//
// Changes apply at once (Simulate plays through the editor's mixer) and are
// saved in project.json ("audio": {"buses"}). While the game runs (Play)
// they're sent to it over the editor link, and the meters show the game's
// levels. Fader: 0 dB at 70 % of its travel, +6 dB at the top (an x²
// curve: volume = 2 x²).
// ============================================================================

MIXER_STRIP_W :: 112
MIXER_STRIP_MIN_H :: 190

@(private = "file")
mx: struct {
	editBus:   int, // the effect being edited (popup)
	editSlot:  int,
	renameBus: int,
	renameBuf: [64]u8,
	asked:     time.Tick,
	openFx:    bool, // popups opened from inside a strip (their ID scope) are opened here
	openRename: bool,
	remote:    [e.MIXER_MAX_BUSES][3]f32, // the game's meters by bus index (left, right, clip)
	remoteGot: bool,
}

// fader curve: position 0..1 <-> linear volume (2 x²; 0.707 = 0 dB).
@(private = "file")
fader_vol :: proc(pos: f32) -> f32 {return 2 * pos * pos}
@(private = "file")
fader_pos :: proc(vol: f32) -> f32 {return clamp(math.sqrt(max(vol, 0) / 2), 0, 1)}
@(private = "file")
vol_db_text :: proc(v: f32) -> string {
	if v <= 0.0001 do return "-inf"
	return fmt.tprintf("%+.1f", e.lin_to_db(v))
}

// Mixer_Save writes the buses to the project (project.json).
@(private = "file")
mixer_save :: proc(state: ^EditorState, structural := false) {
	if state.projectPath == "" do return
	text := e.Mixer_ToJSON()
	if state.projectConfig.mixerBuses != "" do delete(state.projectConfig.mixerBuses)
	state.projectConfig.mixerBuses = strings.clone(text)
	e.Project_SaveConfigToFile(state.projectPath, &state.projectConfig)
	if structural && RemoteGame_Connected() {
		flat, _ := strings.replace_all(text, "\n", " ", context.temp_allocator)
		RemoteGame_Send(fmt.tprintf("mixer-load %s", flat))
	}
}

// MixerPanel_RemoteReply: the game's "@rayzr:mixer-peaks".
MixerPanel_RemoteReply :: proc(text: string) {
	v, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None do return
	arr, ok := v.(json.Array)
	if !ok do return
	mx.remote = {}
	num :: proc(v: json.Value) -> f32 {
		#partial switch x in v {
		case json.Float: return f32(x)
		case json.Integer: return f32(x)
		}
		return 0
	}
	for bv in arr {
		b, bok := bv.(json.Array)
		if !bok || len(b) < 4 do continue
		i := int(num(b[0]))
		if i >= 0 && i < e.MIXER_MAX_BUSES do mx.remote[i] = {num(b[1]), num(b[2]), num(b[3])}
	}
	mx.remoteGot = true
}

MixerPanel_Render :: proc(state: ^EditorState) {
	e.Mixer_Init()
	live := RemoteGame_Connected() && state.gameProcessRunning
	if live && time.duration_milliseconds(time.tick_since(mx.asked)) > 100 {
		mx.asked = time.tick_now()
		RemoteGame_Send("mixer-peaks")
	}
	if !live do mx.remoteGot = false
	buses := e.Mixer_Buses()
	avail := imgui.GetContentRegionAvail()
	masterW: f32 = MIXER_STRIP_W + 16
	// Strips are at least MIXER_STRIP_MIN_H tall (the panel scrolls when shorter).
	stripH := max(avail.y - 18, MIXER_STRIP_MIN_H)
	if imgui.BeginChild("##mixer_strips", {max(avail.x - masterW - 6, 120), avail.y}, {}, {.HorizontalScrollbar}) {
		for b in buses {
			if b.index == 0 do continue
			mixer_strip(state, b, buses, live, stripH)
			imgui.SameLine(0, 4)
		}
		// + Bus
		imgui.BeginGroup()
		if UI_Button(fmt.tprintf("%s  Bus", ICON_FA_PLUS), "mixer.add-bus", {86, 32}) {
			name := "Bus"
			for k := 2; e.Mixer_BusIndex(name) >= 0; k += 1 do name = fmt.tprintf("Bus %d", k)
			e.Mixer_AddBus(name, 0)
			mixer_save(state, structural = true)
		}
		UI_Tooltip("A new bus into Master - send sounds to it (a Sound / Music node's Bus) to mix them together")
		imgui.EndGroup()
	}
	imgui.EndChild()
	imgui.SameLine(0, 6)
	if imgui.BeginChild("##mixer_master", {0, avail.y}, {.Borders}, {}) {
		mixer_strip(state, buses[0], buses, live, stripH)
	}
	imgui.EndChild()
	if mx.openFx {
		imgui.OpenPopup("Effect###mixer_fx")
		mx.openFx = false
	}
	if mx.openRename {
		imgui.OpenPopup("Rename Bus###mixer_rename")
		mx.openRename = false
	}
	mixer_effect_popup(state, live)
	mixer_rename_popup(state)
}

// mixer_strip draws one bus's channel strip.
@(private = "file")
mixer_strip :: proc(state: ^EditorState, b: e.Mixer_Bus_Info, all: []e.Mixer_Bus_Info, live: bool, height: f32) {
	imgui.PushIDInt(i32(b.index))
	defer imgui.PopID()
	id := fmt.tprintf("mixer.bus:%s", b.name)
	if imgui.BeginChild("##strip", {MIXER_STRIP_W, height}, {.Borders}, {.NoScrollbar, .NoScrollWithMouse}) {
		w := imgui.GetContentRegionAvail().x
		dl := imgui.GetWindowDrawList()
		// Name.
		p := imgui.GetCursorScreenPos()
		col := UI_ACCENT if b.index == 0 else ui_line(0.35)
		imgui.DrawList_AddRectFilled(dl, p, {p.x + w, p.y + 3}, col_u32(col))
		imgui.Dummy({0, 4})
		imgui.PushFont(GlobalFonts.semibold)
		imgui.TextUnformatted(strings.clone_to_cstring(b.name, context.temp_allocator))
		imgui.PopFont()
		Drive_Item(id)
		if b.index != 0 {
			if imgui.IsItemHovered() && imgui.IsMouseDoubleClicked(.Left) do mixer_begin_rename(b)
			if imgui.BeginPopupContextItem("##busctx") {
				if imgui.MenuItem(fmt.ctprintf("%s  Rename", ICON_FA_PEN)) do mixer_begin_rename(b)
				Drive_Item("ctx:mixer-rename")
				if imgui.MenuItem(fmt.ctprintf("%s  Delete Bus", ICON_FA_TRASH)) {
					e.Mixer_RemoveBus(b.index)
					mixer_save(state, structural = true)
				}
				Drive_Item("ctx:mixer-delete")
				imgui.EndPopup()
			}
		}
		// Effects: their own scrolling area, sized to what's left, so the fader
		// row always fits.
		fixed: f32 = 24 + 26 + 30 + 56 + 24 // output, pan, bottom row, fader (min), spacing
		rows := f32(len(b.effects) + (1 if len(b.effects) < e.MIXER_MAX_EFFECTS else 0))
		fxH := clamp(rows * 24, 24, max(imgui.GetContentRegionAvail().y - fixed, 24))
		fxOpen := imgui.BeginChild("##fxlist", {0, fxH}, {}, {})
		if fxOpen do for fx, k in b.effects {
			imgui.PushIDInt(i32(k))
			on := fx.enabled
			dot := ICON_FA_CIRCLE if on else ICON_FA_CIRCLE_XMARK
			if UI_IconButton(dot, fmt.tprintf("mixer.fx-on:%s:%d", b.name, k), "Bypass" if on else "Enable", on, 20) {
				e.Mixer_SetEffectEnabled(b.index, k, !on)
				if live do RemoteGame_Send(fmt.tprintf("mixer-fx-enabled %d %d %d", b.index, k, 0 if on else 1))
				mixer_save(state)
			}
			imgui.SameLine(0, 2)
			label := e.MIXER_EFFECT_LABELS[fx.type]
			if fx.gr > 0.5 do label = fmt.tprintf("%s -%.0f", label, fx.gr) // gain reduction
			if !on do imgui.PushStyleColorImVec4(.Text, UI_TEXT_FAINT)
			if imgui.Button(fmt.ctprintf("%s##fx", label), {w - 24, 20}) {
				mx.editBus, mx.editSlot = b.index, k
				mx.openFx = true
			}
			if !on do imgui.PopStyleColor()
			Drive_Item(fmt.tprintf("mixer.fx:%s:%d", b.name, k))
			if imgui.BeginPopupContextItem("##fxctx") {
				if imgui.MenuItem("Move Up", nil, false, k > 0) {e.Mixer_MoveEffect(b.index, k, k - 1); mixer_save(state, structural = true)}
				if imgui.MenuItem("Move Down", nil, false, k < len(b.effects) - 1) {e.Mixer_MoveEffect(b.index, k, k + 1); mixer_save(state, structural = true)}
				imgui.Separator()
				if imgui.MenuItem(fmt.ctprintf("%s  Remove", ICON_FA_TRASH)) {
					e.Mixer_RemoveEffect(b.index, k)
					mixer_save(state, structural = true)
				}
				Drive_Item("ctx:mixer-fx-remove")
				imgui.EndPopup()
			}
			imgui.PopID()
		}
		if fxOpen && len(b.effects) < e.MIXER_MAX_EFFECTS {
			imgui.SetNextItemWidth(w)
			if imgui.BeginCombo("##addfx", fmt.ctprintf("%s Effect", ICON_FA_PLUS), {.NoArrowButton}) {
				for t in e.Mixer_Effect_Type {
					if t == .None do continue
					if imgui.Selectable(strings.clone_to_cstring(e.MIXER_EFFECT_LABELS[t], context.temp_allocator)) {
						e.Mixer_AddEffect(b.index, t)
						mixer_save(state, structural = true)
					}
					Drive_Item(fmt.tprintf("pick:%s", e.MIXER_EFFECT_LABELS[t]))
				}
				imgui.EndCombo()
			}
			Drive_Item(fmt.tprintf("mixer.add-fx:%s", b.name))
		}
		imgui.EndChild()
		// Output.
		if b.index != 0 {
			names := make([dynamic]string, context.temp_allocator)
			idx := make([dynamic]int, context.temp_allocator)
			cur := 0
			for o in all {
				if o.index == b.index do continue
				append(&names, fmt.tprintf("%s %s", ICON_FA_ARROW_RIGHT, o.name))
				append(&idx, o.index)
				if o.index == b.output do cur = len(names) - 1
			}
			imgui.SetNextItemWidth(w)
			if k, changed := UI_Combo(fmt.tprintf("mixer.out:%s", b.name), cur, names[:]); changed {
				if e.Mixer_SetBusOutput(b.index, idx[k]) do mixer_save(state, structural = true)
				else do Editor_Log(state, .Warn, "%s can't output into %s (it would loop)", b.name, all[idx[k]].name)
			}
			UI_Tooltip("Where this bus goes: Master, or another bus (a group)")
		}
		// Pan.
		pan := b.pan
		imgui.SetNextItemWidth(w)
		if imgui.SliderFloat("##pan", &pan, -1, 1, pan < -0.005 ? fmt.ctprintf("L %.0f", -pan * 100) : pan > 0.005 ? fmt.ctprintf("R %.0f", pan * 100) : "C") {
			e.Mixer_SetBusPan(b.index, pan)
			if live do RemoteGame_Send(fmt.tprintf("mixer-set %d pan %.3f", b.index, pan))
		}
		if imgui.IsItemDeactivatedAfterEdit() do mixer_save(state)
		if imgui.IsItemHovered() && imgui.IsMouseDoubleClicked(.Left) {
			e.Mixer_SetBusPan(b.index, 0)
			if live do RemoteGame_Send(fmt.tprintf("mixer-set %d pan 0", b.index))
			mixer_save(state)
		}
		Drive_Item(fmt.tprintf("mixer.pan:%s", b.name))
		UI_Tooltip("Pan (double-click: centre)")
		// Fader + meter (the rest of the strip; the dB readout under it).
		left := imgui.GetContentRegionAvail().y - 28
		pos := fader_pos(b.volume)
		imgui.PushStyleVarImVec2(.FramePadding, {0, 0})
		if imgui.VSliderFloat("##fader", {26, max(left, 36)}, &pos, 0, 1, "") {
			v := fader_vol(pos) if pos > 0.004 else 0
			e.Mixer_SetBusVolume(b.index, v)
			if live do RemoteGame_Send(fmt.tprintf("mixer-set %d volume %.4f", b.index, v))
		}
		imgui.PopStyleVar()
		if imgui.IsItemDeactivatedAfterEdit() do mixer_save(state)
		if imgui.IsItemHovered() && imgui.IsMouseDoubleClicked(.Left) {
			e.Mixer_SetBusVolume(b.index, 1)
			if live do RemoteGame_Send(fmt.tprintf("mixer-set %d volume 1", b.index))
			mixer_save(state)
		}
		Drive_Item(fmt.tprintf("mixer.fader:%s", b.name))
		UI_Tooltip("Volume (double-click: 0 dB)")
		fmn := imgui.GetItemRectMin()
		fmx := imgui.GetItemRectMax()
		// 0 dB tick on the fader.
		y0 := fmx.y - (fmx.y - fmn.y) * fader_pos(1)
		imgui.DrawList_AddLine(dl, {fmn.x - 2, y0}, {fmx.x + 2, y0}, col_u32(ui_line(0.6)), 1)
		imgui.SameLine(0, 6)
		pk := b.peak
		clip := b.clip
		if live && mx.remoteGot {
			pk = {mx.remote[b.index][0], mx.remote[b.index][1]}
			clip = mx.remote[b.index][2] > 0
		}
		mp := imgui.GetCursorScreenPos()
		mh := fmx.y - fmn.y
		mw: f32 = 10
		for ch in 0 ..< 2 {
			x := mp.x + f32(ch) * (mw + 3)
			imgui.DrawList_AddRectFilled(dl, {x, mp.y}, {x + mw, mp.y + mh}, col_u32(UI_BG_APP), 2)
			f := fader_pos(pk[ch])
			top := mp.y + mh * (1 - f)
			// Green below -12 dB, yellow to 0 dB, red over.
			g12 := mp.y + mh * (1 - fader_pos(0.25))
			g0 := mp.y + mh * (1 - fader_pos(1))
			bot := mp.y + mh
			if f > 0 {
				imgui.DrawList_AddRectFilled(dl, {x, max(top, g12)}, {x + mw, bot}, col_u32({0.30, 0.81, 0.55, 1}))
				if top < g12 do imgui.DrawList_AddRectFilled(dl, {x, max(top, g0)}, {x + mw, g12}, col_u32({0.96, 0.78, 0.30, 1}))
				if top < g0 do imgui.DrawList_AddRectFilled(dl, {x, top}, {x + mw, g0}, col_u32(UI_DANGER))
			}
		}
		if clip do imgui.DrawList_AddRectFilled(dl, {mp.x, mp.y - 5}, {mp.x + mw * 2 + 3, mp.y - 1}, col_u32(UI_DANGER), 1)
		Drive_ItemRect(fmt.tprintf("mixer.meter:%s", b.name), mp, {mp.x + mw * 2 + 3, mp.y + mh}, inWindow = true)
		imgui.Dummy({mw * 2 + 3, mh})
		// Mute, solo and the level (one row).
		if b.index != 0 {
			if mixer_toggle("M", b.mute, {0.95, 0.55, 0.25, 1}, fmt.tprintf("mixer.mute:%s", b.name)) {
				e.Mixer_SetBusMute(b.index, !b.mute)
				if live do RemoteGame_Send(fmt.tprintf("mixer-set %d mute %d", b.index, 0 if b.mute else 1))
				mixer_save(state)
			}
			UI_Tooltip("Mute")
			imgui.SameLine(0, 4)
			if mixer_toggle("S", b.solo, {0.96, 0.82, 0.30, 1}, fmt.tprintf("mixer.solo:%s", b.name)) {
				e.Mixer_SetBusSolo(b.index, !b.solo)
				if live do RemoteGame_Send(fmt.tprintf("mixer-set %d solo %d", b.index, 0 if b.solo else 1))
				mixer_save(state)
			}
			UI_Tooltip("Solo: only soloed buses (and what they feed) are heard")
			imgui.SameLine(0, 4)
		}
		// dB readout: type a value (Enter) for an exact level.
		{
			@(static) dbBuf: [16]u8
			@(static) dbFor: int = -1
			dbId := fmt.tprintf("mixer.db:%s", b.name)
			// The live level, except in the field being typed in.
			show: [16]u8
			copy(show[:15], fmt.tprintf("%s dB", vol_db_text(b.volume)))
			imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x)
			editing := dbFor == b.index
			buf := &dbBuf if editing else &show
			if imgui.InputText("##db", cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue, .AutoSelectAll, .CharsScientific}) {
				txt := strings.trim_space(strings.trim_suffix(strings.trim_space(string(cstring(raw_data(buf[:])))), "dB"))
				v: f32
				if strings.has_prefix(txt, "-inf") {
					v = 0
				} else if db, ok := strconv_f32(txt); ok {
					v = e.db_to_lin(clamp(db, -96, 6))
				} else {
					v = b.volume
				}
				e.Mixer_SetBusVolume(b.index, v)
				if live do RemoteGame_Send(fmt.tprintf("mixer-set %d volume %.4f", b.index, v))
				mixer_save(state)
				dbFor = -1
			}
			if imgui.IsItemActivated() {
				dbFor = b.index
				dbBuf = show
			}
			if imgui.IsItemDeactivated() && dbFor == b.index do dbFor = -1
			Drive_Item(dbId)
			UI_Tooltip("The fader's level - type a value in dB and press Enter")
		}
	}
	imgui.EndChild()
}

@(private = "file")
mixer_toggle :: proc(label: string, on: bool, col: imgui.Vec4, id: string) -> bool {
	if on {
		imgui.PushStyleColorImVec4(.Button, col)
		imgui.PushStyleColorImVec4(.Text, {0.08, 0.08, 0.1, 1})
	}
	clicked := imgui.Button(strings.clone_to_cstring(label, context.temp_allocator), {22, 22})
	if on do imgui.PopStyleColor(2)
	Drive_Item(id)
	return clicked
}

@(private = "file")
mixer_begin_rename :: proc(b: e.Mixer_Bus_Info) {
	mx.renameBus = b.index
	mx.renameBuf = {}
	copy(mx.renameBuf[:len(mx.renameBuf) - 1], b.name)
	mx.openRename = true
}

@(private = "file")
mixer_rename_popup :: proc(state: ^EditorState) {
	if !imgui.BeginPopup("Rename Bus###mixer_rename") do return
	defer imgui.EndPopup()
	if imgui.IsWindowAppearing() do imgui.SetKeyboardFocusHere()
	imgui.SetNextItemWidth(180)
	done := imgui.InputText("##rn", cstring(raw_data(mx.renameBuf[:])), len(mx.renameBuf), {.EnterReturnsTrue, .AutoSelectAll})
	Drive_Item("mixer.rename")
	if done {
		name := strings.trim_space(string(cstring(raw_data(mx.renameBuf[:]))))
		if e.Mixer_RenameBus(mx.renameBus, name) {
			mixer_save(state, structural = true)
			Editor_Log(state, .Info, "Renamed the bus to %s (Sound / Music nodes using the old name now play into SFX / Music)", name)
		} else {
			Editor_Log(state, .Warn, "A bus named %s already exists", name)
		}
		imgui.CloseCurrentPopup()
	}
}

// mixer_effect_popup: the parameters of the effect being edited.
@(private = "file")
mixer_effect_popup :: proc(state: ^EditorState, live: bool) {
	if !imgui.BeginPopup("Effect###mixer_fx") do return
	defer imgui.EndPopup()
	fx := e.Mixer_EffectRef(mx.editBus, mx.editSlot)
	if fx == nil {
		imgui.CloseCurrentPopup()
		return
	}
	if imgui.IsKeyPressed(.Escape) {
		imgui.CloseCurrentPopup()
		return
	}
	UI_PanelTitle(ICON_FA_SLIDERS, e.MIXER_EFFECT_LABELS[fx.type])
	for d, i in e.MIXER_EFFECT_PARAMS[fx.type] {
		imgui.PushIDInt(i32(i))
		imgui.SetNextItemWidth(220)
		v := fx.params[i]
		fmtc := fmt.ctprintf("%s: %%.%df %s", d.label, 0 if d.max - d.min > 50 else 2, d.unit)
		changed := imgui.SliderFloat("##p", &v, d.min, d.max, fmtc, {.Logarithmic} if d.log else {})
		if changed {
			fx.params[i] = v
			if live do RemoteGame_Send(fmt.tprintf("mixer-fx %d %d %d %.4f", mx.editBus, mx.editSlot, i, v))
		}
		if imgui.IsItemDeactivatedAfterEdit() do mixer_save(state)
		Drive_Item(fmt.tprintf("mixer.param:%s", d.name))
		imgui.PopID()
	}
	if fx.type == .Compressor || fx.type == .Limiter do UI_DimText(fmt.tprintf("Gain reduction: %.1f dB", fx.gr))
	if UI_Button("Defaults", "mixer.fx-defaults") {
		for d, i in e.MIXER_EFFECT_PARAMS[fx.type] {
			fx.params[i] = d.def
			if live do RemoteGame_Send(fmt.tprintf("mixer-fx %d %d %d %.4f", mx.editBus, mx.editSlot, i, d.def))
		}
		mixer_save(state)
	}
}

@(private = "file")
strconv_f32 :: proc(s: string) -> (f32, bool) {
	v, ok := strconv.parse_f32(s)
	return v, ok
}

// MixerPanel_Query: drive queries mixer-*.
MixerPanel_Query :: proc(q: string) -> (string, bool) {
	switch q {
	case "mixer-buses":
		// "Master:0.00,Music:-6.02,..." (name: fader dB)
		sb := strings.builder_make(context.temp_allocator)
		for b, i in e.Mixer_Buses() {
			if i > 0 do strings.write_string(&sb, ",")
			fmt.sbprintf(&sb, "%s:%s", b.name, vol_db_text(b.volume))
		}
		return strings.to_string(sb), true
	case "mixer-voices": return fmt.tprint(e.Mixer_ActiveVoices()), true
	}
	return "", false
}
