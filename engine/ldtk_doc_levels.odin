package engine

import "core:fmt"
import "core:math"
import "core:mem"
import os "osx"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Ldtk_Doc levels: resizing from any edge (Level.applyNewBounds), background
// images (Level.getBgTileInfos, the "__bgPos" field) and worlds
// (Project.createWorld / removeWorld, the MultiWorlds flag).
// ============================================================================

// ----------------------------------------------------------------------------
// Worlds
// ----------------------------------------------------------------------------

// Ldtk_Doc_WorldInt / WorldStr: a world setting (the root holds them in
// single-world projects).
Ldtk_Doc_WorldInt :: proc(doc: ^Ldtk_Doc, world: int, key: string, def := 0) -> int {
	if world < 0 || world >= len(doc.worlds) do return LdtkJson_Int(doc.root, key, def)
	return LdtkJson_Int(doc.worlds[world].obj, key, def)
}

Ldtk_Doc_WorldStr :: proc(doc: ^Ldtk_Doc, world: int, key: string, def := "") -> string {
	if world < 0 || world >= len(doc.worlds) do return LdtkJson_Str(doc.root, key, def)
	return LdtkJson_Str(doc.worlds[world].obj, key, def)
}

Ldtk_Doc_WorldName :: proc(doc: ^Ldtk_Doc, world: int) -> string {
	return doc.multiWorlds ? Ldtk_Doc_WorldStr(doc, world, "identifier", "World") : "World"
}

@(private = "file")
has_flag :: proc(doc: ^Ldtk_Doc, flag: string) -> bool {
	for f in LdtkJson_Arr(doc.root, "flags") do if f.kind == .String && f.text == flag do return true
	return false
}

// Ldtk_Doc_SetFlag turns a project flag ("MultiWorlds", ...) on or off.
Ldtk_Doc_SetFlag :: proc(doc: ^Ldtk_Doc, flag: string, on: bool) {
	a := doc.allocator
	arr := LdtkJson_Get(doc.root, "flags")
	if arr == nil || arr.kind != .Array {
		arr = LdtkJson_New(.Array, a)
		LdtkJson_Set(doc.root, "flags", arr, a)
	}
	for f, i in arr.items do if f.kind == .String && f.text == flag {
		if !on do ordered_remove(&arr.items, i)
		return
	}
	if on do append(&arr.items, LdtkJson_NewString(flag, a))
}

Ldtk_Doc_HasFlag :: proc(doc: ^Ldtk_Doc, flag: string) -> bool {return has_flag(doc, flag)}

@(private = "file")
WORLD_KEYS := [?]string{"defaultLevelWidth", "defaultLevelHeight", "worldGridWidth", "worldGridHeight", "worldLayout"}

// Ldtk_Doc_SetMultiWorlds: on - the root's levels and world settings move to
// a "worlds" array (the world keeps the dummy world iid); off - back to the
// root (only with one world). Returns false when it can't.
Ldtk_Doc_SetMultiWorlds :: proc(doc: ^Ldtk_Doc, on: bool) -> bool {
	a := doc.allocator
	if on == doc.multiWorlds {
		Ldtk_Doc_SetFlag(doc, "MultiWorlds", on)
		return true
	}
	if on {
		root := doc.root
		w := LdtkJson_New(.Object, a)
		iid := LdtkJson_Str(root, "dummyWorldIid")
		if iid == "" do iid = Ldtk_Doc_Iid(context.temp_allocator)
		LdtkJson_Set(w, "iid", LdtkJson_NewString(iid, a), a)
		LdtkJson_Set(w, "identifier", LdtkJson_NewString("World", a), a)
		for k in WORLD_KEYS {
			v := LdtkJson_Get(root, k)
			LdtkJson_Set(w, k, v != nil ? LdtkJson_Clone(v, a) : LdtkJson_New(.Null, a), a)
			LdtkJson_SetNull(root, k, a)
		}
		levels := doc.worlds[0].levelsArr
		LdtkJson_Set(w, "levels", levels, a)
		LdtkJson_Set(root, "levels", LdtkJson_New(.Array, a), a)
		worlds := LdtkJson_Get(root, "worlds")
		if worlds == nil || worlds.kind != .Array {
			worlds = LdtkJson_New(.Array, a)
			LdtkJson_Set(root, "worlds", worlds, a)
		}
		clear(&worlds.items)
		append(&worlds.items, w)
		doc.worlds[0].obj = w
		doc.multiWorlds = true
	} else {
		if len(doc.worlds) != 1 do return false
		root := doc.root
		w := doc.worlds[0].obj
		for k in WORLD_KEYS {
			v := LdtkJson_Get(w, k)
			LdtkJson_Set(root, k, v != nil ? v : LdtkJson_New(.Null, a), a)
		}
		if iid := LdtkJson_Str(w, "iid"); iid != "" do LdtkJson_SetStr(root, "dummyWorldIid", iid, a)
		LdtkJson_Set(root, "levels", doc.worlds[0].levelsArr, a)
		LdtkJson_Set(root, "worlds", LdtkJson_New(.Array, a), a)
		doc.worlds[0].obj = root
		doc.multiWorlds = false
	}
	Ldtk_Doc_SetFlag(doc, "MultiWorlds", on)
	for &lv in doc.levels do lv.dirty = true
	Ldtk_Doc_UpdateToc(doc)
	Ldtk_Doc_Touch(doc)
	return true
}

// Ldtk_Doc_AddWorld adds a world with one level (turning multi-worlds on);
// returns the world's index.
Ldtk_Doc_AddWorld :: proc(doc: ^Ldtk_Doc, name := "World") -> int {
	a := doc.allocator
	Ldtk_Doc_SetMultiWorlds(doc, true)
	src := doc.worlds[len(doc.worlds) - 1].obj
	w := LdtkJson_New(.Object, a)
	LdtkJson_Set(w, "iid", LdtkJson_NewString(Ldtk_Doc_Iid(context.temp_allocator), a), a)
	LdtkJson_Set(w, "identifier", LdtkJson_NewString(Ldtk_Doc_UniqueWorldName(doc, name), a), a)
	LdtkJson_Set(w, "defaultLevelWidth", LdtkJson_NewInt(LdtkJson_Int(src, "defaultLevelWidth", 256), a), a)
	LdtkJson_Set(w, "defaultLevelHeight", LdtkJson_NewInt(LdtkJson_Int(src, "defaultLevelHeight", 256), a), a)
	LdtkJson_Set(w, "worldGridWidth", LdtkJson_NewInt(LdtkJson_Int(src, "worldGridWidth", 256), a), a)
	LdtkJson_Set(w, "worldGridHeight", LdtkJson_NewInt(LdtkJson_Int(src, "worldGridHeight", 256), a), a)
	LdtkJson_Set(w, "worldLayout", LdtkJson_NewString("Free", a), a)
	levels := LdtkJson_New(.Array, a)
	LdtkJson_Set(w, "levels", levels, a)
	append(&LdtkJson_Get(doc.root, "worlds").items, w)
	append(&doc.worlds, Ldtk_DocWorld{obj = w, levelsArr = levels})
	wi := len(doc.worlds) - 1
	Ldtk_Doc_AddLevel(doc, wi, {0, 0})
	Ldtk_Doc_UpdateToc(doc)
	Ldtk_Doc_Touch(doc)
	return wi
}

// Ldtk_Doc_UniqueWorldName: Project.fixUniqueIdStr for worlds.
Ldtk_Doc_UniqueWorldName :: proc(doc: ^Ldtk_Doc, base: string, except := -1, allocator := context.temp_allocator) -> string {
	base := Ldtk_Doc_CleanIdentifier(doc, base)
	if base == "" || base == "_" do base = "Unnamed"
	used :: proc(doc: ^Ldtk_Doc, id: string, except: int) -> bool {
		for w, i in doc.worlds do if i != except && LdtkJson_Str(w.obj, "identifier") == id do return true
		return false
	}
	if !used(doc, base, except) do return strings.clone(base, allocator)
	stem, idx := base, 2
	// "World3" -> World4...
	end := len(base)
	for end > 0 && base[end - 1] >= '0' && base[end - 1] <= '9' do end -= 1
	if end < len(base) {
		n := 0
		for c in base[end:] do n = n * 10 + int(c - '0')
		stem, idx = base[:end], n
	}
	for {
		id := fmt.tprintf("%s%d", stem, idx)
		if !used(doc, id, except) do return strings.clone(id, allocator)
		idx += 1
	}
}

Ldtk_Doc_RenameWorld :: proc(doc: ^Ldtk_Doc, world: int, name: string) {
	if !doc.multiWorlds || world < 0 || world >= len(doc.worlds) do return
	LdtkJson_SetStr(doc.worlds[world].obj, "identifier", Ldtk_Doc_UniqueWorldName(doc, name, world), doc.allocator)
	Ldtk_Doc_UpdateToc(doc)
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_RemoveWorld deletes a world and its levels (not the last one).
Ldtk_Doc_RemoveWorld :: proc(doc: ^Ldtk_Doc, world: int) -> bool {
	if !doc.multiWorlds || len(doc.worlds) <= 1 || world < 0 || world >= len(doc.worlds) do return false
	#reverse for &lv, i in doc.levels do if lv.world == world do Ldtk_Doc_RemoveLevel(doc, i)
	arr := LdtkJson_Get(doc.root, "worlds")
	for it, i in arr.items do if it == doc.worlds[world].obj {
		ordered_remove(&arr.items, i)
		break
	}
	ordered_remove(&doc.worlds, world)
	for &lv in doc.levels do if lv.world > world do lv.world -= 1
	Ldtk_Doc_UpdateNeighbours(doc)
	Ldtk_Doc_UpdateToc(doc)
	Ldtk_Doc_Touch(doc)
	return true
}

// Ldtk_Doc_SetWorldInt: a world's defaultLevelWidth / Height or
// worldGridWidth / Height.
Ldtk_Doc_SetWorldInt :: proc(doc: ^Ldtk_Doc, world: int, key: string, v: int) {
	if world < 0 || world >= len(doc.worlds) do return
	LdtkJson_SetInt(doc.worlds[world].obj, key, v, doc.allocator)
	Ldtk_Doc_Touch(doc)
}

// ----------------------------------------------------------------------------
// New level spots (LDtk's LevelSpotPicker)
// ----------------------------------------------------------------------------

Ldtk_LevelSpot :: struct {
	rect:        [4]f64, // x, y, w, h in the world (linear layouts: a marker)
	overlaps:    bool,   // no room there
	linearIndex: int,    // linear layouts: the new level's index in the world (-1 otherwise)
	ok:          bool,
}

// Ldtk_Doc_LevelSpot: LevelSpotPicker.getLevelInsertBounds - a level of the
// world's default size around a world point, pushed out of the levels it
// overlaps (Free, GridVania; snapped to the world grid / `grid`), or the
// nearest insertion point in linear layouts.
Ldtk_Doc_LevelSpot :: proc(doc: ^Ldtk_Doc, world: int, m: [2]f64, grid := 0) -> Ldtk_LevelSpot {
	w := f64(Ldtk_Doc_WorldInt(doc, world, "defaultLevelWidth", 256))
	h := f64(Ldtk_Doc_WorldInt(doc, world, "defaultLevelHeight", 256))
	layout := Ldtk_Doc_WorldStr(doc, world, "worldLayout", "Free")
	sp := Ldtk_LevelSpot{rect = {m.x - w * 0.5, m.y - h * 0.5, w, h}, linearIndex = -1, ok = true}
	overlap :: proc(doc: ^Ldtk_Doc, li: int, r: [4]f64) -> bool {
		p := Ldtk_Doc_LevelPos(doc, li)
		s := Ldtk_Doc_LevelSize(doc, li)
		return r[0] < f64(p.x + s.x) && r[0] + r[2] > f64(p.x) && r[1] < f64(p.y + s.y) && r[1] + r[3] > f64(p.y)
	}
	switch layout {
	case "LinearHorizontal", "LinearVertical":
		horiz := layout == "LinearHorizontal"
		best, bestD := -1, max(f64)
		idx := 0
		coord := 0.0
		last := -1
		for &lv, i in doc.levels {
			if lv.world != world do continue
			p := Ldtk_Doc_LevelPos(doc, i)
			c := f64(horiz ? p.x : p.y)
			if d := abs((horiz ? m.x : m.y) - c); d < bestD {
				bestD, best, coord = d, idx, c
			}
			idx += 1
			last = i
		}
		if last >= 0 {
			p := Ldtk_Doc_LevelPos(doc, last)
			s := Ldtk_Doc_LevelSize(doc, last)
			c := f64(horiz ? p.x + s.x : p.y + s.y)
			if d := abs((horiz ? m.x : m.y) - c); d < bestD do best, coord = idx, c
		}
		if best < 0 do return {ok = false}
		sp.linearIndex = best
		if horiz do sp.rect = {coord - w * 0.5, -h * 0.1, w, h * 1.2}
		else do sp.rect = {-w * 0.1, coord - h * 0.5, w * 1.2, h}
	case:
		if Ldtk_Doc_LevelAt(doc, world, {int(math.floor(m.x)), int(math.floor(m.y))}) >= 0 {
			sp.overlaps = true
		} else {
			// push it out of the levels it overlaps (the side its centre faces)
			for &lv, i in doc.levels {
				if lv.world != world || !overlap(doc, i, sp.rect) do continue
				p := Ldtk_Doc_LevelPos(doc, i)
				s := Ldtk_Doc_LevelSize(doc, i)
				cx, cy := f64(p.x) + f64(s.x) * 0.5, f64(p.y) + f64(s.y) * 0.5
				dx := sp.rect[0] + w * 0.5 - cx
				slope := dx != 0 ? (sp.rect[1] + h * 0.5 - cy) / dx : max(f64)
				if slope * f64(s.x) * 0.5 >= -f64(s.y) * 0.5 && slope * f64(s.x) * 0.5 <= f64(s.y) * 0.5 {
					sp.rect[0] = sp.rect[0] < cx ? f64(p.x) - w : f64(p.x + s.x)
				} else {
					sp.rect[1] = sp.rect[1] < cy ? f64(p.y) - h : f64(p.y + s.y)
				}
			}
			for &lv, i in doc.levels do if lv.world == world && overlap(doc, i, sp.rect) do sp.overlaps = true
		}
		if layout == "GridVania" {
			gw := f64(max(Ldtk_Doc_WorldInt(doc, world, "worldGridWidth", 256), 1))
			gh := f64(max(Ldtk_Doc_WorldInt(doc, world, "worldGridHeight", 256), 1))
			sp.rect[0] = math.round(sp.rect[0] / gw) * gw
			sp.rect[1] = math.round(sp.rect[1] / gh) * gh
		} else if grid > 0 {
			sp.rect[0] = math.round(sp.rect[0] / f64(grid)) * f64(grid)
			sp.rect[1] = math.round(sp.rect[1] / f64(grid)) * f64(grid)
		}
	}
	return sp
}

// Ldtk_Doc_AddLevelAtSpot: LevelSpotPicker.tryToCreateLevelAt - a new level
// at the spot (at `depth`), or inserted at the spot's index in linear
// layouts. Returns its index (-1: no room).
Ldtk_Doc_AddLevelAtSpot :: proc(doc: ^Ldtk_Doc, world: int, sp: Ldtk_LevelSpot, depth := 0) -> int {
	if !sp.ok || sp.overlaps do return -1
	if sp.linearIndex >= 0 {
		li := Ldtk_Doc_AddLevel(doc, world, {0, 0})
		// it was appended: move it to its index
		count := 0
		for &lv in doc.levels do if lv.world == world do count += 1
		for _ in 0 ..< count - 1 - sp.linearIndex do li = Ldtk_Doc_MoveLevelOrder(doc, li, -1)
		return li
	}
	li := Ldtk_Doc_AddLevel(doc, world, {int(math.round(sp.rect[0])), int(math.round(sp.rect[1]))}, {int(sp.rect[2]), int(sp.rect[3])})
	if depth != 0 do Ldtk_Doc_SetLevelDepth(doc, li, depth)
	return li
}

// ----------------------------------------------------------------------------
// Automatic level identifiers
// ----------------------------------------------------------------------------

// ldtk_level_set_identifier: a level's identifier (its external file too),
// keeping useAutoIdentifier.
@(private = "file")
ldtk_level_set_identifier :: proc(doc: ^Ldtk_Doc, li: int, name: string) {
	lv := &doc.levels[li]
	a := doc.allocator
	if LdtkJson_Str(lv.obj, "identifier") == name do return
	LdtkJson_SetStr(lv.obj, "identifier", name, a)
	if lv.extRoot != nil {
		LdtkJson_SetStr(lv.extRoot, "identifier", name, a)
		old := LdtkJson_Str(lv.obj, "externalRelPath")
		rel := ldtk_external_rel(doc, name)
		if old != rel && !strings.has_prefix(name, "#") {
			if old != "" do append(&doc.removedFiles, strings.clone(old, doc.heap))
			LdtkJson_SetStr(lv.obj, "externalRelPath", rel, a)
		}
	}
	lv.dirty = true
}

// Ldtk_Doc_ApplyAutoLevelIdentifiers: World.applyAutoLevelIdentifiers - the
// world's levels with an automatic identifier get the project's level name
// pattern again: %idx / %idx1 (their index in the world), %world, %depth /
// %d, %x / %y (Free and GridVania), %gx / %gy (GridVania cells).
Ldtk_Doc_ApplyAutoLevelIdentifiers :: proc(doc: ^Ldtk_Doc, world: int) {
	pattern := LdtkJson_Str(doc.root, "levelNamePattern", "Level_%idx")
	layout := Ldtk_Doc_WorldStr(doc, world, "worldLayout", "Free")
	gw := max(Ldtk_Doc_WorldInt(doc, world, "worldGridWidth", 256), 1)
	gh := max(Ldtk_Doc_WorldInt(doc, world, "worldGridHeight", 256), 1)
	left, top := max(int), max(int)
	for &lv, i in doc.levels do if lv.world == world {
		p := Ldtk_Doc_LevelPos(doc, i)
		left, top = min(left, p.x), min(top, p.y)
	}
	// free the automatic names first (they swap places)
	uniq := 0
	for &lv, i in doc.levels do if lv.world == world && LdtkJson_Bool(lv.obj, "useAutoIdentifier") {
		ldtk_level_set_identifier(doc, i, fmt.tprintf("#%d", uniq))
		uniq += 1
	}
	idx := 0
	changed := false
	for &lv, i in doc.levels {
		if lv.world != world do continue
		defer idx += 1
		if !LdtkJson_Bool(lv.obj, "useAutoIdentifier") do continue
		p := Ldtk_Doc_LevelPos(doc, i)
		depth := LdtkJson_Int(lv.obj, "worldDepth")
		free := layout == "Free" || layout == "GridVania"
		id := pattern
		rep :: proc(s, key, v: string) -> string {
			out, _ := strings.replace_all(s, key, v, context.temp_allocator)
			return out
		}
		id = rep(id, "%depth", fmt.tprint(depth))
		id = rep(id, "%world", Ldtk_Doc_WorldName(doc, world))
		id = rep(id, "%idx1", fmt.tprint(idx + 1))
		id = rep(id, "%idx", fmt.tprint(idx))
		id = rep(id, "%gx", layout == "GridVania" ? fmt.tprint((p.x - left) / gw) : "")
		id = rep(id, "%gy", layout == "GridVania" ? fmt.tprint((p.y - top) / gh) : "")
		id = rep(id, "%x", free ? fmt.tprint(p.x) : "")
		id = rep(id, "%y", free ? fmt.tprint(p.y) : "")
		id = rep(id, "%d", fmt.tprint(depth))
		// Project.fixUniqueIdStr among every level
		base := Ldtk_Doc_CleanIdentifier(doc, id)
		used :: proc(doc: ^Ldtk_Doc, id: string, except: int) -> bool {
			for &l, k in doc.levels do if k != except && LdtkJson_Str(l.obj, "identifier") == id do return true
			return false
		}
		name := base
		if used(doc, name, i) {
			stem, n := ldtk_name_stem(base)
			for {
				name = fmt.tprintf("%s%d", stem, n)
				if !used(doc, name, i) do break
				n += 1
			}
		}
		ldtk_level_set_identifier(doc, i, name)
		changed = true
	}
	if changed {
		Ldtk_Doc_UpdateToc(doc)
		Ldtk_Doc_Touch(doc)
	}
}

// Ldtk_Doc_SetLevelAutoIdentifier turns a level's automatic identifier on /
// off (on: the pattern applies at once).
Ldtk_Doc_SetLevelAutoIdentifier :: proc(doc: ^Ldtk_Doc, li: int, on: bool) {
	lv := &doc.levels[li]
	a := doc.allocator
	LdtkJson_SetBool(lv.obj, "useAutoIdentifier", on, a)
	if lv.extRoot != nil do LdtkJson_SetBool(lv.extRoot, "useAutoIdentifier", on, a)
	lv.dirty = true
	if on do Ldtk_Doc_ApplyAutoLevelIdentifiers(doc, lv.world)
	Ldtk_Doc_Touch(doc)
}

// ----------------------------------------------------------------------------
// Resizing
// ----------------------------------------------------------------------------

// Ldtk_Doc_ResizeLevelBounds: Level.applyNewBounds - the new bounds relative
// to the level's top-left (left / top move the level in the world; cells and
// entities keep their world positions). Entities that end up outside are
// removed unless their def allows it; returns how many.
Ldtk_Doc_ResizeLevelBounds :: proc(doc: ^Ldtk_Doc, li: int, left, top, w, h: int) -> int {
	lv := &doc.levels[li]
	a := doc.allocator
	if left != 0 || top != 0 {
		p := Ldtk_Doc_LevelPos(doc, li)
		if !ldtk_linear_layout(doc, li) {
			ldtk_level_set_int(doc, lv, "worldX", p.x + left)
			ldtk_level_set_int(doc, lv, "worldY", p.y + top)
		}
	}
	ldtk_level_set_int(doc, lv, "pxWid", max(w, 1))
	ldtk_level_set_int(doc, lv, "pxHei", max(h, 1))
	removed := 0
	for &ly, layer in lv.layers {
		d := Ldtk_Doc_LayerDef(doc, &ly)
		if d == nil do continue
		g := max(d.gridSize, 1)
		inst := [2]int{LdtkJson_Int(ly.obj, "pxOffsetX"), LdtkJson_Int(ly.obj, "pxOffsetY")}
		total := inst - {left, top}
		newOff := [2]int{total.x % g, total.y % g} // JS % keeps the sign
		cw := max(int(math.ceil(f64(w - newOff.x) / f64(g))), 0)
		ch := max(int(math.ceil(f64(h - newOff.y) / f64(g))), 0)
		dc := [2]int{total.x / g, total.y / g} // Std.int truncates
		switch d.type {
		case .IntGrid, .Tiles, .AutoLayer:
			if d.type == .IntGrid || ly.cWid != cw || ly.cHei != ch || dc != {} {
				grid := make([]i32, cw * ch, doc.heap)
				if d.type == .IntGrid {
					for y in 0 ..< ly.cHei do for x in 0 ..< ly.cWid {
						nx, ny := x + dc.x, y + dc.y
						if nx >= 0 && ny >= 0 && nx < cw && ny < ch do grid[nx + ny * cw] = ly.intGrid[x + y * ly.cWid]
					}
				}
				delete(ly.intGrid, doc.heap)
				ly.intGrid = grid
			}
			k := 0
			for t in ly.gridTiles {
				x := int(t.coord) % max(ly.cWid, 1) + dc.x
				y := int(t.coord) / max(ly.cWid, 1) + dc.y
				if x < 0 || y < 0 || x >= cw || y >= ch do continue
				nt := t
				nt.coord = i32(x + y * cw)
				nt.px = {i32(x * g), i32(y * g)}
				ly.gridTiles[k] = nt
				k += 1
			}
			resize(&ly.gridTiles, k)
		case .Entities:
			ents := Ldtk_Doc_Entities(doc, li, layer)
			out := make([dynamic]^LdtkJson, context.temp_allocator)
			for ent in ents {
				px := LdtkJson_Arr(ent, "px")
				if len(px) < 2 do continue
				np := [2]int{int(px[0].num) + dc.x * g, int(px[1].num) + dc.y * g}
				Ldtk_Doc_MoveEntity(doc, li, layer, ent, np)
				for fi in LdtkJson_Arr(ent, "fieldInstances") {
					fd := Ldtk_Doc_FieldDef(doc, LdtkJson_Int(fi, "defUid", -1))
					if fd == nil || Ldtk_FieldKindOf(fd) != .Point || dc == {} do continue
					for i in 0 ..< Ldtk_Doc_FieldArrayLen(doc, fi) {
						r := Ldtk_Doc_FieldRaw(fi, i)
						if r.isNull || r.isDefault do continue
						parts := strings.split(r.text, ",", context.temp_allocator)
						if len(parts) != 2 do continue
						cx, cy := ldtk_atoi(parts[0]), ldtk_atoi(parts[1])
						Ldtk_Doc_SetFieldRaw(doc, fi, i, fmt.tprintf("%d,%d", cx + dc.x, cy + dc.y))
					}
				}
				ed := Ldtk_Doc_EntityDef(doc, LdtkJson_Int(ent, "defUid", -1))
				allow := ed != nil && LdtkJson_Bool(ed.obj, "allowOutOfBounds")
				if !allow && (np.x < 0 || np.y < 0 || np.x >= w || np.y >= h) do append(&out, ent)
			}
			for ent in out do Ldtk_Doc_RemoveEntity(doc, li, layer, ent)
			removed += len(out)
		}
		ly.cWid, ly.cHei = cw, ch
		LdtkJson_SetInt(ly.obj, "__cWid", cw, a)
		LdtkJson_SetInt(ly.obj, "__cHei", ch, a)
		LdtkJson_SetInt(ly.obj, "pxOffsetX", newOff.x, a)
		LdtkJson_SetInt(ly.obj, "pxOffsetY", newOff.y, a)
		LdtkJson_SetInt(ly.obj, "__pxTotalOffsetX", newOff.x + d.pxOffset.x, a)
		LdtkJson_SetInt(ly.obj, "__pxTotalOffsetY", newOff.y + d.pxOffset.y, a)
		ly.cellsDirty = true
	}
	// entities' world positions follow the level
	for _, layer in lv.layers do for ent in Ldtk_Doc_Entities(doc, li, layer) do ldtk_entity_cached(doc, li, layer, ent)
	ldtk_update_bg_pos(doc, li)
	Ldtk_Doc_ApplyRulesFull(doc, li)
	lv.dirty = true
	Ldtk_Doc_UpdateNeighbours(doc)
	Ldtk_Doc_UpdateToc(doc)
	Ldtk_Doc_Touch(doc)
	return removed
}

@(private = "file")
ldtk_atoi :: proc(s: string) -> int {
	s := strings.trim_space(s)
	neg := strings.has_prefix(s, "-")
	if neg do s = s[1:]
	n := 0
	for c in s do if c >= '0' && c <= '9' do n = n * 10 + int(c - '0')
	return neg ? -n : n
}

// ----------------------------------------------------------------------------
// Background image
// ----------------------------------------------------------------------------

Ldtk_BgPos :: enum u8 {
	Unscaled,
	Contain,
	Cover,
	CoverDirty,
	Repeat,
}

LDTK_BG_POS_NAMES := [Ldtk_BgPos]string {
	.Unscaled   = "Unscaled",
	.Contain    = "Contain",
	.Cover      = "Cover",
	.CoverDirty = "CoverDirty",
	.Repeat     = "Repeat",
}

// LDtk's labels for them.
LDTK_BG_POS_LABELS := [Ldtk_BgPos]string {
	.Unscaled   = "Not scaled",
	.Contain    = "Fit inside (keep aspect ratio)",
	.Cover      = "Cover level (keep aspect ratio)",
	.CoverDirty = "Cover (dirty scaling)",
	.Repeat     = "Repeat",
}

// Ldtk_LevelBg: where a level's background image is drawn (getBgTileInfos):
// the image's cropRect is drawn at topLeft scaled by scale; Repeat tiles
// the crop over the level, aligned by the pivot.
Ldtk_LevelBg :: struct {
	crop:    [4]f64, // x, y, w, h in the image
	scale:   [2]f64,
	topLeft: [2]int,
	pos:     Ldtk_BgPos,
	pivot:   [2]f64,
	imgSize: [2]int,
}

Ldtk_BgPosOf :: proc(name: string) -> (Ldtk_BgPos, bool) {
	for n, p in LDTK_BG_POS_NAMES do if n == name do return p, true
	return .Cover, false
}

// Ldtk_LevelBgInfo: Level.getBgTileInfos for a level size and image size.
Ldtk_LevelBgInfo :: proc(level: [2]int, img: [2]int, pos: Ldtk_BgPos, pivot: [2]f64) -> Ldtk_LevelBg {
	bw, bh := f64(max(img.x, 1)), f64(max(img.y, 1))
	pw, ph := f64(level.x), f64(level.y)
	sx, sy := 1.0, 1.0
	switch pos {
	case .Unscaled, .Repeat:
	case .Contain: sx = min(pw / bw, ph / bh); sy = sx
	case .Cover: sx = max(pw / bw, ph / bh); sy = sx
	case .CoverDirty: sx, sy = pw / bw, ph / bh
	}
	tw := min(bw, pw / sx)
	th := min(bh, ph / sy)
	return {
		crop = {pivot.x * (bw - tw), pivot.y * (bh - th), tw, th},
		scale = {sx, sy},
		topLeft = {int(pivot.x * (pw - tw * sx)), int(pivot.y * (ph - th * sy))},
		pos = pos,
		pivot = pivot,
		imgSize = img,
	}
}

// Ldtk_ImageSize reads an image's size (PNG: from its header).
Ldtk_ImageSize :: proc(path: string) -> ([2]int, bool) {
	if strings.has_suffix(strings.to_lower(path, context.temp_allocator), ".png") {
		f, err := os.open(path)
		if err != nil do return {}, false
		defer os.close(f)
		hdr: [24]u8
		n, rerr := os.read(f, hdr[:])
		if rerr != nil || n < 24 || hdr[1] != 'P' || hdr[2] != 'N' || hdr[3] != 'G' do return {}, false
		be :: proc(b: []u8) -> int {return int(b[0]) << 24 | int(b[1]) << 16 | int(b[2]) << 8 | int(b[3])}
		return {be(hdr[16:20]), be(hdr[20:24])}, true
	}
	if !os.exists(path) do return {}, false
	img := rl.LoadImage(strings.clone_to_cstring(path, context.temp_allocator))
	defer rl.UnloadImage(img)
	if img.data == nil do return {}, false
	return {int(img.width), int(img.height)}, true
}

// Ldtk_Doc_LevelBg: the level's background image placement (false: none, or
// the image can't be read).
Ldtk_Doc_LevelBg :: proc(doc: ^Ldtk_Doc, li: int) -> (Ldtk_LevelBg, bool) {
	lv := &doc.levels[li]
	rel := LdtkJson_Str(lv.obj, "bgRelPath")
	if rel == "" do return {}, false
	p, _ := filepath.join({doc.dir, rel}, context.temp_allocator)
	size, ok := Ldtk_ImageSize(p)
	if !ok do return {}, false
	pos, _ := Ldtk_BgPosOf(LdtkJson_Str(lv.obj, "bgPos", "Cover"))
	pivot := [2]f64{LdtkJson_Float(lv.obj, "bgPivotX", 0.5), LdtkJson_Float(lv.obj, "bgPivotY", 0.5)}
	return Ldtk_LevelBgInfo(Ldtk_Doc_LevelSize(doc, li), size, pos, pivot), true
}

// ldtk_update_bg_pos writes "__bgPos" (null without an image).
@(private)
ldtk_update_bg_pos :: proc(doc: ^Ldtk_Doc, li: int) {
	lv := &doc.levels[li]
	a := doc.allocator
	bg, ok := Ldtk_Doc_LevelBg(doc, li)
	for o in ([]^LdtkJson{lv.obj, lv.extRoot}) {
		if o == nil do continue
		if !ok {
			LdtkJson_SetNull(o, "__bgPos", a)
			continue
		}
		v := LdtkJson_New(.Object, a)
		LdtkJson_Set(v, "topLeftPx", jarr2i(bg.topLeft, a), a)
		sc := LdtkJson_New(.Array, a)
		append(&sc.items, LdtkJson_NewFloat(bg.scale.x, a), LdtkJson_NewFloat(bg.scale.y, a))
		LdtkJson_Set(v, "scale", sc, a)
		cr := LdtkJson_New(.Array, a)
		for c in bg.crop do append(&cr.items, LdtkJson_NewFloat(c, a))
		LdtkJson_Set(v, "cropRect", cr, a)
		LdtkJson_Set(o, "__bgPos", v, a)
	}
	lv.dirty = true
}

@(private = "file")
jarr2i :: proc(v: [2]int, a: mem.Allocator) -> ^LdtkJson {
	arr := LdtkJson_New(.Array, a)
	append(&arr.items, LdtkJson_NewInt(v.x, a), LdtkJson_NewInt(v.y, a))
	return arr
}

@(private = "file")
level_set :: proc(doc: ^Ldtk_Doc, li: int, key: string, v: ^LdtkJson) {
	lv := &doc.levels[li]
	a := doc.allocator
	LdtkJson_Set(lv.obj, key, v, a)
	if lv.extRoot != nil do LdtkJson_Set(lv.extRoot, key, LdtkJson_Clone(v, a), a)
}

// Ldtk_Doc_SetLevelBg: the background image ("" removes it). A first image
// covers the level (LDtk's default).
Ldtk_Doc_SetLevelBg :: proc(doc: ^Ldtk_Doc, li: int, relPath: string) {
	a := doc.allocator
	lv := &doc.levels[li]
	if relPath == "" {
		level_set(doc, li, "bgRelPath", LdtkJson_New(.Null, a))
		level_set(doc, li, "bgPos", LdtkJson_New(.Null, a))
	} else {
		first := LdtkJson_Str(lv.obj, "bgRelPath") == ""
		level_set(doc, li, "bgRelPath", LdtkJson_NewString(relPath, a))
		if first || LdtkJson_Str(lv.obj, "bgPos") == "" do level_set(doc, li, "bgPos", LdtkJson_NewString("Cover", a))
	}
	ldtk_update_bg_pos(doc, li)
	Ldtk_Doc_Touch(doc)
}

Ldtk_Doc_SetLevelBgPos :: proc(doc: ^Ldtk_Doc, li: int, pos: Ldtk_BgPos) {
	if LdtkJson_Str(doc.levels[li].obj, "bgRelPath") == "" do return
	level_set(doc, li, "bgPos", LdtkJson_NewString(LDTK_BG_POS_NAMES[pos], doc.allocator))
	ldtk_update_bg_pos(doc, li)
	Ldtk_Doc_Touch(doc)
}

Ldtk_Doc_SetLevelBgPivot :: proc(doc: ^Ldtk_Doc, li: int, pivot: [2]f64) {
	a := doc.allocator
	level_set(doc, li, "bgPivotX", LdtkJson_NewFloat(clamp(pivot.x, 0, 1), a))
	level_set(doc, li, "bgPivotY", LdtkJson_NewFloat(clamp(pivot.y, 0, 1), a))
	ldtk_update_bg_pos(doc, li)
	Ldtk_Doc_Touch(doc)
}
