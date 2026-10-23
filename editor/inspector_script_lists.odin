package editor

import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:slice"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Inspector widgets for script properties stored as JSON lists:
//   array    { type = "array", of = "float" | "int" | "bool" | "string" |
//            "color" | "vector2" | "node" | "texture" | ... } - one row per item
//   curve    points {t, v}: a canvas - drag points, double-click to add,
//            right-click to remove
//   gradient stops {t, r, g, b, a}: a bar - drag stops, click to edit the
//            colour, double-click to add, right-click to remove
// Each returns the edited list as JSON text when it changed.
// ============================================================================

// Script_PropInfo: a script property's declaration (nil when unknown).
Script_PropInfo :: proc(state: ^EditorState, inst: ^e.ScriptInstance, name: string) -> ^e.ScriptProperty {
	mod, ok := state.game.scriptManager.modules[e.ScriptVFS_NormalizePath(inst.modulePath)]
	if !ok || mod == nil do return nil
	for &p in mod.properties do if p.name == name do return &p
	return nil
}

@(private = "file")
num :: proc(v: json.Value) -> f64 {
	#partial switch x in v {
	case json.Float:   return f64(x)
	case json.Integer: return f64(x)
	}
	return 0
}

@(private = "file")
nums :: proc(v: json.Value, n: int, def: f64 = 0) -> []f64 {
	out := make([]f64, n, context.temp_allocator)
	for i in 0 ..< n do out[i] = def
	if arr, ok := v.(json.Array); ok do for i in 0 ..< min(n, len(arr)) do out[i] = num(arr[i])
	return out
}

@(private = "file")
parse_list :: proc(text: string) -> [dynamic]json.Value {
	out := make([dynamic]json.Value, context.temp_allocator)
	v, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err == .None do if arr, ok := v.(json.Array); ok do append(&out, ..arr[:])
	return out
}

@(private = "file")
to_text :: proc(items: []json.Value) -> string {
	return e.Json_Compact(json.Array(slice.clone_to_dynamic(items, context.temp_allocator)))
}

@(private = "file")
num_array :: proc(vals: ..f64) -> json.Value {
	arr := make(json.Array, len(vals), context.temp_allocator)
	for v, i in vals do arr[i] = json.Float(v)
	return arr
}

// script_array_field: one row per item (its editor per element type),
// a remove button each and "+ Add".
script_array_field :: proc(state: ^EditorState, owner: ^e.Node, id, elem, text: string) -> (out: string, changed: bool) {
	items := parse_list(text)
	remove := -1
	w := field_width() - 28
	for &item, i in items {
		imgui.PushIDInt(c.int(i))
		iid := fmt.tprintf("%s.item:%d", id, i)
		imgui.SetNextItemWidth(w)
		switch elem {
		case "float", "number":
			f := f32(num(item))
			if imgui.DragFloat("##v", &f, 0.1, 0, 0, float_format(f)) {item = json.Float(f); changed = true}
		case "int", "integer":
			n := c.int(num(item))
			if imgui.DragInt("##v", &n, 0.2) {item = json.Integer(n); changed = true}
		case "bool", "boolean":
			b := bool(item.(json.Boolean) or_else false)
			if imgui.Checkbox("##v", &b) {item = json.Boolean(b); changed = true}
		case "color":
			cl := nums(item, 4, 1)
			col := [4]f32{f32(cl[0]), f32(cl[1]), f32(cl[2]), f32(cl[3])}
			if imgui.ColorEdit4("##v", &col, {.AlphaBar}) {item = num_array(f64(col[0]), f64(col[1]), f64(col[2]), f64(col[3])); changed = true}
		case "vector2", "vec2":
			xy := nums(item, 2)
			v := [2]f32{f32(xy[0]), f32(xy[1])}
			if imgui.DragFloat2("##v", &v, 0.5) {item = num_array(f64(v.x), f64(v.y)); changed = true}
		case "node":
			cur := string(item.(json.String) or_else "")
			if path, ok := node_ref_field(state, owner, iid, cur); ok {item = json.String(path); changed = true}
		case "texture", "audio", "scene", "script", "component", "level", "file":
			cur := string(item.(json.String) or_else "")
			if path, ok := asset_picker(iid, cur, Script_AssetFiles(state, elem), allowNone = true); ok && path != cur {item = json.String(path); changed = true}
		case:
			bufT: [256]u8
			copy(bufT[:len(bufT) - 1], string(item.(json.String) or_else ""))
			if imgui.InputText("##v", cstring(raw_data(bufT[:])), len(bufT)) {item = json.String(strings.clone(string(cstring(raw_data(bufT[:]))), context.temp_allocator)); changed = true}
		}
		Drive_Item(iid)
		imgui.SameLine(0, 4)
		if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("%s.remove:%d", id, i), "Remove this item", size = 22) do remove = i
		imgui.PopID()
	}
	if remove >= 0 {
		ordered_remove(&items, remove)
		changed = true
	}
	if UI_Button(fmt.tprintf("%s  Add", ICON_FA_PLUS), fmt.tprintf("%s.add", id)) {
		def: json.Value
		switch elem {
		case "float", "number": def = json.Float(0)
		case "int", "integer":  def = json.Integer(0)
		case "bool", "boolean": def = json.Boolean(false)
		case "color":           def = num_array(1, 1, 1, 1)
		case "vector2", "vec2": def = num_array(0, 0)
		case:                   def = json.String("")
		}
		append(&items, def)
		changed = true
	}
	imgui.SameLine(0, 8)
	UI_DimText(fmt.tprintf("%d item%s", len(items), "" if len(items) == 1 else "s"))
	return to_text(items[:]), changed
}

@(private = "file")
listDrag: struct {
	id:    string, // the widget being dragged in ("" none)
	index: int,
}

// script_curve_field: a curve editor (points {t, v}, t in 0..1).
script_curve_field :: proc(id, text: string) -> (out: string, changed: bool) {
	items := parse_list(text)
	pts := make([dynamic][2]f32, context.temp_allocator)
	for it in items {
		p := nums(it, 2)
		append(&pts, [2]f32{f32(p[0]), f32(p[1])})
	}
	lo, hi: f32 = 0, 1
	for p in pts {lo = min(lo, p.y); hi = max(hi, p.y)}
	size := [2]f32{field_width(), 80}
	cur := imgui.GetCursorScreenPos()
	mn := [2]f32{cur.x, cur.y}
	mx := mn + size
	dl := imgui.GetWindowDrawList()
	imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32(UI_BG_RAISED), 4)
	imgui.DrawList_AddRect(dl, mn, mx, col_u32(ui_line(0.15)), 4)
	to_screen :: proc(p: [2]f32, mn, mx: [2]f32, lo, hi: f32) -> [2]f32 {
		return {mn.x + 6 + p.x * (mx.x - mn.x - 12), mx.y - 6 - (p.y - lo) / max(hi - lo, 0.0001) * (mx.y - mn.y - 12)}
	}
	from_screen :: proc(s: [2]f32, mn, mx: [2]f32, lo, hi: f32) -> [2]f32 {
		t := clamp((s.x - mn.x - 6) / (mx.x - mn.x - 12), 0, 1)
		v := lo + (mx.y - 6 - s.y) / (mx.y - mn.y - 12) * (hi - lo)
		return {t, v}
	}
	slice.sort_by(pts[:], proc(a, b: [2]f32) -> bool {return a.x < b.x})
	for i in 1 ..< len(pts) do imgui.DrawList_AddLine(dl, to_screen(pts[i - 1], mn, mx, lo, hi), to_screen(pts[i], mn, mx, lo, hi), col_u32(UI_ACCENT), 2)
	imgui.InvisibleButton(fmt.ctprintf("##%s", id), size)
	Drive_Item(fmt.tprintf("%s.curve", id))
	hovered := imgui.IsItemHovered()
	mouse := [2]f32{imgui.GetIO().MousePos.x, imgui.GetIO().MousePos.y}
	near := -1
	for p, i in pts {
		s := to_screen(p, mn, mx, lo, hi)
		d := s - mouse
		if d.x * d.x + d.y * d.y < 64 do near = i
		imgui.DrawList_AddCircleFilled(dl, s, 4 if near != i else 6, col_u32(UI_TEXT))
		Drive_ItemRect(fmt.tprintf("%s.point:%d", id, i), s - 5, s + 5, inWindow = true)
	}
	if imgui.IsItemActivated() && near >= 0 {
		delete(listDrag.id)
		listDrag = {strings.clone(id), near}
	}
	if listDrag.id == id && imgui.IsItemActive() && listDrag.index < len(pts) {
		pts[listDrag.index] = from_screen(mouse, mn, mx, lo, hi)
		changed = true
	}
	if !imgui.IsMouseDown(.Left) && listDrag.id == id {delete(listDrag.id); listDrag.id = ""}
	if hovered && imgui.IsMouseDoubleClicked(.Left) && near < 0 {
		append(&pts, from_screen(mouse, mn, mx, lo, hi))
		changed = true
	}
	if hovered && imgui.IsMouseClicked(.Right) && near >= 0 && len(pts) > 2 {
		ordered_remove(&pts, near)
		changed = true
	}
	UI_Tooltip("Drag points · double-click to add · right-click to remove")
	if !changed do return text, false
	slice.sort_by(pts[:], proc(a, b: [2]f32) -> bool {return a.x < b.x})
	vals := make([dynamic]json.Value, context.temp_allocator)
	for p in pts do append(&vals, num_array(f64(p.x), f64(p.y)))
	return to_text(vals[:]), true
}

@(private = "file")
gradEdit: struct {
	id:    string,
	index: int,
}

// script_gradient_field: a gradient editor (stops {t, r, g, b, a}).
script_gradient_field :: proc(id, text: string) -> (out: string, changed: bool) {
	items := parse_list(text)
	Stop :: struct {t: f32, c: [4]f32}
	stops := make([dynamic]Stop, context.temp_allocator)
	for it in items {
		v := nums(it, 5, 1)
		append(&stops, Stop{f32(v[0]), {f32(v[1]), f32(v[2]), f32(v[3]), f32(v[4])}})
	}
	slice.sort_by(stops[:], proc(a, b: Stop) -> bool {return a.t < b.t})
	size := [2]f32{field_width(), 22}
	cur := imgui.GetCursorScreenPos()
	mn := [2]f32{cur.x, cur.y}
	mx := mn + size
	dl := imgui.GetWindowDrawList()
	col :: proc(c: [4]f32) -> u32 {return col_u32({c[0], c[1], c[2], c[3]})}
	if len(stops) > 0 {
		x :: proc(t: f32, mn, mx: [2]f32) -> f32 {return mn.x + t * (mx.x - mn.x)}
		imgui.DrawList_AddRectFilled(dl, mn, {x(stops[0].t, mn, mx), mx.y}, col(stops[0].c))
		for i in 1 ..< len(stops) {
			a, b := stops[i - 1], stops[i]
			imgui.DrawList_AddRectFilledMultiColor(dl, {x(a.t, mn, mx), mn.y}, {x(b.t, mn, mx), mx.y}, col(a.c), col(b.c), col(b.c), col(a.c))
		}
		imgui.DrawList_AddRectFilled(dl, {x(stops[len(stops) - 1].t, mn, mx), mn.y}, mx, col(stops[len(stops) - 1].c))
	}
	imgui.DrawList_AddRect(dl, mn, mx, col_u32(ui_line(0.2)), 2)
	imgui.InvisibleButton(fmt.ctprintf("##%s", id), {size.x, size.y + 12})
	Drive_Item(fmt.tprintf("%s.gradient", id))
	hovered := imgui.IsItemHovered()
	mouse := [2]f32{imgui.GetIO().MousePos.x, imgui.GetIO().MousePos.y}
	near := -1
	for s, i in stops {
		px := mn.x + s.t * size.x
		tri := [2]f32{px, mx.y + 2}
		if abs(mouse.x - px) < 6 && mouse.y > mn.y && mouse.y < mx.y + 14 do near = i
		imgui.DrawList_AddTriangleFilled(dl, tri, tri + {-5, 9}, tri + {5, 9}, col_u32(UI_ACCENT if near == i else UI_TEXT))
		Drive_ItemRect(fmt.tprintf("%s.stop:%d", id, i), tri + {-5, 0}, tri + {5, 9}, inWindow = true)
	}
	if imgui.IsItemActivated() && near >= 0 {
		delete(listDrag.id)
		listDrag = {strings.clone(id), near}
	}
	if listDrag.id == id && imgui.IsItemActive() && listDrag.index < len(stops) && imgui.IsMouseDragging(.Left, 2) {
		stops[listDrag.index].t = clamp((mouse.x - mn.x) / size.x, 0, 1)
		changed = true
	}
	if imgui.IsItemDeactivated() && listDrag.id == id && !imgui.IsMouseDragging(.Left, 2) {
		// A click on a stop: edit its colour.
		delete(gradEdit.id)
		gradEdit = {strings.clone(id), listDrag.index}
		imgui.OpenPopup(fmt.ctprintf("##%s_stop", id))
	}
	if !imgui.IsMouseDown(.Left) && listDrag.id == id {delete(listDrag.id); listDrag.id = ""}
	if hovered && imgui.IsMouseDoubleClicked(.Left) && near < 0 {
		t := clamp((mouse.x - mn.x) / size.x, 0, 1)
		r, g, b, a := sample(stops[:], t)
		append(&stops, Stop{t, {r, g, b, a}})
		changed = true
	}
	if hovered && imgui.IsMouseClicked(.Right) && near >= 0 && len(stops) > 2 {
		ordered_remove(&stops, near)
		changed = true
	}
	if imgui.BeginPopup(fmt.ctprintf("##%s_stop", id)) {
		if gradEdit.id == id && gradEdit.index < len(stops) {
			if imgui.ColorPicker4("##stopcol", &stops[gradEdit.index].c, {.AlphaBar}) do changed = true
		}
		imgui.EndPopup()
	}
	UI_Tooltip("Drag stops · click one for its colour · double-click to add · right-click to remove")
	if !changed do return text, false
	slice.sort_by(stops[:], proc(a, b: Stop) -> bool {return a.t < b.t})
	vals := make([dynamic]json.Value, context.temp_allocator)
	for s in stops do append(&vals, num_array(f64(s.t), f64(s.c[0]), f64(s.c[1]), f64(s.c[2]), f64(s.c[3])))
	return to_text(vals[:]), true

	sample :: proc(stops: []Stop, t: f32) -> (f32, f32, f32, f32) {
		if len(stops) == 0 do return 1, 1, 1, 1
		if t <= stops[0].t do return stops[0].c[0], stops[0].c[1], stops[0].c[2], stops[0].c[3]
		for i in 1 ..< len(stops) {
			a, b := stops[i - 1], stops[i]
			if t <= b.t {
				f := (t - a.t) / max(b.t - a.t, 0.0001)
				m := a.c + (b.c - a.c) * f
				return m[0], m[1], m[2], m[3]
			}
		}
		l := stops[len(stops) - 1].c
		return l[0], l[1], l[2], l[3]
	}
}
