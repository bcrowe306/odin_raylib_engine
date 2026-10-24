package engine

import "core:fmt"
import "core:strings"

// ============================================================================
// Editing auto-layer rules (LDtk's EditAllAutoLayerRules panel and its
// dialogs: RuleEditor, RuleGroupRemap, RulesWizard)
//
// Groups: rename, duplicate (remapping IntGrid values and shifting tiles),
// reorder, colour, icon, optional, biome requirements, out-of-bounds value
// for all rules. Rules: insert, duplicate, reorder / move to another group,
// copy / paste as text. The Rules Assistant builds a group from "wall
// fragments" (the tiles for each wall / corner / turn shape) - with the
// rules' flips filled in where a fragment is the mirror of another, exactly
// as RulesWizard.createRules does.
// Take a project undo step first; these regenerate the auto tiles.
// ============================================================================

@(private = "file")
ldtk_layer_groups :: proc(doc: ^Ldtk_Doc, layerUid: int) -> ^LdtkJson {
	di := Ldtk_Doc_LayerDefIndex(doc, layerUid)
	if di < 0 do return nil
	g := LdtkJson_Get(doc.layerDefs[di].obj, "autoRuleGroups")
	if g == nil || g.kind != .Array {
		g = LdtkJson_New(.Array, doc.allocator)
		LdtkJson_Set(doc.layerDefs[di].obj, "autoRuleGroups", g, doc.allocator)
	}
	return g
}

Ldtk_Doc_FindRuleGroup :: proc(doc: ^Ldtk_Doc, groupUid: int) -> (group: ^LdtkJson, layerUid: int, index: int) {
	for &d in doc.layerDefs {
		for g, i in LdtkJson_Arr(d.obj, "autoRuleGroups") do if LdtkJson_Int(g, "uid", -1) == groupUid do return g, d.uid, i
	}
	return nil, -1, -1
}

Ldtk_Doc_RenameRuleGroup :: proc(doc: ^Ldtk_Doc, groupUid: int, name: string) {
	g, layer, _ := Ldtk_Doc_FindRuleGroup(doc, groupUid)
	if g == nil do return
	LdtkJson_SetStr(g, "name", name, doc.allocator)
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_Touch(doc)
	_ = layer
}

// Ldtk_Doc_MoveRuleGroup moves a group up / down (rules run top to bottom).
Ldtk_Doc_MoveRuleGroup :: proc(doc: ^Ldtk_Doc, groupUid: int, delta: int) -> bool {
	_, layer, i := Ldtk_Doc_FindRuleGroup(doc, groupUid)
	if layer < 0 do return false
	arr := ldtk_layer_groups(doc, layer)
	j := i + delta
	if j < 0 || j >= len(arr.items) do return false
	arr.items[i], arr.items[j] = arr.items[j], arr.items[i]
	Ldtk_Doc_RulesChanged(doc, layer)
	return true
}

Ldtk_Doc_RemoveRuleGroup :: proc(doc: ^Ldtk_Doc, groupUid: int) -> bool {
	_, layer, i := Ldtk_Doc_FindRuleGroup(doc, groupUid)
	if layer < 0 do return false
	ordered_remove(&ldtk_layer_groups(doc, layer).items, i)
	ldtk_forget_optional(doc, groupUid)
	Ldtk_Doc_RulesChanged(doc, layer)
	return true
}

// ldtk_forget_optional removes a group from every layer instance's
// optionalRules.
@(private = "file")
ldtk_forget_optional :: proc(doc: ^Ldtk_Doc, groupUid: int) {
	for &lv in doc.levels {
		for &ly in lv.layers {
			opt := LdtkJson_Get(ly.obj, "optionalRules")
			if opt == nil do continue
			for o, i in opt.items do if int(o.num) == groupUid {
				ordered_remove(&opt.items, i)
				lv.dirty = true
				break
			}
		}
	}
}

// Ldtk_Doc_SetRuleGroupOptional: an optional group is off by default and
// enabled per level; turning it back into a global group forgets the
// per-level states.
Ldtk_Doc_SetRuleGroupOptional :: proc(doc: ^Ldtk_Doc, groupUid: int, optional: bool) {
	g, layer, _ := Ldtk_Doc_FindRuleGroup(doc, groupUid)
	if g == nil do return
	LdtkJson_SetBool(g, "isOptional", optional, doc.allocator)
	if !optional do ldtk_forget_optional(doc, groupUid)
	Ldtk_Doc_RulesChanged(doc, layer)
}

// Ldtk_Doc_SetRuleGroupColor: "#RRGGBB", "" = none.
Ldtk_Doc_SetRuleGroupColor :: proc(doc: ^Ldtk_Doc, groupUid: int, hex: string) {
	g, _, _ := Ldtk_Doc_FindRuleGroup(doc, groupUid)
	if g == nil do return
	if hex == "" do LdtkJson_SetNull(g, "color", doc.allocator)
	else do LdtkJson_SetStr(g, "color", hex, doc.allocator)
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_SetRuleGroupIcon: a tile rectangle as the group's icon (w = 0: none).
Ldtk_Doc_SetRuleGroupIcon :: proc(doc: ^Ldtk_Doc, groupUid: int, tilesetUid: int, rect: [4]int) {
	a := doc.allocator
	g, _, _ := Ldtk_Doc_FindRuleGroup(doc, groupUid)
	if g == nil do return
	if rect[2] <= 0 {
		LdtkJson_SetNull(g, "icon", a)
	} else {
		o := LdtkJson_New(.Object, a)
		LdtkJson_SetInt(o, "tilesetUid", tilesetUid, a)
		LdtkJson_SetInt(o, "x", rect[0], a)
		LdtkJson_SetInt(o, "y", rect[1], a)
		LdtkJson_SetInt(o, "w", rect[2], a)
		LdtkJson_SetInt(o, "h", rect[3], a)
		LdtkJson_Set(g, "icon", o, a)
	}
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_SetRuleGroupBiome: the enum values a level's biome field must
// have for the group to apply (mode 0: any of them, 1: all of them).
Ldtk_Doc_SetRuleGroupBiome :: proc(doc: ^Ldtk_Doc, groupUid: int, values: []string, mode: int) {
	a := doc.allocator
	g, layer, _ := Ldtk_Doc_FindRuleGroup(doc, groupUid)
	if g == nil do return
	arr := LdtkJson_New(.Array, a)
	for v in values do append(&arr.items, LdtkJson_NewString(v, a))
	LdtkJson_Set(g, "requiredBiomeValues", arr, a)
	LdtkJson_SetInt(g, "biomeRequirementMode", mode, a)
	Ldtk_Doc_RulesChanged(doc, layer)
}

// Ldtk_Doc_SetRuleGroupOutOfBounds sets every rule's out-of-bounds value
// (-1: null - cells outside the level don't match).
Ldtk_Doc_SetRuleGroupOutOfBounds :: proc(doc: ^Ldtk_Doc, groupUid: int, value: int) {
	g, layer, _ := Ldtk_Doc_FindRuleGroup(doc, groupUid)
	if g == nil do return
	for r in LdtkJson_Arr(g, "rules") {
		if value < 0 do LdtkJson_SetNull(r, "outOfBoundsValue", doc.allocator)
		else do LdtkJson_SetInt(r, "outOfBoundsValue", value, doc.allocator)
	}
	Ldtk_Doc_RulesChanged(doc, layer)
}

// ldtk_rule_remap: a rule copy with new uids, IntGrid values remapped and
// tiles shifted by `tileOffset` cells.
@(private = "file")
ldtk_rule_remap :: proc(doc: ^Ldtk_Doc, r: ^LdtkJson, remap: map[i32]i32, tileOffset: [2]int, tsCWid: int) -> ^LdtkJson {
	a := doc.allocator
	c := LdtkJson_Clone(r, a)
	LdtkJson_SetInt(c, "uid", Ldtk_Doc_NextUid(doc), a)
	if pat := LdtkJson_Get(c, "pattern"); pat != nil {
		for v, i in pat.items {
			x := i32(v.num)
			if to, ok := remap[x]; ok do pat.items[i] = LdtkJson_NewInt(int(to), a)
			else if to2, ok2 := remap[-x]; ok2 do pat.items[i] = LdtkJson_NewInt(-int(to2), a)
		}
	}
	if ob := LdtkJson_Get(c, "outOfBoundsValue"); ob != nil && ob.kind == .Number {
		if to, ok := remap[i32(ob.num)]; ok do LdtkJson_SetInt(c, "outOfBoundsValue", int(to), a)
	}
	if tileOffset != {} {
		for rect in LdtkJson_Arr(c, "tileRectsIds") {
			for t, i in rect.items do rect.items[i] = LdtkJson_NewInt(int(t.num) + tileOffset.x + tileOffset.y * tsCWid, a)
		}
	}
	return c
}

// Ldtk_Doc_DuplicateRuleGroup copies a group after it (RuleGroupRemap):
// IntGrid values remapped (old -> new), tiles shifted by tileOffset cells.
// Returns the copy's uid.
Ldtk_Doc_DuplicateRuleGroup :: proc(doc: ^Ldtk_Doc, groupUid: int, name: string = "", remap: map[i32]i32 = nil, tileOffset: [2]int = {}) -> int {
	a := doc.allocator
	g, layer, i := Ldtk_Doc_FindRuleGroup(doc, groupUid)
	if g == nil do return -1
	d := &doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, layer)]
	ts := Ldtk_Doc_Tileset(doc, d.tilesetUid)
	cw := ts != nil ? ts.cWid : 1
	c := LdtkJson_Clone(g, a)
	uid := Ldtk_Doc_NextUid(doc)
	LdtkJson_SetInt(c, "uid", uid, a)
	LdtkJson_SetStr(c, "name", name != "" ? name : fmt.tprintf("%s copy", LdtkJson_Str(g, "name")), a)
	rules := LdtkJson_New(.Array, a)
	for r in LdtkJson_Arr(g, "rules") do append(&rules.items, ldtk_rule_remap(doc, r, remap, tileOffset, cw))
	LdtkJson_Set(c, "rules", rules, a)
	inject_at(&ldtk_layer_groups(doc, layer).items, i + 1, c)
	Ldtk_Doc_RulesChanged(doc, layer)
	return uid
}

// Ldtk_Doc_RuleGroupValues: the IntGrid values a group's patterns use (for
// the remap form).
Ldtk_Doc_RuleGroupValues :: proc(doc: ^Ldtk_Doc, groupUid: int) -> []i32 {
	g, _, _ := Ldtk_Doc_FindRuleGroup(doc, groupUid)
	out := make([dynamic]i32, context.temp_allocator)
	for r in LdtkJson_Arr(g, "rules") {
		for v in LdtkJson_Arr(r, "pattern") {
			x := abs(i32(v.num))
			if x == 0 || x == LDTK_AUTO_LAYER_ANYTHING do continue
			found := false
			for y in out do if y == x do found = true
			if !found do append(&out, x)
		}
	}
	return out[:]
}

// ldtk_rule_place: (group json, index) of a rule.
@(private = "file")
ldtk_rule_place :: proc(doc: ^Ldtk_Doc, ruleUid: int) -> (^LdtkJson, int, int) {
	r, g, layer := Ldtk_Doc_FindRule(doc, ruleUid)
	if r == nil do return nil, -1, -1
	for x, i in LdtkJson_Arr(g, "rules") do if x == r do return g, i, layer
	return nil, -1, -1
}

// Ldtk_Doc_InsertRule adds an empty 3x3 rule at an index of a group.
Ldtk_Doc_InsertRule :: proc(doc: ^Ldtk_Doc, groupUid: int, index: int, value := 1, tileId := 0) -> int {
	g, layer, _ := Ldtk_Doc_FindRuleGroup(doc, groupUid)
	if g == nil do return -1
	uid := Ldtk_Doc_AddRule(doc, layer, groupUid, 3, value, tileId) // appended
	rules := LdtkJson_Get(g, "rules")
	last := rules.items[len(rules.items) - 1]
	ordered_remove(&rules.items, len(rules.items) - 1)
	inject_at(&rules.items, clamp(index, 0, len(rules.items)), last)
	Ldtk_Doc_RulesChanged(doc, layer)
	return uid
}

// Ldtk_Doc_DuplicateRule copies a rule right after it; returns the copy's uid.
Ldtk_Doc_DuplicateRule :: proc(doc: ^Ldtk_Doc, ruleUid: int) -> int {
	g, i, layer := ldtk_rule_place(doc, ruleUid)
	if g == nil do return -1
	c := ldtk_rule_remap(doc, LdtkJson_Arr(g, "rules")[i], nil, {}, 1)
	inject_at(&LdtkJson_Get(g, "rules").items, i + 1, c)
	Ldtk_Doc_RulesChanged(doc, layer)
	return LdtkJson_Int(c, "uid")
}

// Ldtk_Doc_MoveRule moves a rule up / down; at a group's end it goes into
// the next / previous group of the layer.
Ldtk_Doc_MoveRule :: proc(doc: ^Ldtk_Doc, ruleUid: int, delta: int) -> bool {
	g, i, layer := ldtk_rule_place(doc, ruleUid)
	if g == nil do return false
	rules := LdtkJson_Get(g, "rules")
	j := i + delta
	if j >= 0 && j < len(rules.items) {
		rules.items[i], rules.items[j] = rules.items[j], rules.items[i]
		Ldtk_Doc_RulesChanged(doc, layer)
		return true
	}
	groups := ldtk_layer_groups(doc, layer)
	gi := -1
	for x, k in groups.items do if x == g do gi = k
	gj := gi + (delta < 0 ? -1 : 1)
	if gj < 0 || gj >= len(groups.items) do return false
	r := rules.items[i]
	ordered_remove(&rules.items, i)
	other := LdtkJson_Get(groups.items[gj], "rules")
	if delta < 0 do append(&other.items, r)
	else do inject_at(&other.items, 0, r)
	Ldtk_Doc_RulesChanged(doc, layer)
	return true
}

// Ldtk_Doc_RuleText: a rule as JSON text (the clipboard).
Ldtk_Doc_RuleText :: proc(doc: ^Ldtk_Doc, ruleUid: int, allocator := context.allocator) -> string {
	r, _, _ := Ldtk_Doc_FindRule(doc, ruleUid)
	if r == nil do return ""
	return LdtkJson_ToString(r, .Minified, allocator)
}

// Ldtk_Doc_RuleGroupText: a group as JSON text.
Ldtk_Doc_RuleGroupText :: proc(doc: ^Ldtk_Doc, groupUid: int, allocator := context.allocator) -> string {
	g, _, _ := Ldtk_Doc_FindRuleGroup(doc, groupUid)
	if g == nil do return ""
	return LdtkJson_ToString(g, .Minified, allocator)
}

// Ldtk_Doc_PasteRule inserts a copied rule into a group (after `afterRule`,
// or at the end); returns the new rule's uid.
Ldtk_Doc_PasteRule :: proc(doc: ^Ldtk_Doc, groupUid: int, text: string, afterRule := -1) -> int {
	g, layer, _ := Ldtk_Doc_FindRuleGroup(doc, groupUid)
	if g == nil do return -1
	r, ok := LdtkJson_Parse(text, doc.allocator)
	if !ok || r.kind != .Object || LdtkJson_Get(r, "pattern") == nil do return -1
	c := ldtk_rule_remap(doc, r, nil, {}, 1)
	rules := LdtkJson_Get(g, "rules")
	at := len(rules.items)
	for x, i in rules.items do if LdtkJson_Int(x, "uid", -1) == afterRule do at = i + 1
	inject_at(&rules.items, at, c)
	Ldtk_Doc_RulesChanged(doc, layer)
	return LdtkJson_Int(c, "uid")
}

// Ldtk_Doc_PasteRuleGroup adds a copied group to a layer; returns its uid.
Ldtk_Doc_PasteRuleGroup :: proc(doc: ^Ldtk_Doc, layerUid: int, text: string) -> int {
	a := doc.allocator
	g, ok := LdtkJson_Parse(text, a)
	if !ok || g.kind != .Object || LdtkJson_Get(g, "rules") == nil do return -1
	arr := ldtk_layer_groups(doc, layerUid)
	if arr == nil do return -1
	uid := Ldtk_Doc_NextUid(doc)
	LdtkJson_SetInt(g, "uid", uid, a)
	rules := LdtkJson_New(.Array, a)
	for r in LdtkJson_Arr(g, "rules") do append(&rules.items, ldtk_rule_remap(doc, r, nil, {}, 1))
	LdtkJson_Set(g, "rules", rules, a)
	append(&arr.items, g)
	Ldtk_Doc_RulesChanged(doc, layerUid)
	return uid
}

// ----------------------------------------------------------------------------
// The Rules Assistant (RulesWizard)
// ----------------------------------------------------------------------------

// The fragments, in LDtk's order (the order the rules are created in).
Ldtk_WallFragment :: enum u8 {
	Single, Cross, Turn_NW, Turn_NE, Turn_SE, Turn_SW, Diagonal_SW_NE, Diagonal_NW_SE,
	Corner_NW_to_N, Corner_NW_to_W, Corner_NW_to_NW, Corner_NE_to_N, Corner_NE_to_E, Corner_NE_to_NE,
	Corner_SE_to_E, Corner_SE_to_S, Corner_SE_to_SE, Corner_SW_to_S, Corner_SW_to_W, Corner_SW_to_SW,
	TCross_N, TCross_E, TCross_S, TCross_W, TWall_W, TWall_E, TWall_S, TWall_N,
	Horizontal_W, Horizontal_E, Horizontal_Mid, Vertical_N, Vertical_S, Vertical_Mid,
	ExtCorner_NW, ExtCorner_NE, ExtCorner_SE, ExtCorner_SW, Wall_N, Wall_E, Wall_S, Wall_W,
	InCorner_NW, InCorner_NE, InCorner_SE, InCorner_SW, Full,
}

// Where each fragment sits in the Assistant's grid (column, row).
LDTK_FRAGMENT_AT := [Ldtk_WallFragment][2]int{
	.Single = {3, 1}, .Cross = {3, 2}, .Turn_NW = {2, 3}, .Turn_NE = {3, 3}, .Turn_SE = {3, 4}, .Turn_SW = {2, 4},
	.Diagonal_SW_NE = {10, 2}, .Diagonal_NW_SE = {10, 3},
	.Corner_NW_to_N = {6, 2}, .Corner_NW_to_W = {6, 0}, .Corner_NW_to_NW = {10, 0},
	.Corner_NE_to_N = {7, 2}, .Corner_NE_to_E = {7, 0}, .Corner_NE_to_NE = {11, 0},
	.Corner_SE_to_E = {7, 1}, .Corner_SE_to_S = {7, 3}, .Corner_SE_to_SE = {11, 1},
	.Corner_SW_to_S = {6, 3}, .Corner_SW_to_W = {6, 1}, .Corner_SW_to_SW = {10, 1},
	.TCross_N = {8, 3}, .TCross_E = {8, 2}, .TCross_S = {9, 2}, .TCross_W = {9, 3},
	.TWall_W = {8, 0}, .TWall_E = {9, 0}, .TWall_S = {8, 1}, .TWall_N = {9, 1},
	.Horizontal_W = {3, 0}, .Horizontal_E = {5, 0}, .Horizontal_Mid = {4, 0},
	.Vertical_N = {4, 1}, .Vertical_S = {4, 3}, .Vertical_Mid = {4, 2},
	.ExtCorner_NW = {0, 0}, .ExtCorner_NE = {2, 0}, .ExtCorner_SE = {2, 2}, .ExtCorner_SW = {0, 2},
	.Wall_N = {1, 0}, .Wall_E = {2, 1}, .Wall_S = {1, 2}, .Wall_W = {0, 1},
	.InCorner_NW = {0, 3}, .InCorner_NE = {1, 3}, .InCorner_SE = {1, 4}, .InCorner_SW = {0, 4},
	.Full = {1, 1},
}

// Ldtk_FragmentMatrix: the 3x3 pattern of a fragment ("o": the main value,
// "x": the other value / not the main one, "-": anything).
Ldtk_FragmentMatrix :: proc(f: Ldtk_WallFragment, flipX := false, flipY := false) -> [3]string {
	m: [3]string
	switch f {
	case .Full: m = {"---", "-o-", "---"}
	case .Single: m = {"-x-", "xox", "-x-"}
	case .Cross: m = {"xox", "ooo", "xox"}
	case .Diagonal_NW_SE: m = {"oox", "ooo", "xoo"}
	case .Diagonal_SW_NE: m = {"xoo", "ooo", "oox"}
	case .TWall_N: m = {"xox", "ooo", "ooo"}
	case .TWall_S: m = Ldtk_FragmentMatrix(.TWall_N, false, true)
	case .TWall_W: m = {"xoo", "ooo", "xoo"}
	case .TWall_E: m = Ldtk_FragmentMatrix(.TWall_W, true, false)
	case .TCross_N: m = {"xox", "ooo", "-x-"}
	case .TCross_S: m = Ldtk_FragmentMatrix(.TCross_N, false, true)
	case .TCross_W: m = {"xo-", "oox", "xo-"}
	case .TCross_E: m = Ldtk_FragmentMatrix(.TCross_W, true, false)
	case .Vertical_N: m = {"-x-", "xox", "---"}
	case .Vertical_Mid: m = {"---", "xox", "---"}
	case .Vertical_S: m = Ldtk_FragmentMatrix(.Vertical_N, false, true)
	case .Horizontal_W: m = {"-x-", "xo-", "-x-"}
	case .Horizontal_Mid: m = {"-x-", "-o-", "-x-"}
	case .Horizontal_E: m = Ldtk_FragmentMatrix(.Horizontal_W, true, false)
	case .Turn_NW: m = {"-x-", "xoo", "-ox"}
	case .Turn_NE: m = Ldtk_FragmentMatrix(.Turn_NW, true, false)
	case .Turn_SE: m = Ldtk_FragmentMatrix(.Turn_NW, true, true)
	case .Turn_SW: m = Ldtk_FragmentMatrix(.Turn_NW, false, true)
	case .Wall_N: m = {"-x-", "-o-", "---"}
	case .Wall_S: m = Ldtk_FragmentMatrix(.Wall_N, false, true)
	case .Wall_W: m = {"---", "xo-", "---"}
	case .Wall_E: m = Ldtk_FragmentMatrix(.Wall_W, true, false)
	case .ExtCorner_NW: m = {"-x-", "xo-", "---"}
	case .ExtCorner_NE: m = Ldtk_FragmentMatrix(.ExtCorner_NW, true, false)
	case .ExtCorner_SE: m = Ldtk_FragmentMatrix(.ExtCorner_NW, true, true)
	case .ExtCorner_SW: m = Ldtk_FragmentMatrix(.ExtCorner_NW, false, true)
	case .InCorner_NW: m = {"xo-", "oo-", "---"}
	case .InCorner_NE: m = Ldtk_FragmentMatrix(.InCorner_NW, true, false)
	case .InCorner_SE: m = Ldtk_FragmentMatrix(.InCorner_NW, true, true)
	case .InCorner_SW: m = Ldtk_FragmentMatrix(.InCorner_NW, false, true)
	case .Corner_NW_to_N: m = {"-ox", "xoo", "-oo"}
	case .Corner_NE_to_N: m = Ldtk_FragmentMatrix(.Corner_NW_to_N, true, false)
	case .Corner_SE_to_S: m = Ldtk_FragmentMatrix(.Corner_NW_to_N, true, true)
	case .Corner_SW_to_S: m = Ldtk_FragmentMatrix(.Corner_NW_to_N, false, true)
	case .Corner_NW_to_W: m = {"-x-", "ooo", "xoo"}
	case .Corner_NE_to_E: m = Ldtk_FragmentMatrix(.Corner_NW_to_W, true, false)
	case .Corner_SE_to_E: m = Ldtk_FragmentMatrix(.Corner_NW_to_W, true, true)
	case .Corner_SW_to_W: m = Ldtk_FragmentMatrix(.Corner_NW_to_W, false, true)
	case .Corner_NW_to_NW: m = {"xox", "ooo", "xoo"}
	case .Corner_NE_to_NE: m = Ldtk_FragmentMatrix(.Corner_NW_to_NW, true, false)
	case .Corner_SW_to_SW: m = Ldtk_FragmentMatrix(.Corner_NW_to_NW, false, true)
	case .Corner_SE_to_SE: m = Ldtk_FragmentMatrix(.Corner_NW_to_NW, true, true)
	}
	if flipX {
		for &line in m {
			b := strings.builder_make(context.temp_allocator)
			#reverse for c in transmute([]u8)line do strings.write_byte(&b, c)
			line = strings.to_string(b)
		}
	}
	if flipY do m[0], m[2] = m[2], m[0]
	return m
}

// ldtk_fragment_flip: the fragment a flip turns f into (RulesWizard.flip).
@(private = "file")
ldtk_fragment_flip :: proc(f: Ldtk_WallFragment, fx, fy: bool) -> Ldtk_WallFragment {
	quad :: proc(f, nw, ne, se, sw: Ldtk_WallFragment, fx, fy: bool) -> Ldtk_WallFragment {
		// the four corners of one family
		order := [4]Ldtk_WallFragment{nw, ne, se, sw}
		pos := [4][2]bool{{false, false}, {true, false}, {true, true}, {false, true}} // (east, south)
		k := 0
		for x, i in order do if x == f do k = i
		p := pos[k]
		if fx do p.x = !p.x
		if fy do p.y = !p.y
		for q, i in pos do if q == p do return order[i]
		return f
	}
	#partial switch f {
	case .Full, .Single, .Cross, .Vertical_Mid, .Horizontal_Mid: return f
	case .Wall_N: return fy ? .Wall_S : f
	case .Wall_S: return fy ? .Wall_N : f
	case .Wall_E: return fx ? .Wall_W : f
	case .Wall_W: return fx ? .Wall_E : f
	case .Diagonal_NW_SE: return fx || fy ? .Diagonal_SW_NE : f
	case .Diagonal_SW_NE: return fx || fy ? .Diagonal_NW_SE : f
	case .TCross_N: return fy ? .TCross_S : f
	case .TCross_S: return fy ? .TCross_N : f
	case .TCross_W: return fx ? .TCross_E : f
	case .TCross_E: return fx ? .TCross_W : f
	case .TWall_N: return fy ? .TWall_S : f
	case .TWall_S: return fy ? .TWall_N : f
	case .TWall_W: return fx ? .TWall_E : f
	case .TWall_E: return fx ? .TWall_W : f
	case .Vertical_N: return fy ? .Vertical_S : f
	case .Vertical_S: return fy ? .Vertical_N : f
	case .Horizontal_W: return fx ? .Horizontal_E : f
	case .Horizontal_E: return fx ? .Horizontal_W : f
	case .ExtCorner_NW, .ExtCorner_NE, .ExtCorner_SE, .ExtCorner_SW: return quad(f, .ExtCorner_NW, .ExtCorner_NE, .ExtCorner_SE, .ExtCorner_SW, fx, fy)
	case .InCorner_NW, .InCorner_NE, .InCorner_SE, .InCorner_SW: return quad(f, .InCorner_NW, .InCorner_NE, .InCorner_SE, .InCorner_SW, fx, fy)
	case .Turn_NW, .Turn_NE, .Turn_SE, .Turn_SW: return quad(f, .Turn_NW, .Turn_NE, .Turn_SE, .Turn_SW, fx, fy)
	case .Corner_NW_to_NW, .Corner_NE_to_NE, .Corner_SE_to_SE, .Corner_SW_to_SW: return quad(f, .Corner_NW_to_NW, .Corner_NE_to_NE, .Corner_SE_to_SE, .Corner_SW_to_SW, fx, fy)
	case .Corner_NW_to_N, .Corner_NE_to_N, .Corner_SE_to_S, .Corner_SW_to_S: return quad(f, .Corner_NW_to_N, .Corner_NE_to_N, .Corner_SE_to_S, .Corner_SW_to_S, fx, fy)
	case .Corner_NW_to_W, .Corner_NE_to_E, .Corner_SE_to_E, .Corner_SW_to_W: return quad(f, .Corner_NW_to_W, .Corner_NE_to_E, .Corner_SE_to_E, .Corner_SW_to_W, fx, fy)
	}
	return f
}

Ldtk_WizardSetup :: struct {
	name:         string,
	mainValue:    int,
	otherValue:   int, // 0: "not the main value"
	breakOnMatch: bool,
	tiles:        [Ldtk_WallFragment][dynamic]i32, // each fragment's tiles (none: no rule)
}

Ldtk_WizardSetup_Destroy :: proc(s: ^Ldtk_WizardSetup) {
	for &t in s.tiles do delete(t)
	s^ = {}
}

// ldtk_sym_alt: getSymetricalAlternative - a mirrored fragment that has tiles.
@(private = "file")
ldtk_sym_alt :: proc(s: ^Ldtk_WizardSetup, f: Ldtk_WallFragment) -> (alt: Ldtk_WallFragment, fx, fy: bool, ok: bool) {
	if x := ldtk_fragment_flip(f, true, false); x != f && len(s.tiles[x]) > 0 do return x, true, false, true
	if x := ldtk_fragment_flip(f, false, true); x != f && len(s.tiles[x]) > 0 do return x, false, true, true
	if x := ldtk_fragment_flip(f, true, true); x != f && len(s.tiles[x]) > 0 do return x, true, true, true
	return f, false, false, false
}

// Ldtk_Doc_RulesWizardApply builds (or rebuilds: groupUid >= 0) an
// Assistant group from fragments; returns the group's uid.
Ldtk_Doc_RulesWizardApply :: proc(doc: ^Ldtk_Doc, layerUid: int, groupUid: int, s: ^Ldtk_WizardSetup) -> int {
	a := doc.allocator
	gid := groupUid
	g: ^LdtkJson
	if gid >= 0 do g, _, _ = Ldtk_Doc_FindRuleGroup(doc, gid)
	if g == nil {
		gid = Ldtk_Doc_AddRuleGroup(doc, layerUid, s.name)
		g, _, _ = Ldtk_Doc_FindRuleGroup(doc, gid)
	}
	LdtkJson_SetStr(g, "name", s.name, a)
	LdtkJson_SetBool(g, "usesWizard", true, a)
	rules := LdtkJson_New(.Array, a)
	LdtkJson_Set(g, "rules", rules, a)
	other := s.otherValue == 0 ? -s.mainValue : s.otherValue
	for f in Ldtk_WallFragment {
		if len(s.tiles[f]) == 0 do continue
		m := Ldtk_FragmentMatrix(f)
		Ldtk_Doc_AddRule(doc, layerUid, gid, 3, s.mainValue, int(s.tiles[f][0]))
		r := rules.items[len(rules.items) - 1]
		pat := LdtkJson_New(.Array, a)
		for cy in 0 ..< 3 do for cx in 0 ..< 3 {
			c := m[cy][cx]
			append(&pat.items, LdtkJson_NewInt(c == 'x' ? other : c == 'o' ? s.mainValue : 0, a))
		}
		LdtkJson_Set(r, "pattern", pat, a)
		rects := LdtkJson_New(.Array, a)
		for t in s.tiles[f] {
			one := LdtkJson_New(.Array, a)
			append(&one.items, LdtkJson_NewInt(int(t), a))
			append(&rects.items, one)
		}
		LdtkJson_Set(r, "tileRectsIds", rects, a)
		LdtkJson_SetInt(r, "outOfBoundsValue", s.mainValue, a)
		LdtkJson_SetBool(r, "breakOnMatch", s.breakOnMatch, a)
		// fragments without tiles whose mirror is this one: flip this rule
		for e in Ldtk_WallFragment {
			if len(s.tiles[e]) > 0 do continue
			alt, fx, fy, ok := ldtk_sym_alt(s, e)
			if !ok || alt != f do continue
			if fx do LdtkJson_SetBool(r, "flipX", true, a)
			if fy do LdtkJson_SetBool(r, "flipY", true, a)
		}
		ldtk_rule_trim(doc, r)
	}
	Ldtk_Doc_RulesChanged(doc, layerUid)
	return gid
}

// ldtk_rule_trim: AutoLayerRuleDef.trim / tidy (empty borders shrink the
// pattern; symmetric patterns don't flip).
@(private = "file")
ldtk_rule_trim :: proc(doc: ^Ldtk_Doc, r: ^LdtkJson) {
	a := doc.allocator
	size := LdtkJson_Int(r, "size", 3)
	pat := LdtkJson_Get(r, "pattern")
	at :: proc(p: ^LdtkJson, size, x, y: int) -> int {return int(p.items[x + y * size].num)}
	for size > 1 {
		empty := true
		for i in 0 ..< size {
			if at(pat, size, i, 0) != 0 || at(pat, size, i, size - 1) != 0 || at(pat, size, 0, i) != 0 || at(pat, size, size - 1, i) != 0 do empty = false
		}
		if !empty do break
		ns := size - 2
		np := LdtkJson_New(.Array, a)
		for y in 0 ..< ns do for x in 0 ..< ns do append(&np.items, pat.items[(x + 1) + (y + 1) * size])
		pat = np
		size = ns
	}
	LdtkJson_Set(r, "pattern", pat, a)
	LdtkJson_SetInt(r, "size", size, a)
	sym :: proc(p: ^LdtkJson, size: int, xAxis: bool) -> bool {
		for i in 0 ..< size / 2 do for j in 0 ..< size {
			va := xAxis ? at(p, size, i, j) : at(p, size, j, i)
			vb := xAxis ? at(p, size, size - 1 - i, j) : at(p, size, j, size - 1 - i)
			if va != vb do return false
		}
		return true
	}
	if LdtkJson_Bool(r, "flipX") && sym(pat, size, true) do LdtkJson_SetBool(r, "flipX", false, a)
	if LdtkJson_Bool(r, "flipY") && sym(pat, size, false) do LdtkJson_SetBool(r, "flipY", false, a)
}

// Ldtk_Doc_RulesWizardImport reads an Assistant group back into fragments
// (RulesWizard.importRuleGroup); ok = false when it doesn't look like one.
Ldtk_Doc_RulesWizardImport :: proc(doc: ^Ldtk_Doc, groupUid: int, s: ^Ldtk_WizardSetup) -> bool {
	g, _, _ := Ldtk_Doc_FindRuleGroup(doc, groupUid)
	if g == nil do return false
	rules := LdtkJson_Arr(g, "rules")
	pat_at :: proc(r: ^LdtkJson, x, y: int) -> int {
		size := LdtkJson_Int(r, "size", 3)
		p := LdtkJson_Arr(r, "pattern")
		i := x + y * size
		return i < len(p) ? int(p[i].num) : 0
	}
	// main: the first positive centre; other: another value used
	for r in rules {
		c := LdtkJson_Int(r, "size", 3) / 2
		if v := pat_at(r, c, c); v > 0 {
			s.mainValue = abs(v)
			break
		}
	}
	if s.mainValue == 0 do return false
	outer: for r in rules {
		size := LdtkJson_Int(r, "size", 3)
		for y in 0 ..< size do for x in 0 ..< size {
			v := abs(pat_at(r, x, y))
			if v != 0 && v != s.mainValue && v < LDTK_AUTO_LAYER_ANYTHING {
				s.otherValue = v
				break outer
			}
		}
	}
	s.name = LdtkJson_Str(g, "name")
	other := s.otherValue == 0 ? -s.mainValue : s.otherValue
	for r, i in rules {
		if i == 0 do s.breakOnMatch = LdtkJson_Bool(r, "breakOnMatch")
		size := LdtkJson_Int(r, "size", 3)
		if size > 3 do continue
		for f in Ldtk_WallFragment {
			m := Ldtk_FragmentMatrix(f)
			mv :: proc(m: [3]string, idx: int, main, other: int) -> int {
				c := m[idx / 3][idx % 3]
				return c == 'x' ? other : c == 'o' ? main : 0
			}
			match := true
			if size == 1 {
				for idx in 0 ..< 9 {
					want := mv(m, idx, s.mainValue, other)
					if idx != 4 && want != 0 do match = false
					if idx == 4 && want != pat_at(r, 0, 0) do match = false
				}
			} else {
				for y in 0 ..< 3 do for x in 0 ..< 3 do if mv(m, x + y * 3, s.mainValue, other) != pat_at(r, x, y) do match = false
			}
			if !match do continue
			rects := LdtkJson_Arr(r, "tileRectsIds")
			clear(&s.tiles[f])
			for rect in rects do if len(rect.items) > 0 do append(&s.tiles[f], i32(rect.items[0].num))
			break
		}
	}
	return true
}

// ----------------------------------------------------------------------------
// Preview
// ----------------------------------------------------------------------------

// Ldtk_Doc_RuleMatchCells: the cells of a level where a rule matches (its
// pattern, modulo and chance - not break on match), for the rule preview.
Ldtk_Doc_RuleMatchCells :: proc(doc: ^Ldtk_Doc, li: int, ruleUid: int, allocator := context.temp_allocator) -> [][2]int {
	out := make([dynamic][2]int, allocator)
	_, _, layerUid := Ldtk_Doc_FindRule(doc, ruleUid)
	if layerUid < 0 do return out[:]
	lv := &doc.levels[li]
	ly := Ldtk_Doc_LevelLayer(doc, lv, layerUid)
	if ly == nil do return out[:]
	ldtk_rule_cells(doc, lv, ly, ruleUid, &out)
	return out[:]
}
