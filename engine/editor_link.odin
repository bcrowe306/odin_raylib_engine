package engine

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import lua "vendor:lua/5.4"
import "core:time"
import rl "vendor:raylib"

// ============================================================================
// Editor link (--editor-link): the editor that launched the game drives it
// through stdin, one command per line; answers are stdout lines starting
// with "@ore:" (the editor reads them, its console hides them).
//
//   pause / resume              freeze the game (it is still drawn) / go on
//   step [n]                    while paused: run n frames of 1/60 s
//   tree                        -> @ore:tree {"frame", "frozen", "scene", "root"}
//   inspect <path>              -> @ore:node {"path", "props": [[name, value], ...]}
//   set <path> <prop> <value>   change a property ("position" "10,20", "rotation", any reflected one)
//   reload-scene <file>         re-read a scene file; restart it when it's the current scene
//   break-set <file> <l,l,...>  breakpoints in a script (break-clear: none); a hit
//                               pauses the game in the script (lua_debugger.odin):
//                               -> @ore:stopped {...}, then continue / step-* / locals
//
// Paths are node names from the scene root, '/'-separated ("Player/Gun").
// Scripts and textures reload by themselves when their files change.
// ============================================================================

Editor_Link :: struct {
	enabled: bool,
	steps:   int, // frames to run while paused
	frame:   int, // frames run (not counting frozen ones)
	inBuf:   [dynamic]u8,
}

editorLink: Editor_Link

EditorLink_Enable :: proc(game: ^Game) {
	editorLink.enabled = true
	// Breakpoints: the debugger waits for commands on stdin while stopped.
	LuaDebugger_Attach(game.scriptManager.L, link_wait_command, proc(kind, json: string) {fmt.printfln("@ore:%s %s", kind, json)})
	luaDebugger.projectDir = game.assetManager.projectDir
	fmt.println("@ore:hello")
}

// link_wait_command blocks until the editor sends a line (the game is
// paused in a script); window events keep being handled meanwhile.
@(private = "file")
link_wait_command :: proc() -> string {
	for {
		for b, i in editorLink.inBuf {
			if b != '\n' do continue
			line := strings.clone(strings.trim_space(string(editorLink.inBuf[:i])), context.temp_allocator)
			remove_range(&editorLink.inBuf, 0, i + 1)
			if line != "" do return line
			break
		}
		has, err := os.pipe_has_data(os.stdin)
		if err != nil do return ""
		if has {
			chunk: [1024]u8
			n, rerr := os.read(os.stdin, chunk[:])
			if n <= 0 || rerr != nil do return "" // the editor went away
			append(&editorLink.inBuf, ..chunk[:n])
			continue
		}
		if rl.IsWindowReady() do rl.PollInputEvents()
		if rl.IsWindowReady() && rl.WindowShouldClose() do return ""
		time.sleep(10 * time.Millisecond)
	}
}

// EditorLink_BeginFrame reads pending commands and decides whether this
// frame runs (game.frozen = false) or only draws.
EditorLink_BeginFrame :: proc(game: ^Game) {
	if !editorLink.enabled do return
	for {
		has, err := os.pipe_has_data(os.stdin)
		if err != nil || !has do break
		chunk: [1024]u8
		n, rerr := os.read(os.stdin, chunk[:])
		if n <= 0 || rerr != nil {
			editorLink.enabled = false // the editor went away
			break
		}
		append(&editorLink.inBuf, ..chunk[:n])
	}
	for {
		idx := -1
		for b, i in editorLink.inBuf do if b == '\n' {idx = i; break}
		if idx < 0 do break
		line := strings.clone(strings.trim_space(string(editorLink.inBuf[:idx])), context.temp_allocator)
		remove_range(&editorLink.inBuf, 0, idx + 1)
		if line != "" do EditorLink_Command(game, line)
	}
	if game.linkPaused {
		game.frozen = editorLink.steps <= 0
		if editorLink.steps > 0 do editorLink.steps -= 1
	} else {
		game.frozen = false
	}
	if !game.frozen do editorLink.frame += 1
}

// EditorLink_Command runs one command (also used by tests).
EditorLink_Command :: proc(game: ^Game, line: string) {
	cmd, rest := line, ""
	if i := strings.index_byte(line, ' '); i >= 0 do cmd, rest = line[:i], strings.trim_space(line[i + 1:])
	switch cmd {
	case "pause":
		game.linkPaused = true
		fmt.println("@ore:paused")
	case "resume":
		game.linkPaused = false
		editorLink.steps = 0
		fmt.println("@ore:resumed")
	case "step":
		n := 1
		if v, ok := strconv.parse_int(rest); ok do n = max(v, 1)
		game.linkPaused = true
		editorLink.steps += n
		fmt.printfln("@ore:stepped %d", n)
	case "tree":
		fmt.printfln("@ore:tree %s", EditorLink_TreeJSON(game))
	case "inspect":
		fmt.printfln("@ore:node %s", EditorLink_NodeJSON(game, rest))
	case "set":
		parts := strings.fields(rest, context.temp_allocator)
		if len(parts) >= 3 {
			value := strings.join(parts[2:], " ", context.temp_allocator)
			ok := EditorLink_Set(game, parts[0], parts[1], value)
			fmt.printfln("@ore:set %s %s %t", parts[0], parts[1], ok)
		}
	case "break-set":
		LuaDebugger_Command(rest)
	case "break-clear":
		LuaDebugger_ClearBreakpoints()
	case "reload-scene":
		fmt.printfln("@ore:reloaded %s %t", rest, Game_ReloadSceneFile(game, rest))
	case "debug-draw":
		// Colliders, joints and areas drawn (the toolbar's Show Colliders).
		game.physicsWorld.drawPhysicsDebug = rest == "true"
		fmt.printfln("@ore:debug-draw %t", game.physicsWorld.drawPhysicsDebug)
	}
}

// Game_ReloadSceneFile re-reads a registered scene's file; the current
// scene restarts with it.
Game_ReloadSceneFile :: proc(game: ^Game, rel: string) -> bool {
	scene := Game_FindSceneByFile(game, rel)
	if scene == nil do return false
	bytes, ok := AssetManager_ReadFileBytes(&game.assetManager, rel, context.temp_allocator)
	if !ok do return false
	allocator := game.sceneManager.allocator if game.sceneManager.allocator.procedure != nil else context.allocator
	scene.sourceJson = strings.clone(string(bytes), allocator)
	if scene == game.sceneManager.currentScene do ChangeScene_ByName(&game.sceneManager, scene.name)
	return true
}

// link_find: a node by its name path from the current scene's root.
@(private = "file")
link_find :: proc(game: ^Game, path: string) -> ^Node {
	scene := game.sceneManager.currentScene
	if scene == nil || scene.rootNode == nil do return nil
	n := scene.rootNode
	if path == "" || path == "/" do return n
	for part in strings.split(path, "/", context.temp_allocator) {
		next: ^Node
		for c in GetChildrenView(scene.manager, n) do if c != nil && c.name == part {next = c; break}
		if next == nil do return nil
		n = next
	}
	return n
}

EditorLink_TreeJSON :: proc(game: ^Game) -> string {
	sb := strings.builder_make(context.temp_allocator)
	scene := game.sceneManager.currentScene
	fmt.sbprintf(&sb, "{{\"frame\": %d, \"frozen\": %t, \"paused\": %t, \"scene\": ", editorLink.frame, game.frozen, game.linkPaused)
	link_str(&sb, scene.filePath if scene != nil else "")
	strings.write_string(&sb, ", \"root\": ")
	walk :: proc(sb: ^strings.Builder, m: ^NodeManager, n: ^Node) {
		strings.write_string(sb, "{\"name\": ")
		link_str(sb, n.name)
		strings.write_string(sb, ", \"type\": ")
		link_str(sb, Node_TypeName(n))
		fmt.sbprintf(sb, ", \"enabled\": %t, \"visible\": %t", n.enabled, n.renderable)
		kids := GetChildrenView(m, n)
		if len(kids) > 0 {
			strings.write_string(sb, ", \"children\": [")
			k := 0
			for c in kids {
				if c == nil do continue
				if k > 0 do strings.write_string(sb, ", ")
				walk(sb, m, c)
				k += 1
			}
			strings.write_byte(sb, ']')
		}
		strings.write_byte(sb, '}')
	}
	if scene != nil && scene.rootNode != nil do walk(&sb, scene.manager, scene.rootNode)
	else do strings.write_string(&sb, "null")
	strings.write_byte(&sb, '}')
	return strings.to_string(sb)
}

EditorLink_NodeJSON :: proc(game: ^Game, path: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "{\"path\": ")
	link_str(&sb, path)
	n := link_find(game, path)
	if n == nil {
		strings.write_string(&sb, ", \"missing\": true}")
		return strings.to_string(sb)
	}
	strings.write_string(&sb, ", \"type\": ")
	link_str(&sb, Node_TypeName(n))
	strings.write_string(&sb, ", \"props\": [")
	prop :: proc(sb: ^strings.Builder, first: ^bool, name, value: string) {
		if !first^ do strings.write_string(sb, ", ")
		first^ = false
		strings.write_byte(sb, '[')
		link_str(sb, name)
		strings.write_string(sb, ", ")
		link_str(sb, value)
		strings.write_byte(sb, ']')
	}
	first := true
	prop(&sb, &first, "position", fmt.tprintf("%.2f,%.2f", n.position.x, n.position.y))
	prop(&sb, &first, "global", fmt.tprintf("%.2f,%.2f", n.globalPosition.x, n.globalPosition.y))
	prop(&sb, &first, "rotation", fmt.tprintf("%.2f", n.rotation))
	prop(&sb, &first, "scale", fmt.tprintf("%.3f,%.3f", n.scale.x, n.scale.y))
	prop(&sb, &first, "enabled", fmt.tprintf("%t", n.enabled))
	prop(&sb, &first, "visible", fmt.tprintf("%t", n.renderable))
	for p in Node_CollectProperties(n) do prop(&sb, &first, p.name, Property_ToString(p))
	// Its script's exported properties ("script.<name>"), live from self.
	if inst := cast(^ScriptInstance)n.scriptInstance; inst != nil && game.scriptManager.L != nil {
		if mod, ok := game.scriptManager.modules[ScriptVFS_NormalizePath(inst.modulePath)]; ok && mod != nil {
			L := game.scriptManager.L
			for p in mod.properties {
				lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef))
				lua.getfield(L, -1, strings.clone_to_cstring(p.name, context.temp_allocator))
				text: string
				#partial switch lua.type(L, -1) {
				case .NUMBER:   text = fmt.tprintf("%v", f64(lua.tonumber(L, -1)))
				case .BOOLEAN:  text = "true" if lua.toboolean(L, -1) else "false"
				case .STRING:   text = strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
				case .TABLE:
					if p.type == .Color || p.type == .Vector2 {
						// "r,g,b,a" / "x,y" (as the Game tab edits them)
						parts := make([dynamic]string, context.temp_allocator)
						for i in 1 ..= int(lua.rawlen(L, -1)) {
							lua.rawgeti(L, -1, lua.Integer(i))
							append(&parts, fmt.tprintf("%v", f64(lua.tonumber(L, -1))))
							lua.pop(L, 1)
						}
						text = strings.join(parts[:], ",", context.temp_allocator)
					} else {
						text = lua_to_json(L, -1)
					}
				case .USERDATA:
					if target, isNode := to_node_userdata(L, -1); isNode && target != nil do text = target.name
				case: text = ""
				}
				lua.pop(L, 2)
				prop(&sb, &first, fmt.tprintf("script.%s", p.name), text)
			}
		}
	}
	strings.write_string(&sb, "]}")
	return strings.to_string(sb)
}

// link_set_script sets an exported script property from text, by its
// declared type: numbers, true / false, "x,y" / "r,g,b,a", JSON lists,
// strings (and enums, asset paths, node paths) as they are.
@(private = "file")
link_set_script :: proc(game: ^Game, n: ^Node, field, value: string) -> bool {
	inst := cast(^ScriptInstance)n.scriptInstance
	if inst == nil do return false
	mod, ok := game.scriptManager.modules[ScriptVFS_NormalizePath(inst.modulePath)]
	if !ok || mod == nil do return false
	for p in mod.properties {
		if p.name != field do continue
		v := ScriptValue{type = p.type}
		parts := strings.split(value, ",", context.temp_allocator)
		switch p.type {
		case .Float:
			f, fok := strconv.parse_f32(strings.trim_space(value))
			if !fok do return false
			v.valFloat = f
		case .Int:
			i, iok := strconv.parse_i64(strings.trim_space(value))
			if !iok do return false
			v.valInt = i
		case .Boolean:
			v.valBool = strings.trim_space(value) == "true"
		case .String:
			v.valString = strings.clone(value, context.temp_allocator)
		case .Vector2:
			if len(parts) != 2 do return false
			for i in 0 ..< 2 do v.valVec2[i], _ = strconv.parse_f32(strings.trim_space(parts[i]))
		case .Color:
			if len(parts) < 3 do return false
			v.valColor = {1, 1, 1, 1}
			for i in 0 ..< min(len(parts), 4) do v.valColor[i], _ = strconv.parse_f32(strings.trim_space(parts[i]))
		}
		return ScriptInstance_SetProperty(inst, field, v, &game.scriptManager)
	}
	return false
}

// EditorLink_Set changes a node's transform or reflected property from text.
EditorLink_Set :: proc(game: ^Game, path, name, value: string) -> bool {
	n := link_find(game, path)
	if n == nil do return false
	vec :: proc(s: string) -> ([2]f32, bool) {
		parts := strings.split(s, ",", context.temp_allocator)
		if len(parts) != 2 do return {}, false
		x, ok1 := strconv.parse_f32(strings.trim_space(parts[0]))
		y, ok2 := strconv.parse_f32(strings.trim_space(parts[1]))
		return {x, y}, ok1 && ok2
	}
	switch name {
	case "position":
		v, ok := vec(value)
		if ok do n.position = v
		return ok
	case "scale":
		v, ok := vec(value)
		if ok do n.scale = v
		return ok
	case "rotation":
		v, ok := strconv.parse_f32(value)
		if ok do n.rotation = v
		return ok
	case "enabled": n.enabled = value == "true"; return true
	case "visible": n.renderable = value == "true"; return true
	}
	if strings.has_prefix(name, "script.") do return link_set_script(game, n, name[len("script."):], value)
	p, found := Node_FindProperty(n, name)
	if !found do return false
	return Property_FromString(n, p, value)
}

// Property_ToString / Property_FromString: a property's value as text
// ("1.5", "true", "10,20", "#ff8800ff", enum names, bit-set names joined
// with '|').
Property_ToString :: proc(p: Node_Property) -> string {
	switch p.kind {
	case .Float: return fmt.tprintf("%v", Property_GetFloat(p))
	case .Int: return fmt.tprintf("%v", Property_GetInt(p))
	case .Bool: return "true" if (^bool)(p.ptr)^ else "false"
	case .Vec2:
		v := (^[2]f32)(p.ptr)^
		return fmt.tprintf("%v,%v", v.x, v.y)
	case .Color:
		c := (^rl.Color)(p.ptr)^
		return fmt.tprintf("#%02x%02x%02x%02x", c.r, c.g, c.b, c.a)
	case .String: return (^string)(p.ptr)^
	case .Enum:
		names := Property_EnumNames(p)
		i := Property_GetEnumIndex(p)
		return names[i] if i >= 0 && i < len(names) else ""
	case .Bit_Set:
		on := make([dynamic]string, context.temp_allocator)
		for nm, i in Property_EnumNames(p) do if Property_BitSetHas(p, i) do append(&on, nm)
		return strings.join(on[:], "|", context.temp_allocator)
	}
	return ""
}

Property_FromString :: proc(node: ^Node, p: Node_Property, value: string) -> bool {
	value := strings.trim_space(value)
	switch p.kind {
	case .Float:
		v, ok := strconv.parse_f32(value)
		if ok do Property_SetFloat(p, v)
		return ok
	case .Int:
		v, ok := strconv.parse_i64(value)
		if ok do Property_SetInt(p, v)
		return ok
	case .Bool:
		(^bool)(p.ptr)^ = value == "true" || value == "1"
		return true
	case .Vec2:
		parts := strings.split(value, ",", context.temp_allocator)
		if len(parts) != 2 do return false
		x, ok1 := strconv.parse_f32(strings.trim_space(parts[0]))
		y, ok2 := strconv.parse_f32(strings.trim_space(parts[1]))
		if ok1 && ok2 do (^[2]f32)(p.ptr)^ = {x, y}
		return ok1 && ok2
	case .Color:
		hex := strings.trim_prefix(value, "#")
		if len(hex) != 6 && len(hex) != 8 do return false
		v, ok := strconv.parse_u64(hex, 16)
		if !ok do return false
		if len(hex) == 6 do v = v << 8 | 0xff
		(^rl.Color)(p.ptr)^ = {u8(v >> 24), u8(v >> 16), u8(v >> 8), u8(v)}
		return true
	case .String:
		Property_SetString(node, p, value)
		return true
	case .Enum:
		for nm, i in Property_EnumNames(p) do if nm == value {Property_SetEnumIndex(p, i); return true}
		return false
	case .Bit_Set:
		names := Property_EnumNames(p)
		want := strings.split(value, "|", context.temp_allocator)
		for nm, i in names {
			on := false
			for w in want do if strings.trim_space(w) == nm do on = true
			Property_BitSetSet(p, i, on)
		}
		return true
	}
	return false
}

@(private = "file")
link_str :: proc(sb: ^strings.Builder, s: string) {
	strings.write_byte(sb, '"')
	for r in s {
		switch r {
		case '"': strings.write_string(sb, `\"`)
		case '\\': strings.write_string(sb, `\\`)
		case '\n': strings.write_string(sb, `\n`)
		case: strings.write_rune(sb, r)
		}
	}
	strings.write_byte(sb, '"')
}
