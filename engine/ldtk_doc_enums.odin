package engine

import "core:crypto/legacy/md5"
import "core:fmt"
import "core:mem"
import os "osx"
import "core:path/filepath"
import "core:strings"

// ============================================================================
// Ldtk_Doc enums (LDtk's EditEnumDefs / EnumDef / ExternalEnum): renaming
// enums and values (instances, tileset enum tags and rule biomes follow),
// removing values / enums (like Project.tidy), order, colours, icons, tags,
// copy / paste / duplicate, and external enums imported from Haxe, CastleDB,
// JSON or text files and kept in sync with them (diffs, renames).
// ============================================================================

@(private = "file")
enums_arr :: proc(doc: ^Ldtk_Doc, external := false) -> ^LdtkJson {
	defs := LdtkJson_Get(doc.root, "defs")
	key := external ? "externalEnums" : "enums"
	arr := LdtkJson_Get(defs, key)
	if arr == nil || arr.kind != .Array {
		arr = LdtkJson_New(.Array, doc.allocator)
		LdtkJson_Set(defs, key, arr, doc.allocator)
	}
	return arr
}

Ldtk_Doc_EnumIsExternal :: proc(ed: ^LdtkJson) -> bool {return LdtkJson_Str(ed, "externalRelPath") != ""}

// enum_field_defs: the field defs (entities' and levels') of an enum.
@(private = "file")
enum_field_defs :: proc(doc: ^Ldtk_Doc, enumUid: int) -> [dynamic]^LdtkJson {
	out := make([dynamic]^LdtkJson, context.temp_allocator)
	defs := LdtkJson_Get(doc.root, "defs")
	for f in LdtkJson_Arr(defs, "levelFields") do if Ldtk_FieldEnumUid(f) == enumUid do append(&out, f)
	for e in LdtkJson_Arr(defs, "entities") do for f in LdtkJson_Arr(e, "fieldDefs") do if Ldtk_FieldEnumUid(f) == enumUid do append(&out, f)
	return out
}

// field_instances: every instance of a field def (level fields, their
// external mirrors, entity fields).
@(private = "file")
field_instances :: proc(doc: ^Ldtk_Doc, fieldUid: int) -> [dynamic]^LdtkJson {
	out := make([dynamic]^LdtkJson, context.temp_allocator)
	for &lv in doc.levels {
		for fi in LdtkJson_Arr(lv.obj, "fieldInstances") do if LdtkJson_Int(fi, "defUid", -1) == fieldUid do append(&out, fi)
		if lv.extRoot != nil do for fi in LdtkJson_Arr(lv.extRoot, "fieldInstances") do if LdtkJson_Int(fi, "defUid", -1) == fieldUid do append(&out, fi)
		for &ly in lv.layers do for ent in LdtkJson_Arr(ly.obj, "entityInstances") {
			for fi in LdtkJson_Arr(ent, "fieldInstances") do if LdtkJson_Int(fi, "defUid", -1) == fieldUid do append(&out, fi)
		}
	}
	return out
}

@(private = "file")
touch_levels :: proc(doc: ^Ldtk_Doc) {
	for &lv in doc.levels do lv.dirty = true
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_EnumValueUsed / EnumUsed: Project.isEnumValueUsed / isEnumDefUsed.
Ldtk_Doc_EnumValueUsed :: proc(doc: ^Ldtk_Doc, enumUid: int, valueId: string) -> bool {
	for fd in enum_field_defs(doc, enumUid) {
		for fi in field_instances(doc, LdtkJson_Int(fd, "uid")) {
			for i in 0 ..< len(LdtkJson_Arr(fi, "realEditorValues")) {
				r := Ldtk_Doc_FieldRaw(fi, i)
				if !r.isNull && !r.isDefault && r.text == valueId do return true
			}
		}
	}
	return false
}

Ldtk_Doc_EnumUsed :: proc(doc: ^Ldtk_Doc, enumUid: int) -> bool {
	for fd in enum_field_defs(doc, enumUid) {
		for fi in field_instances(doc, LdtkJson_Int(fd, "uid")) {
			for i in 0 ..< len(LdtkJson_Arr(fi, "realEditorValues")) {
				r := Ldtk_Doc_FieldRaw(fi, i)
				if !r.isNull && !r.isDefault do return true
			}
		}
	}
	return false
}

// Ldtk_Doc_UniqueEnumName: unique among internal and external enums.
Ldtk_Doc_UniqueEnumName :: proc(doc: ^Ldtk_Doc, base: string, except := -1, allocator := context.temp_allocator) -> string {
	clean := Ldtk_Doc_CleanIdentifier(doc, base)
	used :: proc(doc: ^Ldtk_Doc, id: string, except: int) -> bool {
		for ext in ([]bool{false, true}) do for e in enums_arr(doc, ext).items {
			if LdtkJson_Int(e, "uid") != except && LdtkJson_Str(e, "identifier") == id do return true
		}
		return false
	}
	if !used(doc, clean, except) do return strings.clone(clean, allocator)
	stem, idx := ldtk_name_stem(clean)
	for {
		id := fmt.tprintf("%s%d", stem, idx)
		if !used(doc, id, except) do return strings.clone(id, allocator)
		idx += 1
	}
}

// ldtk_name_stem: fixUniqueIdStr's split ("Wall3" -> "Wall", 3; "Wall" ->
// "Wall", 2).
@(private)
ldtk_name_stem :: proc(s: string) -> (string, int) {
	end := len(s)
	for end > 0 && s[end - 1] >= '0' && s[end - 1] <= '9' do end -= 1
	if end == len(s) || end == 0 do return s, 2
	n := 0
	for c in s[end:] do n = n * 10 + int(c - '0')
	return s[:end], n
}

// ldtk_enum_type_label: a field def's "__type" for an enum.
@(private = "file")
enum_type_label :: proc(ed: ^LdtkJson, isArray: bool) -> string {
	base := fmt.tprintf("%s.%s", Ldtk_Doc_EnumIsExternal(ed) ? "ExternEnum" : "LocalEnum", LdtkJson_Str(ed, "identifier"))
	return isArray ? fmt.tprintf("Array<%s>", base) : base
}

// Ldtk_Doc_RenameEnum: the enum's identifier (unique); its fields' types
// follow.
Ldtk_Doc_RenameEnum :: proc(doc: ^Ldtk_Doc, enumUid: int, name: string) {
	a := doc.allocator
	ed := Ldtk_Doc_EnumDef(doc, enumUid)
	if ed == nil do return
	LdtkJson_SetStr(ed, "identifier", Ldtk_Doc_UniqueEnumName(doc, name, enumUid), a)
	ldtk_enum_types_changed(doc, enumUid)
}

@(private)
ldtk_enum_types_changed :: proc(doc: ^Ldtk_Doc, enumUid: int) {
	a := doc.allocator
	ed := Ldtk_Doc_EnumDef(doc, enumUid)
	if ed == nil do return
	for fd in enum_field_defs(doc, enumUid) {
		label := enum_type_label(ed, LdtkJson_Bool(fd, "isArray"))
		LdtkJson_SetStr(fd, "__type", label, a)
		for fi in field_instances(doc, LdtkJson_Int(fd, "uid")) do LdtkJson_SetStr(fi, "__type", label, a)
	}
	touch_levels(doc)
}

@(private = "file")
enum_value :: proc(ed: ^LdtkJson, id: string) -> (^LdtkJson, int) {
	for v, i in LdtkJson_Arr(ed, "values") do if LdtkJson_Str(v, "id") == id do return v, i
	return nil, -1
}

// Ldtk_Doc_RenameEnumValue: EnumDef.renameValue - instances, tileset enum
// tags, rule biomes and field defaults follow. Returns the new id ("" when
// it can't).
Ldtk_Doc_RenameEnumValue :: proc(doc: ^Ldtk_Doc, enumUid: int, from, to: string) -> string {
	a := doc.allocator
	ed := Ldtk_Doc_EnumDef(doc, enumUid)
	if ed == nil || strings.trim_space(to) == "" do return ""
	v, _ := enum_value(ed, from)
	if v == nil do return ""
	clean := Ldtk_Doc_EnumIsExternal(ed) ? to : Ldtk_Doc_CleanIdentifier(doc, to)
	if clean == from do return from
	// unique among the enum's values
	if other, _ := enum_value(ed, clean); other != nil {
		stem, idx := ldtk_name_stem(clean)
		for {
			c := fmt.tprintf("%s%d", stem, idx)
			if o, _ := enum_value(ed, c); o == nil {
				clean = c
				break
			}
			idx += 1
		}
	}
	clean = strings.clone(clean, a)
	LdtkJson_SetStr(v, "id", clean, a)
	for fd in enum_field_defs(doc, enumUid) {
		if d := LdtkJson_Get(fd, "defaultOverride"); d != nil && d.kind == .Object {
			for p, i in LdtkJson_Arr(d, "params") do if p.kind == .String && p.text == from do LdtkJson_Arr(d, "params")[i] = LdtkJson_NewString(clean, a)
		}
		for fi in field_instances(doc, LdtkJson_Int(fd, "uid")) {
			for i in 0 ..< len(LdtkJson_Arr(fi, "realEditorValues")) {
				r := Ldtk_Doc_FieldRaw(fi, i)
				if !r.isNull && !r.isDefault && r.text == from do Ldtk_Doc_SetFieldRaw(doc, fi, i, clean)
			}
			Ldtk_Doc_FieldRebuild(doc, fi)
		}
	}
	for ts in LdtkJson_Arr(LdtkJson_Get(doc.root, "defs"), "tilesets") {
		if LdtkJson_Int(ts, "tagsSourceEnumUid", -1) != enumUid do continue
		for t in LdtkJson_Arr(ts, "enumTags") do if LdtkJson_Str(t, "enumValueId") == from do LdtkJson_SetStr(t, "enumValueId", clean, a)
	}
	ldtk_biome_values(doc, enumUid, from, clean)
	Ldtk_Doc_RefreshDefs(doc)
	touch_levels(doc)
	return clean
}

// ldtk_biome_values renames (to != "") or removes a value in the rule groups
// of layers whose biome field uses this enum.
@(private = "file")
ldtk_biome_values :: proc(doc: ^Ldtk_Doc, enumUid: int, from, to: string) {
	a := doc.allocator
	for d in LdtkJson_Arr(LdtkJson_Get(doc.root, "defs"), "layers") {
		bf := Ldtk_Doc_FieldDef(doc, LdtkJson_Int(d, "biomeFieldUid", -1))
		if bf == nil || Ldtk_FieldEnumUid(bf) != enumUid do continue
		for g in LdtkJson_Arr(d, "autoRuleGroups") {
			vals := LdtkJson_Get(g, "requiredBiomeValues")
			if vals == nil do continue
			for i := len(vals.items) - 1; i >= 0; i -= 1 {
				if vals.items[i].kind != .String || vals.items[i].text != from do continue
				if to == "" do ordered_remove(&vals.items, i)
				else do vals.items[i] = LdtkJson_NewString(to, a)
			}
		}
	}
}

// Ldtk_Doc_RemoveEnumValue: the value goes, and instances using it become
// empty (FieldInstance.tidy); tileset enum tags and rule biomes too.
Ldtk_Doc_RemoveEnumValue :: proc(doc: ^Ldtk_Doc, enumUid: int, id: string) {
	a := doc.allocator
	ed := Ldtk_Doc_EnumDef(doc, enumUid)
	if ed == nil do return
	_, idx := enum_value(ed, id)
	if idx < 0 do return
	ordered_remove(&LdtkJson_Get(ed, "values").items, idx)
	for fd in enum_field_defs(doc, enumUid) {
		if d := LdtkJson_Get(fd, "defaultOverride"); d != nil && d.kind == .Object {
			for p in LdtkJson_Arr(d, "params") do if p.kind == .String && p.text == id do LdtkJson_SetNull(fd, "defaultOverride", a)
		}
		for fi in field_instances(doc, LdtkJson_Int(fd, "uid")) {
			rev := LdtkJson_Get(fi, "realEditorValues")
			if rev == nil do continue
			for i in 0 ..< len(rev.items) {
				r := Ldtk_Doc_FieldRaw(fi, i)
				if r.isNull || r.isDefault || r.text != id do continue
				nv := LdtkJson_New(.Object, a)
				LdtkJson_Set(nv, "id", LdtkJson_NewString("V_Null", a), a)
				rev.items[i] = nv
			}
			Ldtk_Doc_FieldRebuild(doc, fi)
		}
	}
	for ts in LdtkJson_Arr(LdtkJson_Get(doc.root, "defs"), "tilesets") {
		if LdtkJson_Int(ts, "tagsSourceEnumUid", -1) != enumUid do continue
		tags := LdtkJson_Get(ts, "enumTags")
		if tags == nil do continue
		for i := len(tags.items) - 1; i >= 0; i -= 1 do if LdtkJson_Str(tags.items[i], "enumValueId") == id do ordered_remove(&tags.items, i)
	}
	ldtk_biome_values(doc, enumUid, id, "")
	Ldtk_Doc_RefreshDefs(doc)
	touch_levels(doc)
}

// Ldtk_Doc_RemoveEnum deletes an enum: its fields go too
// (tidyFieldDefsArray), tilesets using it for tags lose them, biome fields
// using it are cleared.
Ldtk_Doc_RemoveEnum :: proc(doc: ^Ldtk_Doc, enumUid: int) {
	a := doc.allocator
	for ext in ([]bool{false, true}) {
		arr := enums_arr(doc, ext)
		for e, i in arr.items do if LdtkJson_Int(e, "uid") == enumUid {
			ordered_remove(&arr.items, i)
			break
		}
	}
	fields := enum_field_defs(doc, enumUid)
	for fd in fields {
		fuid := LdtkJson_Int(fd, "uid")
		for d in LdtkJson_Arr(LdtkJson_Get(doc.root, "defs"), "layers") do if LdtkJson_Int(d, "biomeFieldUid", -1) == fuid do LdtkJson_SetNull(d, "biomeFieldUid", a)
		Ldtk_Doc_RemoveFieldDef(doc, fuid)
	}
	for ts in LdtkJson_Arr(LdtkJson_Get(doc.root, "defs"), "tilesets") {
		if LdtkJson_Int(ts, "tagsSourceEnumUid", -1) != enumUid do continue
		LdtkJson_SetNull(ts, "tagsSourceEnumUid", a)
		LdtkJson_Set(ts, "enumTags", LdtkJson_New(.Array, a), a)
	}
	Ldtk_Doc_RefreshDefs(doc)
	touch_levels(doc)
}

// Ldtk_Doc_MoveEnumValue / MoveEnum reorder.
Ldtk_Doc_MoveEnumValue :: proc(doc: ^Ldtk_Doc, enumUid: int, id: string, delta: int) -> bool {
	ed := Ldtk_Doc_EnumDef(doc, enumUid)
	if ed == nil do return false
	_, i := enum_value(ed, id)
	vals := LdtkJson_Get(ed, "values")
	j := i + delta
	if i < 0 || j < 0 || j >= len(vals.items) do return false
	vals.items[i], vals.items[j] = vals.items[j], vals.items[i]
	Ldtk_Doc_Touch(doc)
	return true
}

Ldtk_Doc_MoveEnum :: proc(doc: ^Ldtk_Doc, enumUid: int, delta: int) -> bool {
	arr := enums_arr(doc)
	for e, i in arr.items do if LdtkJson_Int(e, "uid") == enumUid {
		j := i + delta
		if j < 0 || j >= len(arr.items) do return false
		arr.items[i], arr.items[j] = arr.items[j], arr.items[i]
		Ldtk_Doc_Touch(doc)
		return true
	}
	return false
}

// Ldtk_Doc_SetEnumValueColor: an RGB colour (0xRRGGBB).
Ldtk_Doc_SetEnumValueColor :: proc(doc: ^Ldtk_Doc, enumUid: int, id: string, rgb: int) {
	ed := Ldtk_Doc_EnumDef(doc, enumUid)
	if ed == nil do return
	if v, _ := enum_value(ed, id); v != nil do LdtkJson_SetInt(v, "color", rgb, doc.allocator)
	Ldtk_Doc_RefreshDefs(doc)
	touch_levels(doc)
}

// Ldtk_Doc_SetEnumValueTile: the value's icon (a rectangle of the enum's
// icon tileset; tilesetUid < 0 clears it).
Ldtk_Doc_SetEnumValueTile :: proc(doc: ^Ldtk_Doc, enumUid: int, id: string, tilesetUid: int, rect: [4]int) {
	a := doc.allocator
	ed := Ldtk_Doc_EnumDef(doc, enumUid)
	if ed == nil do return
	v, _ := enum_value(ed, id)
	if v == nil do return
	if tilesetUid < 0 {
		LdtkJson_SetNull(v, "tileRect", a)
	} else {
		t := LdtkJson_New(.Object, a)
		LdtkJson_Set(t, "tilesetUid", LdtkJson_NewInt(tilesetUid, a), a)
		LdtkJson_Set(t, "x", LdtkJson_NewInt(rect[0], a), a)
		LdtkJson_Set(t, "y", LdtkJson_NewInt(rect[1], a), a)
		LdtkJson_Set(t, "w", LdtkJson_NewInt(rect[2], a), a)
		LdtkJson_Set(t, "h", LdtkJson_NewInt(rect[3], a), a)
		LdtkJson_Set(v, "tileRect", t, a)
	}
	ldtk_enum_tiles_changed(doc, enumUid)
}

// Ldtk_Doc_SetEnumIconTileset: the tileset values' icons come from (< 0:
// none); the icons are cleared, like LDtk.
Ldtk_Doc_SetEnumIconTileset :: proc(doc: ^Ldtk_Doc, enumUid: int, tilesetUid: int) {
	a := doc.allocator
	ed := Ldtk_Doc_EnumDef(doc, enumUid)
	if ed == nil do return
	if tilesetUid < 0 do LdtkJson_SetNull(ed, "iconTilesetUid", a)
	else do LdtkJson_SetInt(ed, "iconTilesetUid", tilesetUid, a)
	for v in LdtkJson_Arr(ed, "values") do LdtkJson_SetNull(v, "tileRect", a)
	ldtk_enum_tiles_changed(doc, enumUid)
}

// field instances showing enum tiles (__tile) follow the icons
@(private = "file")
ldtk_enum_tiles_changed :: proc(doc: ^Ldtk_Doc, enumUid: int) {
	for fd in enum_field_defs(doc, enumUid) do for fi in field_instances(doc, LdtkJson_Int(fd, "uid")) do Ldtk_Doc_FieldRebuild(doc, fi)
	Ldtk_Doc_RefreshDefs(doc)
	touch_levels(doc)
}

// Ldtk_Doc_EnumText / PasteEnum / DuplicateEnum: Definitions.pasteEnumDef -
// a copy with a new uid and a free name, internal, after `afterUid`.
Ldtk_Doc_EnumText :: proc(doc: ^Ldtk_Doc, enumUid: int, allocator := context.allocator) -> string {
	ed := Ldtk_Doc_EnumDef(doc, enumUid)
	if ed == nil do return ""
	return LdtkJson_ToString(ed, .Minified, allocator)
}

Ldtk_Doc_PasteEnum :: proc(doc: ^Ldtk_Doc, text: string, afterUid := -1) -> int {
	a := doc.allocator
	o, ok := LdtkJson_Parse(text, a)
	if !ok || o.kind != .Object || LdtkJson_Get(o, "values") == nil || LdtkJson_Get(o, "identifier") == nil do return -1
	uid := Ldtk_Doc_NextUid(doc)
	LdtkJson_SetInt(o, "uid", uid, a)
	LdtkJson_SetStr(o, "identifier", Ldtk_Doc_UniqueEnumName(doc, LdtkJson_Str(o, "identifier", "Enum")), a)
	LdtkJson_SetNull(o, "externalRelPath", a)
	LdtkJson_SetNull(o, "externalFileChecksum", a)
	arr := enums_arr(doc)
	at := len(arr.items)
	for e, i in arr.items do if LdtkJson_Int(e, "uid") == afterUid do at = i + 1
	inject_at(&arr.items, at, o)
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_Touch(doc)
	return uid
}

Ldtk_Doc_DuplicateEnum :: proc(doc: ^Ldtk_Doc, enumUid: int) -> int {
	text := Ldtk_Doc_EnumText(doc, enumUid, context.temp_allocator)
	if text == "" do return -1
	return Ldtk_Doc_PasteEnum(doc, text, enumUid)
}

// Ldtk_Doc_SetEnumTags: the enum's tags.
Ldtk_Doc_SetEnumTags :: proc(doc: ^Ldtk_Doc, enumUid: int, tags: []string) {
	a := doc.allocator
	ed := Ldtk_Doc_EnumDef(doc, enumUid)
	if ed == nil do return
	arr := LdtkJson_New(.Array, a)
	for t in tags do if strings.trim_space(t) != "" do append(&arr.items, LdtkJson_NewString(strings.trim_space(t), a))
	LdtkJson_Set(ed, "tags", arr, a)
	Ldtk_Doc_Touch(doc)
}

// ----------------------------------------------------------------------------
// External enums
// ----------------------------------------------------------------------------

Ldtk_ParsedEnumValue :: struct {
	id:      string,
	color:   int, // -1: none
	tile:    [4]int,
	hasTile: bool,
}

Ldtk_ParsedEnum :: struct {
	id:     string,
	values: [dynamic]Ldtk_ParsedEnumValue,
}

// Ldtk_ParseExternalEnums: importer.enu.* - enums in a Haxe source (simple
// enums), a JSON file ({"Enum": ["A", "B"]} or {"Enum": "A, B"}), a text
// file ("Enum: A, B" per line) or a CastleDB file (sheets with a unique id
// column; colours). Everything in the temp allocator.
Ldtk_ParseExternalEnums :: proc(path: string, text: string) -> []Ldtk_ParsedEnum {
	out := make([dynamic]Ldtk_ParsedEnum, context.temp_allocator)
	ext := strings.to_lower(filepath.ext(path), context.temp_allocator)
	switch ext {
	case ".hx": parse_hx(text, &out)
	case ".json": parse_json_enums(text, &out)
	case ".txt": parse_txt(text, &out)
	case ".cdb": parse_cdb(text, &out)
	}
	return out[:]
}

// values_from_string: ExternalEnum.parseValuesFromString - split on the first
// of , ; or space found.
@(private = "file")
values_from_string :: proc(raw: string) -> [dynamic]string {
	out := make([dynamic]string, context.temp_allocator)
	s := strings.trim_space(raw)
	if s == "" do return out
	sep := ""
	for c in ([]string{",", ";", " "}) do if strings.contains(s, c) {
		sep = c
		break
	}
	if sep == "" do return out // (LDtk: a single value isn't split - nor kept)
	for p in strings.split(s, sep, context.temp_allocator) do if t := strings.trim_space(p); t != "" do append(&out, t)
	return out
}

@(private = "file")
add_parsed :: proc(out: ^[dynamic]Ldtk_ParsedEnum, id: string, values: []string) {
	pe := Ldtk_ParsedEnum{id = id, values = make([dynamic]Ldtk_ParsedEnumValue, context.temp_allocator)}
	for v in values do append(&pe.values, Ldtk_ParsedEnumValue{id = v, color = -1})
	append(out, pe)
}

@(private = "file")
parse_txt :: proc(text: string, out: ^[dynamic]Ldtk_ParsedEnum) {
	for line in strings.split_lines(text, context.temp_allocator) {
		colon := strings.index_byte(line, ':')
		if colon < 0 do continue
		id := strings.trim_space(line[:colon])
		if id == "" do continue
		vals := values_from_string(line[colon + 1:])
		add_parsed(out, id, vals[:])
	}
}

@(private = "file")
parse_json_enums :: proc(text: string, out: ^[dynamic]Ldtk_ParsedEnum) {
	root, ok := LdtkJson_Parse(text, context.temp_allocator)
	if !ok || root.kind != .Object do return
	for k, i in root.keys {
		v := root.items[i]
		#partial switch v.kind {
		case .Array:
			if len(v.items) == 0 || v.items[0].kind != .String do continue
			vals := make([dynamic]string, context.temp_allocator)
			for x in v.items do if x.kind == .String do append(&vals, x.text)
			add_parsed(out, k, vals[:])
		case .String:
			vals := values_from_string(v.text)
			add_parsed(out, k, vals[:])
		}
	}
}

@(private = "file")
is_ident_char :: proc(c: u8) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'
}

@(private = "file")
parse_hx :: proc(src: string, out: ^[dynamic]Ldtk_ParsedEnum) {
	// strip comments
	b := strings.builder_make(context.temp_allocator)
	for i := 0; i < len(src); {
		if i + 1 < len(src) && src[i] == '/' && src[i + 1] == '/' {
			for i < len(src) && src[i] != '\n' do i += 1
			continue
		}
		if i + 1 < len(src) && src[i] == '/' && src[i + 1] == '*' {
			i += 2
			for i + 1 < len(src) && !(src[i] == '*' && src[i + 1] == '/') do i += 1
			i += 2
			continue
		}
		strings.write_byte(&b, src[i])
		i += 1
	}
	s := strings.to_string(b)
	// "enum Name {" at a line start
	for i := 0; i < len(s); i += 1 {
		if !(i == 0 || s[i - 1] == '\n' || s[i - 1] == ' ' || s[i - 1] == '\t') do continue
		if !strings.has_prefix(s[i:], "enum") || i + 4 >= len(s) || (s[i + 4] != ' ' && s[i + 4] != '\t') do continue
		// only whitespace before it on its line
		ls := i
		for ls > 0 && s[ls - 1] != '\n' do ls -= 1
		if strings.trim_space(s[ls:i]) != "" do continue
		j := i + 4
		for j < len(s) && (s[j] == ' ' || s[j] == '\t') do j += 1
		ns := j
		for j < len(s) && is_ident_char(s[j]) do j += 1
		name := s[ns:j]
		for j < len(s) && (s[j] == ' ' || s[j] == '\t' || s[j] == '\r' || s[j] == '\n') do j += 1
		if name == "" || j >= len(s) || s[j] != '{' do continue
		// the block
		depth := 1
		k := j + 1
		start := k
		for k < len(s) && depth >= 1 {
			if s[k] == '{' do depth += 1
			else if s[k] == '}' do depth -= 1
			k += 1
		}
		raw := s[start:max(k - 1, start)]
		i = k - 1
		// parametered values aren't supported: skip the enum
		has_param := false
		vals := make([dynamic]string, context.temp_allocator)
		p := 0
		for p < len(raw) {
			if raw[p] >= 'A' && raw[p] <= 'Z' && (p == 0 || !is_ident_char(raw[p - 1])) {
				q := p
				for q < len(raw) && is_ident_char(raw[q]) do q += 1
				r := q
				for r < len(raw) && (raw[r] == ' ' || raw[r] == '\t') do r += 1
				if r < len(raw) && raw[r] == '(' do has_param = true
				if r < len(raw) && raw[r] == ';' do append(&vals, raw[p:q])
				p = q
				continue
			}
			p += 1
		}
		if !has_param && len(vals) > 0 do add_parsed(out, name, vals[:])
	}
}

@(private = "file")
parse_cdb :: proc(text: string, out: ^[dynamic]Ldtk_ParsedEnum) {
	root, ok := LdtkJson_Parse(text, context.temp_allocator)
	if !ok do return
	for sheet in LdtkJson_Arr(root, "sheets") {
		idCol, colorCol := "", ""
		for col in LdtkJson_Arr(sheet, "columns") {
			t := LdtkJson_Get(col, "typeStr")
			ts := t != nil && t.kind == .String ? t.text : fmt.tprint(LdtkJson_Int(col, "typeStr"))
			switch ts {
			case "0": idCol = LdtkJson_Str(col, "name")
			case "11": if colorCol == "" do colorCol = LdtkJson_Str(col, "name")
			}
		}
		if idCol == "" do continue
		pe := Ldtk_ParsedEnum{id = LdtkJson_Str(sheet, "name"), values = make([dynamic]Ldtk_ParsedEnumValue, context.temp_allocator)}
		seen := make(map[string]bool, allocator = context.temp_allocator)
		for line in LdtkJson_Arr(sheet, "lines") {
			id := strings.trim_space(LdtkJson_Str(line, idCol))
			if id == "" || seen[id] do continue
			seen[id] = true
			v := Ldtk_ParsedEnumValue{id = id, color = -1}
			if colorCol != "" do if c := LdtkJson_Get(line, colorCol); c != nil && c.kind == .Number do v.color = int(c.num)
			append(&pe.values, v)
		}
		append(out, pe)
	}
}

// Ldtk_Md5Hex: haxe.crypto.Md5.encode (the externalFileChecksum).
Ldtk_Md5Hex :: proc(text: string, allocator := context.temp_allocator) -> string {
	ctx: md5.Context
	md5.init(&ctx)
	md5.update(&ctx, transmute([]byte)text)
	digest: [md5.DIGEST_SIZE]byte
	md5.final(&ctx, digest[:])
	b := strings.builder_make(allocator)
	for x in digest do fmt.sbprintf(&b, "%02x", x)
	return strings.to_string(b)
}

// Ldtk_EnumSync: what importing / syncing a file would change.
Ldtk_EnumChange :: enum u8 {
	Added,
	Removed,
	Renamed,
}

Ldtk_EnumSyncItem :: struct {
	enumId:  string,
	valueId: string, // "" = the enum itself
	change:  Ldtk_EnumChange,
	to:      string, // Renamed: the new id
	used:    bool,   // Removed: instances use it (asks first)
}

Ldtk_EnumSync :: struct {
	relPath:  string,
	checksum: string,
	parsed:   []Ldtk_ParsedEnum,
	items:    [dynamic]Ldtk_EnumSyncItem,
	conflict: string, // an enum id already used by another source / internal enum
	isNew:    bool,
}

// Ldtk_Doc_ExternalEnumDiff: ExternalEnum.load + importToProject's diff for
// a file (path relative to the project). ok = false: unreadable or empty.
Ldtk_Doc_ExternalEnumDiff :: proc(doc: ^Ldtk_Doc, relPath: string) -> (sync: Ldtk_EnumSync, ok: bool) {
	abs, _ := filepath.join({doc.dir, relPath}, context.temp_allocator)
	bytes, err := os.read_entire_file(abs, context.temp_allocator)
	if err != nil || len(bytes) == 0 do return {}, false
	text := string(bytes)
	sync.relPath = relPath
	sync.checksum = Ldtk_Md5Hex(text)
	parsed := Ldtk_ParseExternalEnums(relPath, text)
	// sanitize ids
	for &pe in parsed {
		pe.id = Ldtk_Doc_CleanIdentifier(doc, pe.id)
		seen := make(map[string]bool, allocator = context.temp_allocator)
		for &v in pe.values {
			id := v.id
			if seen[id] {
				stem, n := ldtk_name_stem(id)
				for seen[fmt.tprintf("%s%d", stem, n)] do n += 1
				id = fmt.tprintf("%s%d", stem, n)
			}
			seen[id] = true
			v.id = id
		}
	}
	sync.parsed = parsed
	sync.items = make([dynamic]Ldtk_EnumSyncItem, context.temp_allocator)
	// conflicts
	for pe in parsed {
		for ext in ([]bool{false, true}) do for e in enums_arr(doc, ext).items {
			if LdtkJson_Str(e, "identifier") == pe.id && LdtkJson_Str(e, "externalRelPath") != relPath {
				sync.conflict = pe.id
				return sync, true
			}
		}
	}
	sync.isNew = true
	for e in enums_arr(doc, true).items do if LdtkJson_Str(e, "externalRelPath") == relPath do sync.isNew = false
	find :: proc(doc: ^Ldtk_Doc, id, relPath: string) -> ^LdtkJson {
		for e in enums_arr(doc, true).items do if LdtkJson_Str(e, "identifier") == id && LdtkJson_Str(e, "externalRelPath") == relPath do return e
		return nil
	}
	for pe in parsed {
		ed := find(doc, pe.id, relPath)
		if ed == nil {
			append(&sync.items, Ldtk_EnumSyncItem{enumId = pe.id, change = .Added})
			continue
		}
		for v in pe.values do if ev, _ := enum_value(ed, v.id); ev == nil do append(&sync.items, Ldtk_EnumSyncItem{enumId = pe.id, valueId = v.id, change = .Added})
		uid := LdtkJson_Int(ed, "uid")
		for ev in LdtkJson_Arr(ed, "values") {
			id := LdtkJson_Str(ev, "id")
			found := false
			for v in pe.values do if v.id == id do found = true
			if !found do append(&sync.items, Ldtk_EnumSyncItem{enumId = pe.id, valueId = id, change = .Removed, used = Ldtk_Doc_EnumValueUsed(doc, uid, id)})
		}
	}
	for e in enums_arr(doc, true).items {
		if LdtkJson_Str(e, "externalRelPath") != relPath do continue
		id := LdtkJson_Str(e, "identifier")
		found := false
		for pe in parsed do if pe.id == id do found = true
		if !found do append(&sync.items, Ldtk_EnumSyncItem{enumId = id, change = .Removed, used = Ldtk_Doc_EnumUsed(doc, LdtkJson_Int(e, "uid"))})
	}
	return sync, true
}

// Ldtk_EnumSync_NeedsConfirm: something used would be removed.
Ldtk_EnumSync_NeedsConfirm :: proc(s: ^Ldtk_EnumSync) -> bool {
	for it in s.items do if it.change == .Removed && it.used do return true
	return false
}

// Ldtk_Doc_ApplyEnumSync: applyDiff + preserveEnumValuesOrder +
// copyParsedValuesData + checksums. Removed items whose `change` was set to
// Renamed (with `to` an added value) rename instead.
Ldtk_Doc_ApplyEnumSync :: proc(doc: ^Ldtk_Doc, s: ^Ldtk_EnumSync) {
	a := doc.allocator
	find :: proc(doc: ^Ldtk_Doc, id, relPath: string) -> ^LdtkJson {
		for e in enums_arr(doc, true).items do if LdtkJson_Str(e, "identifier") == id && LdtkJson_Str(e, "externalRelPath") == relPath do return e
		return nil
	}
	// renames first (the target value doesn't exist yet: rename the old one)
	renamedTo := make(map[string]bool, allocator = context.temp_allocator)
	for it in s.items {
		if it.change != .Renamed || it.valueId == "" do continue
		ed := find(doc, it.enumId, s.relPath)
		if ed == nil do continue
		Ldtk_Doc_RenameEnumValue(doc, LdtkJson_Int(ed, "uid"), it.valueId, it.to)
		renamedTo[fmt.tprintf("%s.%s", it.enumId, it.to)] = true
	}
	for it in s.items {
		switch it.change {
		case .Renamed:
		case .Removed:
			ed := find(doc, it.enumId, s.relPath)
			if ed == nil do continue
			if it.valueId == "" do Ldtk_Doc_RemoveEnum(doc, LdtkJson_Int(ed, "uid"))
			else do Ldtk_Doc_RemoveEnumValue(doc, LdtkJson_Int(ed, "uid"), it.valueId)
		case .Added:
			if it.valueId == "" {
				o := LdtkJson_New(.Object, a)
				LdtkJson_Set(o, "identifier", LdtkJson_NewString(it.enumId, a), a)
				LdtkJson_Set(o, "uid", LdtkJson_NewInt(Ldtk_Doc_NextUid(doc), a), a)
				LdtkJson_Set(o, "values", LdtkJson_New(.Array, a), a)
				LdtkJson_Set(o, "iconTilesetUid", LdtkJson_New(.Null, a), a)
				LdtkJson_Set(o, "externalRelPath", LdtkJson_NewString(s.relPath, a), a)
				LdtkJson_Set(o, "externalFileChecksum", LdtkJson_NewString(s.checksum, a), a)
				LdtkJson_Set(o, "tags", LdtkJson_New(.Array, a), a)
				append(&enums_arr(doc, true).items, o)
			} else if !renamedTo[fmt.tprintf("%s.%s", it.enumId, it.valueId)] {
				ed := find(doc, it.enumId, s.relPath)
				if ed != nil do append(&LdtkJson_Get(ed, "values").items, new_value(it.valueId, a))
			}
		}
	}
	// the file's values: order, colours (new enums get every value)
	for pe in s.parsed {
		ed := find(doc, pe.id, s.relPath)
		if ed == nil do continue
		vals := LdtkJson_Get(ed, "values")
		for v in pe.values do if ev, _ := enum_value(ed, v.id); ev == nil do append(&vals.items, new_value(v.id, a))
		ordered := make([dynamic]^LdtkJson, a)
		for v in pe.values {
			if ev, _ := enum_value(ed, v.id); ev != nil {
				if v.color >= 0 do LdtkJson_SetInt(ev, "color", v.color, a)
				append(&ordered, ev)
			}
		}
		for ev in vals.items {
			keep := true
			for o in ordered do if o == ev do keep = false
			if keep do append(&ordered, ev)
		}
		vals.items = ordered
		ldtk_enum_types_changed(doc, LdtkJson_Int(ed, "uid"))
	}
	for e in enums_arr(doc, true).items do if LdtkJson_Str(e, "externalRelPath") == s.relPath do LdtkJson_SetStr(e, "externalFileChecksum", s.checksum, a)
	Ldtk_Doc_RefreshDefs(doc)
	touch_levels(doc)
}

@(private = "file")
new_value :: proc(id: string, a: mem.Allocator) -> ^LdtkJson {
	o := LdtkJson_New(.Object, a)
	LdtkJson_Set(o, "id", LdtkJson_NewString(id, a), a)
	LdtkJson_Set(o, "tileRect", LdtkJson_New(.Null, a), a)
	LdtkJson_Set(o, "color", LdtkJson_NewInt(0, a), a)
	return o
}

// Ldtk_Doc_RemoveExternalEnumSource deletes every enum imported from a file.
Ldtk_Doc_RemoveExternalEnumSource :: proc(doc: ^Ldtk_Doc, relPath: string) {
	uids := make([dynamic]int, context.temp_allocator)
	for e in enums_arr(doc, true).items do if LdtkJson_Str(e, "externalRelPath") == relPath do append(&uids, LdtkJson_Int(e, "uid"))
	for u in uids do Ldtk_Doc_RemoveEnum(doc, u)
}

// Ldtk_Doc_ExternalEnumSources: the files external enums come from, and
// whether each changed since the last sync (checksum) or is missing.
Ldtk_EnumSource :: struct {
	relPath:  string,
	missing:  bool,
	modified: bool,
}

Ldtk_Doc_ExternalEnumSources :: proc(doc: ^Ldtk_Doc) -> []Ldtk_EnumSource {
	out := make([dynamic]Ldtk_EnumSource, context.temp_allocator)
	for e in enums_arr(doc, true).items {
		rel := LdtkJson_Str(e, "externalRelPath")
		known := false
		for o in out do if o.relPath == rel do known = true
		if known || rel == "" do continue
		src := Ldtk_EnumSource{relPath = rel}
		abs, _ := filepath.join({doc.dir, rel}, context.temp_allocator)
		bytes, err := os.read_entire_file(abs, context.temp_allocator)
		if err != nil {
			src.missing = true
		} else {
			sum := Ldtk_Md5Hex(string(bytes))
			for x in enums_arr(doc, true).items do if LdtkJson_Str(x, "externalRelPath") == rel && LdtkJson_Str(x, "externalFileChecksum") != sum do src.modified = true
		}
		append(&out, src)
	}
	return out[:]
}
