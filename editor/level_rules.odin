package editor

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Level editor: the Rules tab (LDtk's EditAllAutoLayerRules, RuleEditor,
// RulesWizard, RuleGroupRemap)
//
//   layers with rules | groups and their rules | the selected rule
//
// Groups: on / off, collapse, rename, duplicate (and remap values / tiles),
// colour, icon, optional, biome, out-of-bounds for all rules, the Rules
// Assistant, reorder, copy / paste, delete. Rules: pattern (any size up to
// 9), tiles (individual / stamps, pivot), out-of-bounds value, chance,
// opacity, flips, break on match, modulo / offset / checker, Perlin noise,
// tile offsets and random offsets, on / off; duplicate, copy / paste,
// insert, reorder, preview the cells it matches.
// ============================================================================

@(private = "file")
lr: struct {
	layerUid:   int,
	ruleUid:    int,
	groupUid:   int,
	collapsed:  map[int]bool,
	clipRule:   string,
	clipGroup:  string,
	patValue:   int,  // the value the pattern editor paints (0: any value)
	renameGroup: int,
	renameReq:  bool,
	renameBuf:  [128]u8,
	// the Rules Assistant window
	wizOpen:    bool,
	wizGroup:   int, // -1: a new group
	wizLayer:   int,
	wizFrag:    e.Ldtk_WallFragment,
	wiz:        e.Ldtk_WizardSetup,
	wizName:    [128]u8,
	// duplicate & remap
	remapReq:   bool,
	remapGroup: int,
	remapFrom:  [dynamic]i32,
	remapTo:    [dynamic]i32,
	remapOff:   [2]i32,
	remapName:  [128]u8,
}

LevelRules_SelectLayer :: proc(uid: int) {lr.layerUid = uid}

// LevelRules_Preview: the rule whose matching cells the canvas shows (0: none).
levelRulePreview: int

LevelRules_Shutdown :: proc() {
	delete(lr.collapsed)
	delete(lr.clipRule)
	delete(lr.clipGroup)
	delete(lr.remapFrom)
	delete(lr.remapTo)
	e.Ldtk_WizardSetup_Destroy(&lr.wiz)
	lr = {}
}

@(private = "file")
cp :: proc(label: string) {e.Ldtk_Doc_Checkpoint(GlobalLevel.doc, -1, label)}

@(private = "file")
src_def :: proc(doc: ^e.Ldtk_Doc, d: ^e.Ldtk_DocLayerDef) -> ^e.Ldtk_DocLayerDef {
	if d.type == .IntGrid do return d
	si := e.Ldtk_Doc_LayerDefIndex(doc, d.autoSourceUid)
	return si >= 0 ? &doc.layerDefs[si] : nil
}

LevelRules_Page :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	if e.Ldtk_Doc_LayerDefIndex(doc, lr.layerUid) < 0 {
		if _, d := level_active_layer(); d != nil && (d.type == .IntGrid || d.type == .AutoLayer) do lr.layerUid = d.uid
	}
	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##rules_layers", {170, avail.y}, {.Borders}, {}) {
		UI_DimText("Layers with rules")
		level_tip("IntGrid layers with a tileset and Auto layers", "tab.rules")
		for &d in doc.layerDefs {
			if d.type != .IntGrid && d.type != .AutoLayer do continue
			n := 0
			for g in d.groups do n += len(g.rules)
			if imgui.Selectable(fmt.ctprintf("%s  %s (%d)##rl%d", LAYER_TYPE_ICON[d.type], d.identifier, n, d.uid), lr.layerUid == d.uid, {}, {0, 22}) do lr.layerUid = d.uid
			Drive_Item(fmt.tprintf("defs.rules.layer:%s", d.identifier))
			level_tip(fmt.tprintf("%s: %d rules", d.identifier, n), "tab.rules")
		}
	}
	imgui.EndChild()
	di := e.Ldtk_Doc_LayerDefIndex(doc, lr.layerUid)
	imgui.SameLine(0, 8)
	if di < 0 {
		UI_DimText("Pick an IntGrid layer (with a tileset) or an Auto layer.")
		rules_windows(state)
		return
	}
	layerUid := lr.layerUid
	d := &doc.layerDefs[di]
	if d.tilesetUid < 0 || src_def(doc, d) == nil {
		imgui.BeginGroup()
		UI_DimText(d.tilesetUid < 0 ? "This layer needs a tileset: rules place its tiles (Layers tab)." : "This Auto layer needs the IntGrid layer its rules read (Layers tab).")
		if UI_Button("Layer settings", "defs.rules.layersettings") {
			LevelDefs_SelectLayer(layerUid)
			LevelEditor_ShowTab(.Layers)
		}
		imgui.EndGroup()
		rules_windows(state)
		return
	}
	w := imgui.GetContentRegionAvail().x
	listW := clamp(w * 0.45, 260, 460)
	if imgui.BeginChild("##rules_groups", {listW, avail.y}, {.Borders}, {}) do groups_list(state, layerUid)
	imgui.EndChild()
	imgui.SameLine(0, 8)
	if imgui.BeginChild("##rule_editor", {0, avail.y}, {}, {}) {
		r, _, rl_ := e.Ldtk_Doc_FindRule(doc, lr.ruleUid)
		if r != nil && rl_ == layerUid do rule_editor(state, layerUid, r)
		else do UI_DimText("Pick a rule to edit it.")
	}
	imgui.EndChild()
	rules_windows(state)
}

// rules_windows: the Assistant window and the dialogs.
@(private = "file")
rules_windows :: proc(state: ^EditorState) {
	wizard_window(state)
	remap_popup(state)
	rename_popup(state)
}

// ----------------------------------------------------------------------------
// Groups and rules list
// ----------------------------------------------------------------------------

@(private = "file")
groups_list :: proc(state: ^EditorState, layerUid: int) {
	L := &GlobalLevel
	doc := L.doc
	d := &doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(doc, layerUid)]
	ts := e.Ldtk_Doc_Tileset(doc, d.tilesetUid)
	sd := src_def(doc, d)
	// add buttons
	if UI_Button(fmt.tprintf("%s  Assistant", ICON_FA_WAND_MAGIC_SPARKLES), "defs.rules.wizard") do wizard_open(layerUid, -1)
	level_tip("The Rules Assistant: pick the tiles for walls, corners and turns - it writes the rules (recommended)", "rules.wizard")
	imgui.SameLine()
	if UI_Button(fmt.tprintf("%s  Empty group", ICON_FA_PLUS), "defs.group.add") {
		cp("Add Rule Group")
		lr.groupUid = e.Ldtk_Doc_AddRuleGroup(doc, layerUid, fmt.tprintf("Group %d", len(d.groups) + 1))
	}
	level_tip("A group to fill with your own rules", "tab.rules")
	imgui.SameLine()
	if UI_Button(fmt.tprintf("%s  3x3", ICON_FA_TABLE), "defs.terrain") {
		if len(L.tileSel) == 9 && L.tileSelW == 3 {
			v := L.intValue
			if e.Ldtk_Doc_IntValue(sd, v) == nil do v = len(sd.values) > 0 ? sd.values[0].value : 1
			block: [9]int
			for t, i in L.tileSel do block[i] = int(t)
			cp("Terrain Rules")
			e.Ldtk_Doc_AddTerrainRules(doc, layerUid, v, block)
			return
		} else do Editor_Log(state, .Info, "Pick a 3x3 block of tiles (corners, edges, centre) in the Layers panel's tileset first")
	}
	level_tip("Terrain from the picked 3x3 tiles: corners, edges and centre over the picked value", "rules.terrain")
	if lr.clipGroup != "" {
		imgui.SameLine()
		if UI_IconButton(ICON_FA_PASTE, "defs.group.paste", "", false, 26) {
			cp("Paste Rule Group")
			lr.groupUid = e.Ldtk_Doc_PasteRuleGroup(doc, layerUid, lr.clipGroup)
			return
		}
		level_tip("Paste the copied group", "tab.rules")
	}
	imgui.Separator()
	for gi in 0 ..< len(d.groups) {
		g := &doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(doc, layerUid)].groups[gi]
		guid := g.uid
		imgui.PushIDInt(i32(guid))
		// header
		collapsed := lr.collapsed[guid]
		if UI_IconButton(collapsed ? ICON_FA_ARROW_DOWN : ICON_FA_ARROW_UP, fmt.tprintf("defs.group.fold:%s", g.name), "", false, 20) {
			if lr.collapsed == nil do lr.collapsed = make(map[int]bool)
			lr.collapsed[guid] = !collapsed
		}
		level_tip(collapsed ? "Show its rules" : "Fold its rules", "tab.rules")
		imgui.SameLine(0, 2)
		active := g.active
		if imgui.Checkbox("##gactive", &active) {
			cp("Rule Group")
			e.LdtkJson_SetBool(g.obj, "active", active, doc.allocator)
			e.Ldtk_Doc_RulesChanged(doc, layerUid)
			imgui.PopID()
			return
		}
		level_tip("The group on / off", "tab.rules")
		imgui.SameLine(0, 4)
		if hex := e.LdtkJson_Str(g.obj, "color"); hex != "" {
			c := e.Ldtk_ParseHexColor(hex)
			p := imgui.GetCursorScreenPos()
			imgui.DrawList_AddRectFilled(imgui.GetWindowDrawList(), {p.x, p.y + 5}, {p.x + 8, p.y + 17}, col_u32({f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, 1}), 2, {})
			imgui.Dummy({10, 20})
			imgui.SameLine(0, 2)
		}
		badges := ""
		if g.isOptional do badges = fmt.tprintf("%s [optional]", badges)
		if e.LdtkJson_Bool(g.obj, "usesWizard") do badges = fmt.tprintf("%s [assistant]", badges)
		if len(g.biomeValues) > 0 do badges = fmt.tprintf("%s [biome]", badges)
		imgui.PushFont(GlobalFonts.semibold)
		if imgui.Selectable(fmt.ctprintf("%s (%d)%s##gsel", g.name, len(g.rules), badges), lr.groupUid == guid, {.AllowDoubleClick}, {0, 20}) {
			lr.groupUid = guid
			if imgui.IsMouseDoubleClicked(.Left) && e.LdtkJson_Bool(g.obj, "usesWizard") do wizard_open(layerUid, guid)
		}
		imgui.PopFont()
		Drive_Item(fmt.tprintf("defs.group:%s", g.name))
		level_tip(fmt.tprintf("%s: %d rules%s. Right-click for more.", g.name, len(g.rules), e.LdtkJson_Bool(g.obj, "usesWizard") ? " (double-click: the Assistant)" : ""), "tab.rules")
		if group_menu(state, layerUid, guid) {
			imgui.PopID()
			return
		}
		if !collapsed {
			g = &doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(doc, layerUid)].groups[gi]
			for ri in 0 ..< len(g.rules) {
				r := &g.rules[ri]
				imgui.PushIDInt(i32(r.uid))
				if rule_row(state, layerUid, sd, ts, r, ri, g.name) {
					imgui.PopID()
					imgui.PopID()
					return
				}
				imgui.PopID()
			}
			if !e.LdtkJson_Bool(g.obj, "usesWizard") {
				imgui.Indent(24)
				if UI_Button(fmt.tprintf("%s  Rule", ICON_FA_PLUS), fmt.tprintf("defs.rule.add:%s", g.name)) {
					cp("Add Rule")
					v := len(sd.values) > 0 ? sd.values[0].value : 1
					tile := len(L.tileSel) > 0 ? int(L.tileSel[0]) : 0
					lr.ruleUid = e.Ldtk_Doc_AddRule(doc, layerUid, guid, 3, v, tile)
					imgui.Unindent(24)
					imgui.PopID()
					return
				}
				level_tip("A new rule at the end of the group (the picked tile, the picked value at the centre)", "tab.rules")
				imgui.Unindent(24)
			}
		}
		imgui.PopID()
		imgui.Separator()
	}
}

// mini_pattern draws a rule's pattern small.
mini_pattern :: proc(dl: ^imgui.DrawList, p: [2]f32, cell: f32, size: int, pattern: []i32, sd: ^e.Ldtk_DocLayerDef) {
	for cy in 0 ..< size {
		for cx in 0 ..< size {
			v := int(pattern[cx + cy * size])
			mn := [2]f32{p.x + f32(cx) * cell, p.y + f32(cy) * cell}
			mx := mn + {cell - 1, cell - 1}
			fill := imgui.Vec4{0.15, 0.16, 0.19, 1}
			if v == e.LDTK_AUTO_LAYER_ANYTHING do fill = {0.8, 0.8, 0.8, 1}
			else if v == -e.LDTK_AUTO_LAYER_ANYTHING do fill = {0.05, 0.05, 0.05, 1}
			else if v != 0 {
				iv := e.Ldtk_Doc_IntValue(sd, abs(v))
				c := iv != nil ? iv.color : rl.MAGENTA
				fill = {f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, 1}
			}
			imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32(fill), 0, {})
			if v < 0 && v != -e.LDTK_AUTO_LAYER_ANYTHING do imgui.DrawList_AddLine(dl, mn, mx, col_u32(UI_DANGER), 1.5)
		}
	}
}

// rule_row: one rule in the list (true: the rules changed - stop drawing).
@(private = "file")
rule_row :: proc(state: ^EditorState, layerUid: int, sd: ^e.Ldtk_DocLayerDef, ts: ^e.Ldtk_DocTileset, r: ^e.Ldtk_DocRule, index: int, groupName: string) -> bool {
	L := &GlobalLevel
	doc := L.doc
	dl := imgui.GetWindowDrawList()
	rowH: f32 = 30
	p := imgui.GetCursorScreenPos()
	if imgui.Selectable(fmt.ctprintf("##rule%d", r.uid), lr.ruleUid == r.uid, {.AllowOverlap}, {0, rowH}) do lr.ruleUid = r.uid
	Drive_Item(fmt.tprintf("defs.rule:%s:%d", groupName, index))
	tipText := fmt.tprintf("Rule %d: %dx%d, %d tile(s), %.0f%% chance%s%s%s. Click to edit; right-click for more.", index + 1, r.size, r.size, len(r.tileRects), r.chance * 100, r.breakOnMatch ? ", break on match" : "", r.flipX || r.flipY ? ", flips" : "", r.active ? "" : " (off)")
	level_tip(tipText, "tab.rules")
	menu := rule_menu(state, layerUid, r.uid)
	// contents
	x := p.x + 20
	cell := max(min(f32(24) / f32(r.size), 8), 3)
	mini_pattern(dl, {x, p.y + 3}, cell, r.size, r.pattern, sd)
	x += cell * f32(r.size) + 8
	if ts != nil {
		if ptr := level_texture_ptr(ts.uid); ptr != nil {
			for rect, i in r.tileRects {
				if i >= 4 || len(rect) == 0 do break
				src := e.Ldtk_Doc_TileSrc(ts, int(rect[0]))
				tw, th := f32(ptr.width), f32(ptr.height)
				imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)ptr, {x, p.y + 3}, {x + 24, p.y + 27}, {f32(src.x) / tw, f32(src.y) / th}, {f32(int(src.x) + ts.gridSize) / tw, f32(int(src.y) + ts.gridSize) / th})
				x += 26
			}
		}
	}
	flags := strings.builder_make(context.temp_allocator)
	if r.chance < 1 do fmt.sbprintf(&flags, "%.0f%% ", r.chance * 100)
	if r.flipX do strings.write_string(&flags, "X ")
	if r.flipY do strings.write_string(&flags, "Y ")
	if r.breakOnMatch do strings.write_string(&flags, "brk ")
	if r.perlin do strings.write_string(&flags, "perlin ")
	if r.xModulo > 1 || r.yModulo > 1 do fmt.sbprintf(&flags, "mod%dx%d ", r.xModulo, r.yModulo)
	if !r.active do strings.write_string(&flags, "(off)")
	imgui.DrawList_AddText(dl, {x + 4, p.y + 8}, col_u32(r.active ? UI_TEXT_DIM : UI_TEXT_FAINT), fmt.ctprintf("%s", strings.to_string(flags)))
	if levelRulePreview == r.uid do imgui.DrawList_AddText(dl, {p.x + 4, p.y + 8}, col_u32(UI_SUCCESS), fmt.ctprintf("%s", ICON_FA_EYE))
	return menu
}

// rule_menu: a rule's right-click menu (true: the rules changed).
@(private = "file")
rule_menu :: proc(state: ^EditorState, layerUid: int, ruleUid: int) -> bool {
	L := &GlobalLevel
	doc := L.doc
	if !imgui.BeginPopupContextItem("##rulectx") do return false
	defer imgui.EndPopup()
	r, g, _ := e.Ldtk_Doc_FindRule(doc, ruleUid)
	if r == nil do return false
	guid := e.LdtkJson_Int(g, "uid")
	idx := 0
	for x, i in e.LdtkJson_Arr(g, "rules") do if x == r do idx = i
	if ctx_item(ICON_FA_PEN_TO_SQUARE, "Edit", "Show it in the rule editor") do lr.ruleUid = ruleUid
	if ctx_item(ICON_FA_EYE, levelRulePreview == ruleUid ? "Hide matching cells" : "Show matching cells", "Highlight in the canvas where it matches (this level)") {
		levelRulePreview = levelRulePreview == ruleUid ? 0 : ruleUid
	}
	active := e.LdtkJson_Bool(r, "active", true)
	if ctx_item(active ? ICON_FA_EYE_SLASH : ICON_FA_EYE, active ? "Disable" : "Enable", "Turn the rule off / on") {
		cp("Rule On / Off")
		e.LdtkJson_SetBool(r, "active", !active, doc.allocator)
		e.Ldtk_Doc_RulesChanged(doc, layerUid)
		return true
	}
	imgui.Separator()
	if ctx_item(ICON_FA_CLONE, "Duplicate", "A copy right after it") {
		cp("Duplicate Rule")
		lr.ruleUid = e.Ldtk_Doc_DuplicateRule(doc, ruleUid)
		return true
	}
	if ctx_item(ICON_FA_COPY, "Copy", "Copy the rule") {
		delete(lr.clipRule)
		lr.clipRule = e.Ldtk_Doc_RuleText(doc, ruleUid)
	}
	if ctx_item(ICON_FA_PASTE, "Paste after", "Paste the copied rule after this one", lr.clipRule != "") {
		cp("Paste Rule")
		lr.ruleUid = e.Ldtk_Doc_PasteRule(doc, guid, lr.clipRule, ruleUid)
		return true
	}
	if ctx_item(ICON_FA_PLUS, "Insert before", "A new rule above this one") {
		cp("Insert Rule")
		lr.ruleUid = e.Ldtk_Doc_InsertRule(doc, guid, idx)
		return true
	}
	if ctx_item(ICON_FA_PLUS, "Insert after", "A new rule below this one") {
		cp("Insert Rule")
		lr.ruleUid = e.Ldtk_Doc_InsertRule(doc, guid, idx + 1)
		return true
	}
	if ctx_item(ICON_FA_ARROW_UP, "Move up", "Earlier (rules run top to bottom); from the top it goes to the group above") {
		cp("Move Rule")
		e.Ldtk_Doc_MoveRule(doc, ruleUid, -1)
		return true
	}
	if ctx_item(ICON_FA_ARROW_DOWN, "Move down", "Later; from the bottom it goes to the group below") {
		cp("Move Rule")
		e.Ldtk_Doc_MoveRule(doc, ruleUid, 1)
		return true
	}
	imgui.Separator()
	if ctx_item(ICON_FA_TRASH, "Delete", "Delete the rule") {
		cp("Delete Rule")
		e.Ldtk_Doc_RemoveRule(doc, ruleUid)
		if levelRulePreview == ruleUid do levelRulePreview = 0
		return true
	}
	imgui.Separator()
	if ctx_item(ICON_FA_CIRCLE_QUESTION, "Help", "Rules in the reference") do LevelRef_Open("tab.rules")
	return false
}

// group_menu: a group's right-click menu (true: the groups changed).
@(private = "file")
group_menu :: proc(state: ^EditorState, layerUid: int, guid: int) -> bool {
	L := &GlobalLevel
	doc := L.doc
	a := doc.allocator
	if !imgui.BeginPopupContextItem("##grpctx") do return false
	defer imgui.EndPopup()
	g, _, _ := e.Ldtk_Doc_FindRuleGroup(doc, guid)
	if g == nil do return false
	d := &doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(doc, layerUid)]
	if ctx_item(ICON_FA_PEN_TO_SQUARE, "Rename...", "Change its name") {
		lr.renameGroup = guid
		lr.renameReq = true
		lr.renameBuf = {}
		copy(lr.renameBuf[:127], e.LdtkJson_Str(g, "name"))
	}
	if e.LdtkJson_Bool(g, "usesWizard") {
		if ctx_item(ICON_FA_WAND_MAGIC_SPARKLES, "Edit with the Assistant", "Change its tiles in the Rules Assistant") do wizard_open(layerUid, guid)
		if ctx_item(ICON_FA_SLIDERS, "Advanced mode", "Edit its rules by hand (the Assistant can't edit it afterwards)") {
			cp("Advanced Mode")
			e.LdtkJson_SetBool(g, "usesWizard", false, a)
			e.Ldtk_Doc_Touch(doc)
		}
	}
	if ctx_item(ICON_FA_CLONE, "Duplicate and remap...", "A copy with other IntGrid values and / or tiles shifted in the tileset") {
		remap_open(guid)
	}
	if ctx_item(ICON_FA_COPY, "Copy", "Copy the group") {
		delete(lr.clipGroup)
		lr.clipGroup = e.Ldtk_Doc_RuleGroupText(doc, guid)
	}
	imgui.Separator()
	opt := e.LdtkJson_Bool(g, "isOptional")
	if ctx_item(ICON_FA_LAYER_GROUP, opt ? "Make global" : "Make optional", opt ? "Apply it in every level (forgets the per-level on / off states)" : "Off by default, enabled per level (Layers panel check box)") {
		cp("Optional Group")
		e.Ldtk_Doc_SetRuleGroupOptional(doc, guid, !opt)
		return true
	}
	if imgui.BeginMenu(fmt.ctprintf("%s  Colour", ICON_FA_CIRCLE)) {
		for hex in ([]string{"#E53B44", "#FB922B", "#FFE762", "#63C64D", "#2CE8F4", "#0484D1", "#B55088", "#FFFFFF"}) {
			c := e.Ldtk_ParseHexColor(hex)
			imgui.PushStyleColorImVec4(.Text, {f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, 1})
			if imgui.MenuItem(fmt.ctprintf("%s  %s", ICON_FA_CIRCLE, hex)) {
				cp("Group Colour")
				e.Ldtk_Doc_SetRuleGroupColor(doc, guid, hex)
			}
			imgui.PopStyleColor()
		}
		if imgui.MenuItem("None") {
			cp("Group Colour")
			e.Ldtk_Doc_SetRuleGroupColor(doc, guid, "")
		}
		imgui.EndMenu()
	}
	Drive_Item("ctx:Colour")
	if ctx_item(ICON_FA_IMAGE, "Icon from picked tile", "The picked tile becomes the group's icon (in LDtk's lists)") {
		if ts, rect, ok := picked_tile_rect(); ok {
			cp("Group Icon")
			e.Ldtk_Doc_SetRuleGroupIcon(doc, guid, ts, rect)
		}
	}
	if !e.LdtkJson_IsNull(g, "icon") && ctx_item(ICON_FA_ERASER, "Remove icon", "No icon") {
		cp("Group Icon")
		e.Ldtk_Doc_SetRuleGroupIcon(doc, guid, -1, {})
	}
	// biome: enum values a level's biome field must have
	if imgui.BeginMenu(fmt.ctprintf("%s  Biome", ICON_FA_GLOBE)) {
		bf := e.Ldtk_Doc_FieldDef(doc, d.biomeFieldUid)
		en := bf != nil ? e.Ldtk_Doc_EnumDef(doc, e.Ldtk_FieldEnumUid(bf)) : nil
		if en == nil {
			UI_DimText("Pick the layer's biome field first (Layers tab)")
		} else {
			cur := make([dynamic]string, context.temp_allocator)
			for v in e.LdtkJson_Arr(g, "requiredBiomeValues") do append(&cur, v.text)
			mode := e.LdtkJson_Int(g, "biomeRequirementMode")
			for v in e.LdtkJson_Arr(en, "values") {
				id := e.LdtkJson_Str(v, "id")
				on := false
				for c in cur do if c == id do on = true
				if imgui.MenuItem(fmt.ctprintf("%s", id), nil, on) {
					next := make([dynamic]string, context.temp_allocator)
					for c in cur do if c != id do append(&next, c)
					if !on do append(&next, id)
					cp("Group Biome")
					e.Ldtk_Doc_SetRuleGroupBiome(doc, guid, next[:], mode)
				}
			}
			imgui.Separator()
			if imgui.MenuItem("Any of them (OR)", nil, mode == 0) {
				cp("Group Biome")
				e.Ldtk_Doc_SetRuleGroupBiome(doc, guid, cur[:], 0)
			}
			if imgui.MenuItem("All of them (AND)", nil, mode == 1) {
				cp("Group Biome")
				e.Ldtk_Doc_SetRuleGroupBiome(doc, guid, cur[:], 1)
			}
		}
		imgui.EndMenu()
	}
	Drive_Item("ctx:Biome")
	if imgui.BeginMenu(fmt.ctprintf("%s  Out of bounds for all rules", ICON_FA_EXPAND)) {
		if imgui.MenuItem("No value (cells outside don't match)") {
			cp("Out of Bounds")
			e.Ldtk_Doc_SetRuleGroupOutOfBounds(doc, guid, -1)
		}
		if imgui.MenuItem("Empty") {
			cp("Out of Bounds")
			e.Ldtk_Doc_SetRuleGroupOutOfBounds(doc, guid, 0)
		}
		if sd := src_def(doc, d); sd != nil {
			for v in sd.values {
				if imgui.MenuItem(fmt.ctprintf("%d  %s", v.value, v.identifier)) {
					cp("Out of Bounds")
					e.Ldtk_Doc_SetRuleGroupOutOfBounds(doc, guid, v.value)
				}
			}
		}
		imgui.EndMenu()
	}
	imgui.Separator()
	if ctx_item(ICON_FA_ARROW_UP, "Move up", "Earlier (groups run top to bottom)") {
		cp("Move Group")
		e.Ldtk_Doc_MoveRuleGroup(doc, guid, -1)
		return true
	}
	if ctx_item(ICON_FA_ARROW_DOWN, "Move down", "Later") {
		cp("Move Group")
		e.Ldtk_Doc_MoveRuleGroup(doc, guid, 1)
		return true
	}
	if ctx_item(ICON_FA_TRASH, "Delete", "Delete the group and its rules") {
		cp("Delete Group")
		e.Ldtk_Doc_RemoveRuleGroup(doc, guid)
		return true
	}
	imgui.Separator()
	if ctx_item(ICON_FA_CIRCLE_QUESTION, "Help", "Rule groups in the reference") do LevelRef_Open("tab.rules")
	return false
}

// ----------------------------------------------------------------------------
// The rule editor
// ----------------------------------------------------------------------------

@(private = "file")
rule_editor :: proc(state: ^EditorState, layerUid: int, robj: ^e.LdtkJson) {
	L := &GlobalLevel
	doc := L.doc
	a := doc.allocator
	ruleUid := e.LdtkJson_Int(robj, "uid")
	d := &doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(doc, layerUid)]
	sd := src_def(doc, d)
	ts := e.Ldtk_Doc_Tileset(doc, d.tilesetUid)
	var_rule: ^e.Ldtk_DocRule
	for &g in d.groups do for &x in g.rules do if x.uid == ruleUid do var_rule = &x
	if var_rule == nil do return
	r := var_rule
	changed := false
	set_int :: proc(obj: ^e.LdtkJson, key: string, v: int) {e.LdtkJson_SetInt(obj, key, v, GlobalLevel.doc.allocator)}
	UI_PanelTitle(ICON_FA_WAND_MAGIC_SPARKLES, "Rule", fmt.tprintf("%dx%d", r.size, r.size))
	UI_HeaderButtons(2)
	if UI_HeaderButton(levelRulePreview == ruleUid ? ICON_FA_EYE_SLASH : ICON_FA_EYE, "defs.rule.preview", "", levelRulePreview == ruleUid) do levelRulePreview = levelRulePreview == ruleUid ? 0 : ruleUid
	level_tip("Show the cells it matches in the canvas (this level)", "tab.rules")
	if UI_HeaderButton(ICON_FA_CIRCLE_QUESTION, "defs.rule.help", "") do LevelRef_Open("tab.rules")
	level_tip("Rules in the reference", "tab.rules")
	// value palette for the pattern
	UI_DimText("Paint the pattern with:")
	level_tip("Left click: require it; right click: forbid it; middle click: clear", "tab.rules")
	if lr.patValue != 0 && e.Ldtk_Doc_IntValue(sd, lr.patValue) == nil do lr.patValue = len(sd.values) > 0 ? sd.values[0].value : 0
	for v in sd.values {
		imgui.SameLine()
		c := v.color
		imgui.PushStyleColorImVec4(.Button, {f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, lr.patValue == v.value ? 1 : 0.45})
		if imgui.Button(fmt.ctprintf("%d##pv%d", v.value, v.value), {24, 22}) do lr.patValue = v.value
		imgui.PopStyleColor()
		Drive_Item(fmt.tprintf("defs.rule.value:%d", v.value))
		level_tip(fmt.tprintf("Value %d (%s)", v.value, v.identifier), "tab.rules")
	}
	imgui.SameLine()
	if UI_IconButton("*", "defs.rule.value:any", "", lr.patValue == 0, 24) do lr.patValue = 0
	level_tip("Any value (left) / no value (right)", "tab.rules")
	// pattern grid
	cell: f32 = max(min(28, 220 / f32(r.size)), 10)
	start := imgui.GetCursorScreenPos()
	dl := imgui.GetWindowDrawList()
	imgui.InvisibleButton("##pattern", {f32(r.size) * cell, f32(r.size) * cell}, {.MouseButtonLeft, .MouseButtonRight, .MouseButtonMiddle})
	Drive_ItemRect("defs.rule.pattern", start, start + 1, true)
	level_tip("The pattern: cells around the centre (yellow). Left: require, right: forbid, middle: clear.", "tab.rules")
	mini_pattern(dl, start, cell, r.size, r.pattern, sd)
	cc := r.size / 2
	imgui.DrawList_AddRect(dl, {start.x + f32(cc) * cell, start.y + f32(cc) * cell}, {start.x + f32(cc + 1) * cell - 1, start.y + f32(cc + 1) * cell - 1}, col_u32(UI_WARNING), 0, {}, 2)
	if imgui.IsItemHovered() {
		m := imgui.GetIO().MousePos
		cx, cy := int((m.x - start.x) / cell), int((m.y - start.y) / cell)
		if cx >= 0 && cy >= 0 && cx < r.size && cy < r.size {
			nv, set := 0, false
			val := lr.patValue == 0 ? e.LDTK_AUTO_LAYER_ANYTHING : lr.patValue
			switch {
			case imgui.IsMouseClicked(.Left): nv, set = val, true
			case imgui.IsMouseClicked(.Right): nv, set = -val, true
			case imgui.IsMouseClicked(.Middle): nv, set = 0, true
			}
			if set {
				cp("Rule Pattern")
				e.Ldtk_Doc_SetRuleCell(doc, ruleUid, cx, cy, nv)
				return
			}
		}
	}
	imgui.SameLine()
	imgui.BeginGroup()
	imgui.SetNextItemWidth(90)
	sz := i32(r.size)
	if imgui.InputInt("##rsize", &sz, 2, 2) {
		ns := clamp(int(sz) | 1, 1, e.LDTK_MAX_AUTO_PATTERN_SIZE)
		if ns != r.size {
			cp("Rule Size")
			resize_pattern(robj, r, ns)
			e.Ldtk_Doc_RulesChanged(doc, layerUid)
			imgui.EndGroup()
			return
		}
	}
	Drive_Item("defs.rule.size")
	level_tip("Pattern size (odd, up to 9)", "tab.rules")
	if UI_Button("Clear", "defs.rule.clear") {
		cp("Rule Pattern")
		for y in 0 ..< r.size do for x in 0 ..< r.size do e.Ldtk_Doc_SetRuleCell(doc, ruleUid, x, y, 0)
		imgui.EndGroup()
		return
	}
	level_tip("Clear the pattern", "tab.rules")
	imgui.EndGroup()
	if !UI_BeginProps("##rule_t") do return
	defer {
		UI_EndProps()
		if changed do e.Ldtk_Doc_RulesChanged(doc, layerUid)
	}
	// tiles
	UI_PropLabel("Tiles")
	modeNames := []string{"Individual tiles (one at random)", "Rectangles of tiles (stamps)"}
	if pick, ch := UI_Combo("defs.rule.tilemode", r.stamp ? 1 : 0, modeNames); ch {
		cp("Rule Tile Mode")
		e.LdtkJson_SetStr(robj, "tileMode", pick == 1 ? "Stamp" : "Single", a)
		changed = true
	}
	level_tip("Each match places one of the tiles at random, or one of the rectangles as a block", "tab.rules")
	UI_PropLabel("")
	if ts != nil {
		if ptr := level_texture_ptr(ts.uid); ptr != nil {
			for rect, i in r.tileRects {
				if len(rect) == 0 do continue
				src := e.Ldtk_Doc_TileSrc(ts, int(rect[0]))
				tw, th := f32(ptr.width), f32(ptr.height)
				imgui.Image(transmute(imgui.TextureID)ptr, {26, 26}, {f32(src.x) / tw, f32(src.y) / th}, {f32(int(src.x) + ts.gridSize) / tw, f32(int(src.y) + ts.gridSize) / th})
				level_tip(fmt.tprintf("%d tile(s) - right-click to remove", len(rect)), "tab.rules")
				if imgui.IsItemClicked(.Right) && len(r.tileRects) > 1 {
					cp("Rule Tiles")
					rects := e.LdtkJson_Get(robj, "tileRectsIds")
					ordered_remove(&rects.items, i)
					changed = true
					break
				}
				imgui.SameLine(0, 2)
			}
		}
	}
	imgui.NewLine()
	UI_PropLabel("")
	if UI_Button("Use picked tiles", "defs.rule.tiles") && len(L.tileSel) > 0 {
		cp("Rule Tiles")
		set_rule_tiles(robj, r.stamp, true)
		changed = true
	}
	level_tip("Replace the tiles with the ones picked in the Layers panel's tileset", "tab.rules")
	imgui.SameLine()
	if UI_Button("Add picked", "defs.rule.tiles.add") && len(L.tileSel) > 0 {
		cp("Rule Tiles")
		set_rule_tiles(robj, r.stamp, false)
		changed = true
	}
	level_tip("Add the picked tiles (as more random choices, or one more stamp)", "tab.rules")
	if r.stamp {
		UI_PropLabel("Stamp pivot")
		if p, ch := level_pivot_picker("defs.rule.pivot", r.pivot, "Which point of the stamp sits on the matching cell", "tab.rules"); ch {
			cp("Stamp Pivot")
			e.LdtkJson_SetFloat(robj, "pivotX", p.x, a)
			e.LdtkJson_SetFloat(robj, "pivotY", p.y, a)
			changed = true
		}
	}
	// matching
	UI_PropLabel("Out of bounds")
	{
		names := make([dynamic]string, context.temp_allocator)
		vals := make([dynamic]int, context.temp_allocator)
		append(&names, "no value (doesn't match)")
		append(&vals, -1)
		append(&names, "empty")
		append(&vals, 0)
		cur := 0
		if r.hasOutOfBounds do cur = r.outOfBounds == 0 ? 1 : 0
		for v in sd.values {
			if r.hasOutOfBounds && r.outOfBounds == v.value do cur = len(names)
			append(&names, fmt.tprintf("%d %s", v.value, v.identifier))
			append(&vals, v.value)
		}
		if pick, ch := UI_Combo("defs.rule.oob", cur, names[:]); ch {
			cp("Out of Bounds")
			if vals[pick] < 0 do e.LdtkJson_SetNull(robj, "outOfBoundsValue", a)
			else do set_int(robj, "outOfBoundsValue", vals[pick])
			changed = true
		}
		level_tip("What cells outside the level count as for the pattern", "tab.rules")
	}
	changed |= rule_bool("Active", "defs.rule.active", robj, "active", "The rule on / off", true)
	changed |= rule_bool("Break on match", "defs.rule.break", robj, "breakOnMatch", "A cell this rule paints isn't painted by later rules")
	changed |= rule_bool("Flip X", "defs.rule.flipx", robj, "flipX", "Also match the pattern mirrored horizontally (the tiles flip too)")
	changed |= rule_bool("Flip Y", "defs.rule.flipy", robj, "flipY", "Also match it mirrored vertically")
	UI_PropLabel("Chance")
	chance := f32(r.chance * 100)
	if imgui.InputFloat("##chance", &chance, 0, 0, "%.0f %%", {.EnterReturnsTrue}) {
		cp("Rule Chance")
		e.LdtkJson_SetFloat(robj, "chance", f64(clamp(chance, 0, 100)) / 100, a)
		changed = true
	}
	Drive_Item("defs.rule.chance")
	level_tip("The percentage of matching cells that get tiles (Enter applies)", "tab.rules")
	UI_PropLabel("Opacity")
	alpha := f32(r.alpha)
	if imgui.InputFloat("##alpha", &alpha, 0, 0, "%.2f", {.EnterReturnsTrue}) {
		cp("Rule Opacity")
		e.LdtkJson_SetFloat(robj, "alpha", f64(clamp(alpha, 0, 1)), a)
		changed = true
	}
	level_tip("The tiles' opacity (0-1)", "tab.rules")
	// modulo / checker
	UI_PropLabel("Modulo X, Y")
	mod := [2]i32{i32(r.xModulo), i32(r.yModulo)}
	if int_pair("defs.rule.modulo", &mod) {
		cp("Rule Modulo")
		set_int(robj, "xModulo", max(int(mod.x), 1))
		set_int(robj, "yModulo", max(int(mod.y), 1))
		changed = true
	}
	level_tip("Only every Nth column / row", "rules.modulo")
	UI_PropLabel("Offset X, Y")
	off := [2]i32{i32(r.xOffset), i32(r.yOffset)}
	if int_pair("defs.rule.offset", &off) {
		cp("Rule Modulo")
		set_int(robj, "xOffset", int(off.x))
		set_int(robj, "yOffset", int(off.y))
		changed = true
	}
	level_tip("Shifts which columns / rows the modulo picks", "rules.modulo")
	UI_PropLabel("Checker")
	checkers := []string{"None", "Horizontal", "Vertical"}
	if pick, ch := UI_Combo("defs.rule.checker", int(r.checker), checkers); ch {
		cp("Rule Checker")
		e.LdtkJson_SetStr(robj, "checker", checkers[pick], a)
		changed = true
	}
	level_tip("With a modulo: shift every other row (horizontal) or column (vertical) - a checkerboard", "rules.modulo")
	// Perlin
	changed |= rule_bool("Perlin noise", "defs.rule.perlin", robj, "perlinActive", "Only where a noise is positive: natural-looking patches", false, "rules.perlin")
	if r.perlin {
		UI_PropLabel("Noise seed")
		seed := i32(r.perlinSeed)
		if imgui.InputInt("##pseed", &seed, 1, 100, {.EnterReturnsTrue}) {
			cp("Perlin Seed")
			set_int(robj, "perlinSeed", int(seed))
			changed = true
		}
		level_tip("Change it for another noise", "rules.perlin")
		UI_PropLabel("Noise scale")
		sc := f32(r.perlinScale)
		if imgui.InputFloat("##pscale", &sc, 0.05, 0.1, "%.2f", {.EnterReturnsTrue}) {
			cp("Perlin Scale")
			e.LdtkJson_SetFloat(robj, "perlinScale", f64(max(sc, 0.01)), a)
			changed = true
		}
		level_tip("Smaller: bigger patches", "rules.perlin")
		UI_PropLabel("Octaves")
		oc := i32(r.perlinOctaves)
		if imgui.InputInt("##poct", &oc, 1, 1, {.EnterReturnsTrue}) {
			cp("Perlin Octaves")
			set_int(robj, "perlinOctaves", clamp(int(oc), 1, 8))
			changed = true
		}
		level_tip("More: more detailed edges", "rules.perlin")
	}
	// offsets
	UI_PropLabel("Tile offset X, Y")
	to := [2]i32{i32(r.tileXOffset), i32(r.tileYOffset)}
	if int_pair("defs.rule.tileoffset", &to) {
		cp("Tile Offset")
		set_int(robj, "tileXOffset", int(to.x))
		set_int(robj, "tileYOffset", int(to.y))
		changed = true
	}
	level_tip("Move the placed tiles by these pixels", "rules.offsets")
	UI_PropLabel("Random X min, max")
	rx := [2]i32{i32(r.tileRandomXMin), i32(r.tileRandomXMax)}
	if int_pair("defs.rule.randomx", &rx) {
		cp("Random Offset")
		set_int(robj, "tileRandomXMin", int(min(rx.x, rx.y)))
		set_int(robj, "tileRandomXMax", int(max(rx.x, rx.y)))
		changed = true
	}
	level_tip("A random horizontal shift in pixels per cell", "rules.offsets")
	UI_PropLabel("Random Y min, max")
	ry := [2]i32{i32(r.tileRandomYMin), i32(r.tileRandomYMax)}
	if int_pair("defs.rule.randomy", &ry) {
		cp("Random Offset")
		set_int(robj, "tileRandomYMin", int(min(ry.x, ry.y)))
		set_int(robj, "tileRandomYMax", int(max(ry.x, ry.y)))
		changed = true
	}
	level_tip("A random vertical shift in pixels per cell", "rules.offsets")
}

// int_pair: two int fields on one row (Enter applies), drive ids <id>.x / <id>.y.
@(private = "file")
int_pair :: proc(id: string, v: ^[2]i32) -> bool {
	w := (imgui.GetContentRegionAvail().x - 4) * 0.5
	imgui.SetNextItemWidth(w)
	a := imgui.InputInt(fmt.ctprintf("##%s.x", id), &v.x, 0, 0, {.EnterReturnsTrue})
	Drive_Item(fmt.tprintf("%s.x", id))
	imgui.SameLine(0, 4)
	imgui.SetNextItemWidth(w)
	b := imgui.InputInt(fmt.ctprintf("##%s.y", id), &v.y, 0, 0, {.EnterReturnsTrue})
	Drive_Item(fmt.tprintf("%s.y", id))
	return a || b
}

@(private = "file")
rule_bool :: proc(label, id: string, obj: ^e.LdtkJson, key, tip: string, def := false, topic := "tab.rules") -> bool {
	UI_PropLabel(label)
	v := e.LdtkJson_Bool(obj, key, def)
	ch := imgui.Checkbox(fmt.ctprintf("##%s", id), &v)
	Drive_Item(id)
	level_tip(tip, topic)
	if ch {
		cp(label)
		e.LdtkJson_SetBool(obj, key, v, GlobalLevel.doc.allocator)
	}
	return ch
}

// set_rule_tiles: the palette's picked tiles as the rule's tiles (replace or
// add): stamp mode - one rectangle, individual mode - one per tile.
@(private = "file")
set_rule_tiles :: proc(robj: ^e.LdtkJson, stamp: bool, replace: bool) {
	L := &GlobalLevel
	a := L.doc.allocator
	rects := e.LdtkJson_Get(robj, "tileRectsIds")
	if rects == nil || replace {
		rects = e.LdtkJson_New(.Array, a)
		e.LdtkJson_Set(robj, "tileRectsIds", rects, a)
	}
	if stamp {
		one := e.LdtkJson_New(.Array, a)
		for t in L.tileSel do append(&one.items, e.LdtkJson_NewInt(int(t), a))
		append(&rects.items, one)
	} else {
		for t in L.tileSel {
			one := e.LdtkJson_New(.Array, a)
			append(&one.items, e.LdtkJson_NewInt(int(t), a))
			append(&rects.items, one)
		}
	}
}

@(private = "file")
resize_pattern :: proc(robj: ^e.LdtkJson, r: ^e.Ldtk_DocRule, ns: int) {
	a := GlobalLevel.doc.allocator
	old := r.size
	pat := e.LdtkJson_New(.Array, a)
	pad := (ns - old) / 2
	for y in 0 ..< ns {
		for x in 0 ..< ns {
			ox, oy := x - pad, y - pad
			v := 0
			if ox >= 0 && oy >= 0 && ox < old && oy < old do v = int(r.pattern[ox + oy * old])
			append(&pat.items, e.LdtkJson_NewInt(v, a))
		}
	}
	e.LdtkJson_Set(robj, "pattern", pat, a)
	e.LdtkJson_SetInt(robj, "size", ns, a)
}

// ----------------------------------------------------------------------------
// Rename / remap dialogs
// ----------------------------------------------------------------------------

@(private = "file")
rename_popup :: proc(state: ^EditorState) {
	doc := GlobalLevel.doc
	if lr.renameReq {
		imgui.OpenPopup("Rename Group###LevelRenameGroup")
		lr.renameReq = false
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if !imgui.BeginPopupModal("Rename Group###LevelRenameGroup", nil, {.AlwaysAutoResize}) do return
	defer imgui.EndPopup()
	imgui.SetNextItemWidth(300)
	if imgui.IsWindowAppearing() do imgui.SetKeyboardFocusHere()
	enter := imgui.InputText("##gname", cstring(raw_data(lr.renameBuf[:])), len(lr.renameBuf), {.EnterReturnsTrue})
	Drive_Item("defs.group.rename.name")
	if UI_PrimaryButton("Rename", "defs.group.rename.ok") || enter {
		cp("Rename Group")
		e.Ldtk_Doc_RenameRuleGroup(doc, lr.renameGroup, string(cstring(raw_data(lr.renameBuf[:]))))
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Cancel", "defs.group.rename.cancel") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
}

@(private = "file")
remap_open :: proc(guid: int) {
	doc := GlobalLevel.doc
	g, _, _ := e.Ldtk_Doc_FindRuleGroup(doc, guid)
	if g == nil do return
	lr.remapGroup = guid
	clear(&lr.remapFrom)
	clear(&lr.remapTo)
	for v in e.Ldtk_Doc_RuleGroupValues(doc, guid) {
		append(&lr.remapFrom, v)
		append(&lr.remapTo, v)
	}
	lr.remapOff = {}
	lr.remapName = {}
	copy(lr.remapName[:127], fmt.tprintf("%s copy", e.LdtkJson_Str(g, "name")))
	lr.remapReq = true
}

@(private = "file")
remap_popup :: proc(state: ^EditorState) {
	doc := GlobalLevel.doc
	if lr.remapReq {
		imgui.OpenPopup("Duplicate and Remap###LevelRemapGroup")
		lr.remapReq = false
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if !imgui.BeginPopupModal("Duplicate and Remap###LevelRemapGroup", nil, {.AlwaysAutoResize}) do return
	defer imgui.EndPopup()
	_, layerUid, _ := e.Ldtk_Doc_FindRuleGroup(doc, lr.remapGroup)
	di := e.Ldtk_Doc_LayerDefIndex(doc, layerUid)
	if di < 0 {
		imgui.CloseCurrentPopup()
		return
	}
	sd := src_def(doc, &doc.layerDefs[di])
	UI_DimText("A copy of the group: each value it uses can become another one,")
	UI_DimText("and its tiles can move to another place of the tileset.")
	imgui.SetNextItemWidth(300)
	imgui.InputText("##rname", cstring(raw_data(lr.remapName[:])), len(lr.remapName), {})
	Drive_Item("defs.remap.name")
	if UI_BeginProps("##remap_t") {
		for from, i in lr.remapFrom {
			UI_PropLabel(fmt.tprintf("Value %d becomes", from))
			names := make([dynamic]string, context.temp_allocator)
			cur := 0
			if sd != nil do for v, k in sd.values {
				if i32(v.value) == lr.remapTo[i] do cur = k
				append(&names, fmt.tprintf("%d %s", v.value, v.identifier))
			}
			if len(names) > 0 {
				if pick, ch := UI_Combo(fmt.tprintf("defs.remap.value:%d", from), cur, names[:]); ch do lr.remapTo[i] = i32(sd.values[pick].value)
			}
		}
		UI_PropLabel("Tiles moved by (cells)")
		imgui.InputInt2("##roff", &lr.remapOff, {})
		Drive_Item("defs.remap.offset")
		level_tip("Columns, rows: e.g. 0, 4 uses the tiles four rows lower (another terrain drawn the same way)", "tab.rules")
		UI_EndProps()
	}
	if UI_PrimaryButton("Duplicate", "defs.remap.ok") {
		remap := make(map[i32]i32, allocator = context.temp_allocator)
		for from, i in lr.remapFrom do if lr.remapTo[i] != from do remap[from] = lr.remapTo[i]
		cp("Duplicate Rule Group")
		lr.groupUid = e.Ldtk_Doc_DuplicateRuleGroup(doc, lr.remapGroup, string(cstring(raw_data(lr.remapName[:]))), remap, {int(lr.remapOff.x), int(lr.remapOff.y)})
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Cancel", "defs.remap.cancel") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
}

// ----------------------------------------------------------------------------
// The Rules Assistant
// ----------------------------------------------------------------------------

@(private = "file")
wizard_open :: proc(layerUid: int, guid: int) {
	doc := GlobalLevel.doc
	e.Ldtk_WizardSetup_Destroy(&lr.wiz)
	lr.wizOpen = true
	lr.wizLayer = layerUid
	lr.wizGroup = guid
	lr.wiz.breakOnMatch = true
	lr.wizName = {}
	if guid >= 0 && e.Ldtk_Doc_RulesWizardImport(doc, guid, &lr.wiz) {
		copy(lr.wizName[:127], lr.wiz.name)
	} else {
		lr.wizGroup = -1
		di := e.Ldtk_Doc_LayerDefIndex(doc, layerUid)
		if sd := src_def(doc, &doc.layerDefs[di]); sd != nil && len(sd.values) > 0 {
			lr.wiz.mainValue = sd.values[0].value
			copy(lr.wizName[:127], sd.values[0].identifier != "" ? sd.values[0].identifier : fmt.tprintf("Rules for #%d", sd.values[0].value))
		}
	}
	lr.wizFrag = .Full
}

LevelRules_WizardOpen :: proc() -> bool {return lr.wizOpen}

@(private = "file")
wizard_window :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	if !lr.wizOpen do return
	di := e.Ldtk_Doc_LayerDefIndex(doc, lr.wizLayer)
	if di < 0 {
		lr.wizOpen = false
		return
	}
	d := &doc.layerDefs[di]
	sd := src_def(doc, d)
	ts := e.Ldtk_Doc_Tileset(doc, d.tilesetUid)
	imgui.SetNextWindowSize({720, 470}, .FirstUseEver)
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .FirstUseEver, {0.5, 0.5})
	defer imgui.End()
	if !imgui.Begin(fmt.ctprintf("%s  Rules Assistant###LevelRulesWizard", ICON_FA_WAND_MAGIC_SPARKLES), &lr.wizOpen, {.NoCollapse, .NoDocking}) do return
	Drive_Item("wiz.window")
	LevelRef_Panel("rules.wizard")
	UI_DimText("Click a shape below, then pick its tile(s) in the Layers panel's tileset and click Use picked tiles.")
	UI_DimText("Shapes you leave empty use a mirrored one when there is one.")
	if UI_BeginProps("##wiz_t") {
		UI_PropLabel("Name")
		imgui.InputText("##wname", cstring(raw_data(lr.wizName[:])), len(lr.wizName), {})
		Drive_Item("wiz.name")
		level_tip("The rule group's name", "rules.wizard")
		names := make([dynamic]string, context.temp_allocator)
		cur := 0
		if sd != nil do for v, k in sd.values {
			if v.value == lr.wiz.mainValue do cur = k
			append(&names, fmt.tprintf("%d %s", v.value, v.identifier))
		}
		UI_PropLabel("Value")
		if len(names) > 0 {
			if pick, ch := UI_Combo("wiz.value", cur, names[:]); ch do lr.wiz.mainValue = sd.values[pick].value
		}
		level_tip("The IntGrid value these walls draw over", "rules.wizard")
		UI_PropLabel("Next to")
		others := make([dynamic]string, context.temp_allocator)
		append(&others, "anything else")
		ocur := 0
		if sd != nil do for v, k in sd.values {
			if v.value == lr.wiz.otherValue do ocur = k + 1
			append(&others, fmt.tprintf("%d %s", v.value, v.identifier))
		}
		if pick, ch := UI_Combo("wiz.other", ocur, others[:]); ch do lr.wiz.otherValue = pick == 0 ? 0 : sd.values[pick - 1].value
		level_tip("What the edges are against: any other cell, or a specific value (e.g. walls next to water)", "rules.wizard")
		UI_PropLabel("Break on match")
		imgui.Checkbox("##wbreak", &lr.wiz.breakOnMatch)
		level_tip("Later rules don't paint the cells these rules painted", "rules.wizard")
		UI_EndProps()
	}
	// the fragment grid (12 x 5)
	CELL :: 44
	start := imgui.GetCursorScreenPos()
	dl := imgui.GetWindowDrawList()
	imgui.Dummy({12 * CELL, 5 * CELL})
	m := imgui.GetIO().MousePos
	for f in e.Ldtk_WallFragment {
		at := e.LDTK_FRAGMENT_AT[f]
		p := [2]f32{start.x + f32(at.x) * CELL, start.y + f32(at.y) * CELL}
		mn, mx := p + 2, p + CELL - 2
		hover := m.x >= mn.x && m.y >= mn.y && m.x < mx.x && m.y < mx.y && imgui.IsWindowHovered()
		imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32(lr.wizFrag == f ? UI_ACCENT_SOFT : hover ? UI_BG_HOVER : UI_BG_RAISED), 4, {})
		tiles := lr.wiz.tiles[f]
		if len(tiles) > 0 && ts != nil {
			if ptr := level_texture_ptr(ts.uid); ptr != nil {
				src := e.Ldtk_Doc_TileSrc(ts, int(tiles[0]))
				tw, th := f32(ptr.width), f32(ptr.height)
				imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)ptr, mn + 4, mx - 4, {f32(src.x) / tw, f32(src.y) / th}, {f32(int(src.x) + ts.gridSize) / tw, f32(int(src.y) + ts.gridSize) / th})
			}
		} else {
			// its pattern, small
			mat := e.Ldtk_FragmentMatrix(f)
			c: f32 = 10
			o := mn + {(CELL - 4 - 3 * c) * 0.5, (CELL - 4 - 3 * c) * 0.5}
			for y in 0 ..< 3 do for x in 0 ..< 3 {
				ch := mat[y][x]
				col := ch == 'o' ? imgui.Vec4{0.9, 0.9, 0.9, 1} : ch == 'x' ? imgui.Vec4{0.15, 0.15, 0.15, 1} : imgui.Vec4{0.4, 0.4, 0.45, 0.4}
				imgui.DrawList_AddRectFilled(dl, o + {f32(x) * c, f32(y) * c}, o + {f32(x + 1) * c - 1, f32(y + 1) * c - 1}, col_u32(col), 0, {})
			}
		}
		if lr.wizFrag == f do imgui.DrawList_AddRect(dl, mn, mx, col_u32(UI_ACCENT), 4, {}, 2)
		Drive_ItemRect(fmt.tprintf("wiz.frag:%v", f), mn, mx, true)
		if hover {
			imgui.SetTooltip("%s", fmt.ctprintf("%v: %d tile(s). Click to pick it; right-click to clear.", f, len(tiles)))
			LevelRef_Hover("rules.wizard")
			if imgui.IsMouseClicked(.Left) do lr.wizFrag = f
			if imgui.IsMouseClicked(.Right) do clear(&lr.wiz.tiles[f])
		}
	}
	if UI_Button(fmt.tprintf("Use picked tiles for %v", lr.wizFrag), "wiz.use") && len(L.tileSel) > 0 {
		clear(&lr.wiz.tiles[lr.wizFrag])
		append(&lr.wiz.tiles[lr.wizFrag], ..L.tileSel[:])
	}
	level_tip("The tiles picked in the Layers panel's tileset (several: one at random)", "rules.wizard")
	imgui.SameLine()
	if UI_Button("Clear", "wiz.clear") do clear(&lr.wiz.tiles[lr.wizFrag])
	level_tip("No tiles for this shape", "rules.wizard")
	imgui.Separator()
	if UI_PrimaryButton(lr.wizGroup >= 0 ? "Update rules" : "Create rules", "wiz.ok") {
		any := false
		for t in lr.wiz.tiles do if len(t) > 0 do any = true
		switch {
		case lr.wiz.mainValue == 0: Editor_Log(state, .Warn, "Pick an IntGrid value")
		case !any: Editor_Log(state, .Warn, "Give at least one shape some tiles")
		case:
			lr.wiz.name = string(cstring(raw_data(lr.wizName[:])))
			cp(lr.wizGroup >= 0 ? "Update Assistant Rules" : "Assistant Rules")
			lr.groupUid = e.Ldtk_Doc_RulesWizardApply(doc, lr.wizLayer, lr.wizGroup, &lr.wiz)
			lr.wizOpen = false
		}
	}
	level_tip("Write the rule group", "rules.wizard")
	imgui.SameLine()
	if UI_Button("Cancel", "wiz.cancel") do lr.wizOpen = false
}

// LevelRules_Query answers the drive's rules questions:
//   level.groups      -> "name(rules),..." for the Rules tab's layer
//   level.rule        -> the selected rule: "size tiles chance% flags"
//   level.rulematches -> cells the previewed rule matches in this level
LevelRules_Query :: proc(q: string) -> (string, bool) {
	doc := GlobalLevel.doc
	switch q {
	case "level.groups":
		di := e.Ldtk_Doc_LayerDefIndex(doc, lr.layerUid)
		if di < 0 do return "", true
		b := strings.builder_make(context.temp_allocator)
		for g, i in doc.layerDefs[di].groups {
			if i > 0 do strings.write_byte(&b, ',')
			fmt.sbprintf(&b, "%s(%d)", g.name, len(g.rules))
		}
		return strings.to_string(b), true
	case "level.rule":
		r, _, layerUid := e.Ldtk_Doc_FindRule(doc, lr.ruleUid)
		if r == nil do return "", true
		di := e.Ldtk_Doc_LayerDefIndex(doc, layerUid)
		for g in doc.layerDefs[di].groups do for x in g.rules do if x.uid == lr.ruleUid {
			b := strings.builder_make(context.temp_allocator)
			fmt.sbprintf(&b, "%d %d %.0f%%", x.size, len(x.tileRects), x.chance * 100)
			if x.flipX do strings.write_string(&b, " flipX")
			if x.flipY do strings.write_string(&b, " flipY")
			if x.breakOnMatch do strings.write_string(&b, " break")
			if x.perlin do strings.write_string(&b, " perlin")
			if x.xModulo > 1 || x.yModulo > 1 do fmt.sbprintf(&b, " mod%dx%d", x.xModulo, x.yModulo)
			if x.stamp do strings.write_string(&b, " stamp")
			if !x.active do strings.write_string(&b, " off")
			return strings.to_string(b), true
		}
		return "", true
	case "level.rulematches":
		if levelRulePreview == 0 || len(doc.levels) == 0 do return "0", true
		return fmt.tprint(len(e.Ldtk_Doc_RuleMatchCells(doc, GlobalLevel.level, levelRulePreview))), true
	}
	return "", false
}
