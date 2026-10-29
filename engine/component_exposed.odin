package engine

import "core:encoding/json"
import "core:slice"
import "core:strings"

// --- exposed properties (#85) -------------------------------------------------------
// A component's root lists the few properties of its nodes that matter on
// an instance (speed, colour, team):
//
//   "exposed": [{"uid": "m0v00000", "property": "speed", "label": "Speed"}]
//
// - "uid": the node's uid in the file ("." = the root); into a nested
//   instance, a path of uids ("t0p00000/l1d00000").
// - "property": an Inspector row path - a node key ("position", "rotation",
//   "scale", "origin"), a reflected property ("emitter.amount") or
//   "script.<name>".
// - "label": shown on the instance ("" = the property's name).
//
// The list is read into the root node's componentExposed (in the component
// document and on every instance, from the file) and written back with the
// node, so it round-trips through the document, Apply and Save as
// Component. On an instance, it compares equal to its base: never an
// override. Editing an exposed value on an instance edits that node: an
// ordinary override.

Component_Exposed :: struct {
	uid:      string,
	property: string,
	label:    string,
}

read_exposed :: proc(node: ^Node, obj: json.Object) {
	arr, ok := obj["exposed"].(json.Array)
	if !ok || len(arr) == 0 do return
	list := make([dynamic]Component_Exposed, 0, len(arr), node.allocator)
	for v in arr {
		o, isObj := v.(json.Object)
		if !isObj do continue
		uid, _ := o["uid"].(json.String)
		prop, _ := o["property"].(json.String)
		label, _ := o["label"].(json.String)
		if prop == "" do continue
		append(&list, Component_Exposed{
			uid      = strings.clone(string(uid) if uid != "" else ".", node.allocator),
			property = strings.clone(string(prop), node.allocator),
			label    = strings.clone(string(label), node.allocator),
		})
	}
	node.componentExposed = list[:]
}

write_exposed :: proc(w: ^Json_Writer, node: ^Node, first: ^bool) {
	Json_Key(w, "exposed", first)
	strings.write_byte(&w.sb, '[')
	for x, i in node.componentExposed {
		if i > 0 do strings.write_string(&w.sb, ", ")
		strings.write_string(&w.sb, `{"uid": `)
		Json_String(w, x.uid)
		strings.write_string(&w.sb, `, "property": `)
		Json_String(w, x.property)
		strings.write_string(&w.sb, `, "label": `)
		Json_String(w, x.label)
		strings.write_byte(&w.sb, '}')
	}
	strings.write_byte(&w.sb, ']')
}

// Node_FindByUidPath: the node at a uid path below `root` ("." = root).
Node_FindByUidPath :: proc(manager: ^NodeManager, root: ^Node, path: string) -> ^Node {
	if root == nil do return nil
	if path == "." || path == "" do return root
	n := root
	for seg in strings.split(path, "/", context.temp_allocator) {
		next: ^Node
		for c in GetChildrenView(manager, n) do if c.uid == seg {next = c; break}
		if next == nil do return nil
		n = next
	}
	return n
}

// Node_UidPathBelow: the uid path of `node` below its ancestor `root` ("."
// for the root itself; "" when a node on the way has no uid and `assign` is
// false - with it, those get one now, kept when the file is written).
Node_UidPathBelow :: proc(manager: ^NodeManager, node, root: ^Node, assign := false) -> string {
	if node == root do return "."
	parts := make([dynamic]string, context.temp_allocator)
	n := node
	for ; n != nil && n != root; n = GetParent(manager, n) {
		if n.uid == "" {
			if !assign do return ""
			n.uid = Component_NewUid(n.allocator)
		}
		inject_at(&parts, 0, n.uid)
	}
	if n != root do return ""
	return strings.join(parts[:], "/", context.temp_allocator)
}

// Component_ExposedIndex: the entry exposing a node's property on `root`
// (-1: not exposed).
Component_ExposedIndex :: proc(root: ^Node, uidPath, property: string) -> int {
	if root == nil do return -1
	for x, i in root.componentExposed do if x.uid == uidPath && x.property == property do return i
	return -1
}

// Component_Expose adds an entry to a component root's list (no-op when
// it's there already).
Component_Expose :: proc(root: ^Node, uidPath, property, label: string) {
	if root == nil || Component_ExposedIndex(root, uidPath, property) >= 0 do return
	list := make([]Component_Exposed, len(root.componentExposed) + 1, root.allocator)
	copy(list, root.componentExposed)
	list[len(list) - 1] = {strings.clone(uidPath, root.allocator), strings.clone(property, root.allocator), strings.clone(label, root.allocator)}
	root.componentExposed = list
}

// Component_Unexpose removes an entry from a component root's list.
Component_Unexpose :: proc(root: ^Node, index: int) {
	if root == nil || index < 0 || index >= len(root.componentExposed) do return
	list := slice.clone(root.componentExposed, root.allocator)
	copy(list[index:], list[index + 1:])
	root.componentExposed = list[:len(list) - 1]
}
