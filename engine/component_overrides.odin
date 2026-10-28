package engine

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"

// ============================================================================
// Per-node overrides for linked component (prefab) instances.
//
// An instance is saved as its link plus what differs from the component
// file, for the root *and every child*:
//
//   {"name": "Ship2", "position": [..], "component": "components/ship.component.json",
//    "overrides": {".":        {"script": {"properties": {"speed": 300}}},
//                  "Thruster": {"properties": {"color": [255, 0, 0, 255]}},
//                  "Thruster/Flame": {"visible": false}}}
//
// Keys are child paths by name from the instance root ("." = the root).
// On load the overrides are merged into the component's JSON before the
// nodes are built, so a changed component file still flows into every
// instance except for the values the instance overrides. "properties" and
// a script's "properties" merge key by key; other keys replace the value;
// null removes a key. The structure (which children exist) always comes
// from the component file.
// ============================================================================

// Set while serializing an instance in full (to diff it against its file).
@(private)
serializeFullInstance: ^Node

// Root keys an instance stores directly (not as overrides).
@(private = "file")
ROOT_DIRECT_KEYS :: []string{"type", "name", "position", "scale", "rotation", "enabled", "visible", "layer", "component", "overrides", "children", "connections"}

@(private = "file")
contains_str :: proc(list: []string, s: string) -> bool {
	for x in list do if x == s do return true
	return false
}

// json_equal compares two JSON values (numbers with a small tolerance).
json_equal :: proc(a, b: json.Value) -> bool {
	num :: proc(v: json.Value) -> (f64, bool) {
		#partial switch x in v {
		case json.Integer: return f64(x), true
		case json.Float:   return f64(x), true
		}
		return 0, false
	}
	if na, oka := num(a); oka {
		nb, okb := num(b)
		return okb && math.abs(na - nb) < 1e-4
	}
	switch x in a {
	case json.Null:
		_, ok := b.(json.Null)
		return ok || b == nil
	case json.Integer, json.Float:
		return false
	case json.Boolean:
		y, ok := b.(json.Boolean)
		return ok && x == y
	case json.String:
		y, ok := b.(json.String)
		return ok && x == y
	case json.Array:
		y, ok := b.(json.Array)
		if !ok || len(x) != len(y) do return false
		for i in 0 ..< len(x) do if !json_equal(x[i], y[i]) do return false
		return true
	case json.Object:
		y, ok := b.(json.Object)
		if !ok || len(x) != len(y) do return false
		for k, v in x {
			w, has := y[k]
			if !has || !json_equal(v, w) do return false
		}
		return true
	}
	return b == nil
}

// Json_WriteValue writes a JSON value with sorted object keys (stable
// output: scene "modified" checks compare serialized text).
Json_WriteValue :: proc(w: ^Json_Writer, v: json.Value) {
	switch x in v {
	case json.Null:    strings.write_string(&w.sb, "null")
	case json.Integer: fmt.sbprintf(&w.sb, "%d", x)
	case json.Float:   Json_Float(w, f32(x))
	case json.Boolean: strings.write_string(&w.sb, "true" if x else "false")
	case json.String:  Json_String(w, x)
	case json.Array:
		strings.write_byte(&w.sb, '[')
		for item, i in x {
			if i > 0 do strings.write_string(&w.sb, ", ")
			Json_WriteValue(w, item)
		}
		strings.write_byte(&w.sb, ']')
	case json.Object:
		keys := make([dynamic]string, context.temp_allocator)
		for k in x do append(&keys, k)
		slice.sort(keys[:])
		strings.write_byte(&w.sb, '{')
		for k, i in keys {
			if i > 0 do strings.write_string(&w.sb, ", ")
			Json_String(w, k)
			strings.write_string(&w.sb, ": ")
			Json_WriteValue(w, x[k])
		}
		strings.write_byte(&w.sb, '}')
	case:
		strings.write_string(&w.sb, "null")
	}
}

@(private = "file")
diff_keywise :: proc(base, inst: json.Object) -> (json.Object, bool) {
	out := make(json.Object, 0, context.temp_allocator)
	for k, v in inst {
		bv, has := base[k]
		if !has || !json_equal(bv, v) do out[k] = v
	}
	for k in base {
		if _, has := inst[k]; !has do out[k] = json.Null{}
	}
	return out, len(out) > 0
}

// diff_node collects what `inst` changes relative to `base` (one node).
@(private = "file")
diff_node :: proc(base, inst: json.Object, isRoot: bool) -> (json.Object, bool) {
	out := make(json.Object, 0, context.temp_allocator)
	for k, v in inst {
		if k == "children" || k == "type" do continue
		if isRoot && contains_str(ROOT_DIRECT_KEYS, k) do continue
		if !isRoot && k == "name" do continue
		bv, has := base[k]
		if !has {
			out[k] = v
			continue
		}
		if json_equal(bv, v) do continue
		bo, bIsObj := bv.(json.Object)
		io, iIsObj := v.(json.Object)
		switch {
		case k == "properties" && bIsObj && iIsObj:
			if d, changed := diff_keywise(bo, io); changed do out[k] = d
		case k == "script" && bIsObj && iIsObj && json_equal(bo["path"], io["path"]):
			bp, _ := bo["properties"].(json.Object)
			ip, _ := io["properties"].(json.Object)
			if bp == nil do bp = make(json.Object, 0, context.temp_allocator)
			if ip == nil do ip = make(json.Object, 0, context.temp_allocator)
			if d, changed := diff_keywise(bp, ip); changed {
				s := make(json.Object, 0, context.temp_allocator)
				s["properties"] = d
				out[k] = s
			}
		case:
			out[k] = v
		}
	}
	for k in base {
		if k == "children" || k == "type" || (isRoot && contains_str(ROOT_DIRECT_KEYS, k)) || (!isRoot && k == "name") do continue
		if _, has := inst[k]; !has do out[k] = json.Null{}
	}
	return out, len(out) > 0
}

@(private = "file")
child_by_name :: proc(obj: json.Object, name: string) -> (json.Object, bool) {
	arr, ok := obj["children"].(json.Array)
	if !ok do return nil, false
	for c in arr {
		co, isObj := c.(json.Object)
		if !isObj do continue
		if n, _ := co["name"].(json.String); n == name do return co, true
	}
	return nil, false
}

@(private = "file")
diff_tree :: proc(base, inst: json.Object, path: string, out: ^json.Object, added: ^json.Object, removed: ^json.Array) {
	if d, changed := diff_node(base, inst, path == "."); changed do out[path] = d
	instKids, _ := inst["children"].(json.Array)
	for c in instKids {
		co, isObj := c.(json.Object)
		if !isObj do continue
		name, _ := co["name"].(json.String)
		bc, found := child_by_name(base, string(name))
		if !found {
			// A node added to this instance: saved in full under its parent.
			list, _ := added[path].(json.Array)
			if list == nil do list = make(json.Array, context.temp_allocator)
			append(&list, co)
			added[path] = list
			continue
		}
		childPath := string(name) if path == "." else fmt.tprintf("%s/%s", path, name)
		diff_tree(bc, co, childPath, out, added, removed)
	}
	// Component children removed from this instance.
	baseKids, _ := base["children"].(json.Array)
	for c in baseKids {
		co, isObj := c.(json.Object)
		if !isObj do continue
		name, _ := co["name"].(json.String)
		if _, stillThere := child_by_name(inst, string(name)); stillThere do continue
		append(removed, json.String(string(name) if path == "." else fmt.tprintf("%s/%s", path, name)))
	}
}

// component_base_json: the component file's node object.
@(private = "file")
component_base_json :: proc(ctx: ^GameContext, compPath: string) -> (json.Object, bool) {
	data, ok := Component_ReadFile(ctx, compPath)
	if !ok do return nil, false
	val, err := json.parse(data, allocator = context.temp_allocator)
	if err != .None do return nil, false
	obj, isObj := val.(json.Object)
	if !isObj do return nil, false
	if inner, has := obj["node"].(json.Object); has do obj = inner
	return obj, true
}

// --- base normalization ------------------------------------------------------------
// Hand-written (or older) component files omit default values. Before
// diffing, the base JSON gets each node type's defaults and each script's
// declared property defaults, so an unchanged instance has no overrides
// (and a later change to the component file isn't masked by a default).

@(private = "file")
typeDefaults: map[string]string // type name -> serialized default node

@(private = "file")
type_defaults :: proc(typeName: string) -> (json.Object, bool) {
	text, cached := typeDefaults[typeName]
	if !cached {
		scratch := new(Scene)
		InitializeScene(scratch)
		n := Node_CreateByTypeName(scratch, typeName)
		if n != nil {
			ProcessNodeQueues(scratch.manager, nil)
			text = strings.clone(Node_SerializeToJSON(n, scratch.manager, context.temp_allocator), runtime_heap())
		}
		TerminateScene(scratch)
		free(scratch)
		if typeDefaults == nil do typeDefaults = make(map[string]string, 16, runtime_heap())
		typeDefaults[strings.clone(typeName, runtime_heap())] = text
	}
	if text == "" do return nil, false
	val, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None do return nil, false
	obj, ok := val.(json.Object)
	return obj, ok
}

@(private = "file")
script_value_json :: proc(v: ScriptValue) -> json.Value {
	switch v.type {
	case .Float:   return json.Float(v.valFloat)
	case .Int:     return json.Integer(v.valInt)
	case .Boolean: return json.Boolean(v.valBool)
	case .String:  return json.String(v.valString)
	case .Vector2:
		arr := make(json.Array, 2, context.temp_allocator)
		arr[0], arr[1] = json.Float(v.valVec2.x), json.Float(v.valVec2.y)
		return arr
	case .Color:
		arr := make(json.Array, 4, context.temp_allocator)
		for c, i in v.valColor do arr[i] = json.Float(c)
		return arr
	}
	return nil
}

// deep_fill sets obj[k] = v when missing; objects are filled key by key.
@(private = "file")
deep_fill :: proc(obj: ^json.Object, k: string, v: json.Value) {
	cur, has := obj[k]
	if !has {
		obj[k] = v
		return
	}
	co, cIsObj := cur.(json.Object)
	do_, dIsObj := v.(json.Object)
	if cIsObj && dIsObj {
		for sk, sv in do_ do deep_fill(&co, sk, sv)
		obj[k] = co
	}
}

// normalize_base fills defaults into a component node tree (in place).
@(private = "file")
normalize_base :: proc(obj: ^json.Object, ctx: ^GameContext) {
	typeName, _ := obj["type"].(json.String)
	if typeName == "" do typeName = "Node"
	if _, isLink := obj["component"]; !isLink {
		if defs, ok := type_defaults(string(typeName)); ok {
			for k, v in defs {
				if k == "children" || k == "name" do continue
				deep_fill(obj, k, v)
			}
		}
	}
	// Script property defaults.
	if so, has := obj["script"].(json.Object); has {
		path, _ := so["path"].(json.String)
		mgr := ctx.scriptManager if ctx != nil else nil
		if path != "" && mgr != nil {
			if mod, ok := ScriptManager_LoadModule(string(path), mgr); ok && mod != nil {
				props, hasProps := so["properties"].(json.Object)
				if !hasProps do props = make(json.Object, 0, context.temp_allocator)
				for p in mod.properties do if _, hp := props[p.name]; !hp do props[p.name] = script_value_json(p.defaultVal)
				so["properties"] = props
				obj["script"] = so
			}
		}
	}
	if arr, ok := obj["children"].(json.Array); ok {
		for &c in arr {
			if _, isObj := c.(json.Object); isObj do normalize_base(&c.(json.Object), ctx)
		}
	}
}

// Component_OverridesJSON: the "overrides" object for an instance ("" if
// it matches its component file).
Component_OverridesJSON :: proc(node: ^Node, manager: ^NodeManager) -> string {
	if node == nil || node.componentPath == "" do return ""
	// Diff against the component JSON this instance was built from (not
	// the file as it is now: after the file changes, unchanged values must
	// still follow it).
	base: json.Object
	if node.componentBase != "" {
		val, err := json.parse(transmute([]u8)node.componentBase, allocator = context.temp_allocator)
		if err != .None do return ""
		base, _ = val.(json.Object)
	} else {
		ok: bool
		base, ok = component_base_json(node.gameContext, node.componentPath)
		if !ok do return ""
		normalize_base(&base, node.gameContext)
	}
	prev := serializeFullInstance
	serializeFullInstance = node
	full := Node_SerializeToJSON(node, manager, context.temp_allocator)
	serializeFullInstance = prev
	val, err := json.parse(transmute([]u8)full, allocator = context.temp_allocator)
	if err != .None do return ""
	inst, isObj := val.(json.Object)
	if !isObj do return ""
	out := make(json.Object, 0, context.temp_allocator)
	added := make(json.Object, 0, context.temp_allocator)
	removed := make(json.Array, 0, context.temp_allocator)
	diff_tree(base, inst, ".", &out, &added, &removed)
	if len(added) > 0 do out[OVERRIDE_ADDED] = added
	if len(removed) > 0 do out[OVERRIDE_REMOVED] = removed
	if len(out) == 0 do return ""
	w := Json_Writer{sb = strings.builder_make(context.temp_allocator)}
	Json_WriteValue(&w, out)
	return strings.to_string(w.sb)
}

@(private = "file")
merge_keywise :: proc(target: ^json.Object, ov: json.Object) {
	for k, v in ov {
		if _, isNull := v.(json.Null); isNull || v == nil {
			delete_key(target, k)
		} else {
			target[k] = v
		}
	}
}

@(private = "file")
merge_node :: proc(target: ^json.Object, ov: json.Object) {
	for k, v in ov {
		if _, isNull := v.(json.Null); isNull || v == nil {
			delete_key(target, k)
			continue
		}
		vo, vIsObj := v.(json.Object)
		to, tIsObj := target[k].(json.Object)
		switch {
		case k == "properties" && vIsObj && tIsObj:
			merge_keywise(&to, vo)
			target[k] = to
		case k == "script" && vIsObj && tIsObj:
			for sk, sv in vo {
				svo, svIsObj := sv.(json.Object)
				tpo, tpIsObj := to[sk].(json.Object)
				if sk == "properties" && svIsObj && tpIsObj {
					merge_keywise(&tpo, svo)
					to[sk] = tpo
				} else {
					to[sk] = sv
				}
			}
			target[k] = to
		case:
			target[k] = v
		}
	}
}

// Component_PrepareBase normalizes a component's node JSON (in place) and
// returns it as text, to remember as the instance's base.
Component_PrepareBase :: proc(obj: ^json.Object, ctx: ^GameContext) -> string {
	normalize_base(obj, ctx)
	w := Json_Writer{sb = strings.builder_make(context.temp_allocator)}
	Json_WriteValue(&w, obj^)
	return strings.to_string(w.sb)
}

// Component_ApplyOverrides merges an instance's overrides into the
// component's node JSON (in place).
// Keys of the structural changes in an "overrides" block.
OVERRIDE_ADDED :: "$added"     // {"parent/path": [node, ...]}: nodes added to the instance
OVERRIDE_REMOVED :: "$removed" // ["child/path", ...]: component nodes removed from it

// find_node_obj: the node object at a name path ("." = the root).
@(private = "file")
find_node_obj :: proc(root: ^json.Object, path: string) -> ^json.Object {
	target := root
	if path == "." || path == "" do return target
	for part in strings.split(path, "/", context.temp_allocator) {
		arr, has := target["children"].(json.Array)
		if !has do return nil
		found := false
		for &c in arr {
			co, cIsObj := c.(json.Object)
			if !cIsObj do continue
			if n, _ := co["name"].(json.String); string(n) == part {
				// json.Object is a map: the pointer we write through is the same map.
				target = &c.(json.Object)
				found = true
				break
			}
		}
		if !found do return nil
	}
	return target
}

Component_ApplyOverrides :: proc(base: ^json.Object, overrides: json.Object) {
	// Removed nodes first (paths refer to the component's structure).
	if removed, ok := overrides[OVERRIDE_REMOVED].(json.Array); ok {
		for rv in removed {
			path, isStr := rv.(json.String)
			if !isStr do continue
			p := string(path)
			slash := strings.last_index_byte(p, '/')
			parentPath := p[:slash] if slash >= 0 else "."
			name := p[slash + 1:]
			parent := find_node_obj(base, parentPath)
			if parent == nil do continue
			kids, has := parent["children"].(json.Array)
			if !has do continue
			for c, i in kids {
				co, cIsObj := c.(json.Object)
				if !cIsObj do continue
				if n, _ := co["name"].(json.String); string(n) == name {
					ordered_remove(&kids, i)
					break
				}
			}
			parent["children"] = kids
		}
	}
	for path, ov in overrides {
		if path == OVERRIDE_ADDED || path == OVERRIDE_REMOVED do continue
		ovo, isObj := ov.(json.Object)
		if !isObj do continue
		if target := find_node_obj(base, path); target != nil do merge_node(target, ovo)
	}
	if added, ok := overrides[OVERRIDE_ADDED].(json.Object); ok {
		for parentPath, list in added {
			parent := find_node_obj(base, parentPath)
			nodes, isArr := list.(json.Array)
			if parent == nil || !isArr do continue
			kids, _ := parent["children"].(json.Array)
			if kids == nil do kids = make(json.Array, context.temp_allocator)
			for n in nodes do append(&kids, n)
			parent["children"] = kids
		}
	}
}

// Node_HasComponentOverrides: does this node (inside an instance) differ
// from the component file?
Node_ComponentOverridePath :: proc(manager: ^NodeManager, node: ^Node) -> (root: ^Node, path: string) {
	root = Node_ComponentRoot(manager, node)
	if root == nil do return nil, ""
	if root == node do return root, "."
	parts := make([dynamic]string, context.temp_allocator)
	for n := node; n != nil && n != root; n = GetParent(manager, n) do inject_at(&parts, 0, n.name)
	return root, strings.join(parts[:], "/", context.temp_allocator)
}

// Node_ComponentOverrides returns the override keys of a node inside an
// instance (empty when it matches the component).
Node_ComponentOverrides :: proc(manager: ^NodeManager, node: ^Node) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	root, path := Node_ComponentOverridePath(manager, node)
	if root == nil do return out[:]
	text := Component_OverridesJSON(root, manager)
	if text == "" do return out[:]
	val, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None do return out[:]
	obj, _ := val.(json.Object)
	// Structural changes at this node: children added / removed.
	if added, ok := obj[OVERRIDE_ADDED].(json.Object); ok {
		if list, has := added[path].(json.Array); has && len(list) > 0 do append(&out, fmt.tprintf("+%d child(ren)", len(list)))
	}
	if removed, ok := obj[OVERRIDE_REMOVED].(json.Array); ok {
		n := 0
		for rv in removed {
			p, _ := rv.(json.String)
			parent := "."
			if i := strings.last_index_byte(string(p), '/'); i >= 0 do parent = string(p)[:i]
			if parent == path do n += 1
		}
		if n > 0 do append(&out, fmt.tprintf("-%d child(ren)", n))
	}
	entry, has := obj[path].(json.Object)
	if !has do return out[:]
	for k, v in entry {
		if sub, isObj := v.(json.Object); isObj && (k == "properties" || k == "script") {
			if k == "script" {
				if p, hp := sub["properties"].(json.Object); hp {
					for pk in p do append(&out, fmt.tprintf("script.%s", pk))
					continue
				}
			}
			for sk in sub do append(&out, fmt.tprintf("%s.%s", k, sk) if k == "script" else sk)
			continue
		}
		append(&out, k)
	}
	slice.sort(out[:])
	return out[:]
}

// Scene_RevertComponentOverrides drops a node's overrides (all of them
// when `node` is the instance root) and rebuilds the instance.
Scene_RevertComponentOverrides :: proc(scene: ^Scene, node: ^Node, ctx: ^GameContext) -> ^Node {
	mgr := scene.manager
	root, path := Node_ComponentOverridePath(mgr, node)
	if root == nil do return nil
	instJson := Node_SerializeToJSON(root, mgr, context.temp_allocator)
	val, err := json.parse(transmute([]u8)instJson, allocator = context.temp_allocator)
	if err != .None do return nil
	obj, _ := val.(json.Object)
	if ov, has := obj["overrides"].(json.Object); has {
		if path == "." {
			delete_key(&obj, "overrides")
		} else {
			delete_key(&ov, path)
			// ...and the children added under / removed from this node.
			if added, ok := ov[OVERRIDE_ADDED].(json.Object); ok {
				delete_key(&added, path)
				ov[OVERRIDE_ADDED] = added
			}
			if removed, ok := ov[OVERRIDE_REMOVED].(json.Array); ok {
				kept := make(json.Array, 0, context.temp_allocator)
				for rv in removed {
					p, _ := rv.(json.String)
					parent := "."
					if i := strings.last_index_byte(string(p), '/'); i >= 0 do parent = string(p)[:i]
					if parent != path do append(&kept, rv)
				}
				ov[OVERRIDE_REMOVED] = kept
			}
			obj["overrides"] = ov
		}
	}
	w := Json_Writer{sb = strings.builder_make(context.temp_allocator)}
	Json_WriteValue(&w, obj)
	return Scene_RebuildInstance(scene, root, strings.to_string(w.sb), ctx)
}

@(private = "file")
runtime_heap :: proc() -> runtime.Allocator {
	return Engine_HeapAllocator()
}

// Component_ClearCaches frees the per-type default cache (engine shutdown / tests).
Component_ClearCaches :: proc() {
	for k, v in typeDefaults {
		delete(k, Engine_HeapAllocator())
		delete(v, Engine_HeapAllocator())
	}
	delete(typeDefaults)
	typeDefaults = nil
}

// Component_InstanceJSON: an instance's whole subtree as a component file
// (its link and overrides baked in).
Component_InstanceJSON :: proc(node: ^Node, manager: ^NodeManager, allocator := context.allocator) -> string {
	prev := serializeFullInstance
	serializeFullInstance = node
	defer serializeFullInstance = prev
	return Node_SerializeToJSON(node, manager, allocator)
}
