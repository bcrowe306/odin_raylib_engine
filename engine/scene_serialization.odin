package engine


import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:math"
import "core:os"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

// ============================================================================
// Scene JSON: saving and loading
//
// Saving and loading are symmetric: everything Scene_SerializeToJSON writes,
// Scene_InstantiateFromJSON reads back, so a load -> save -> load round trip
// keeps every node, property, resource, script value and the hierarchy.
//
// Scene object: "name", "draw_bounds", "background", "ambient", "guides"
// (editor guide lines: [{"x": 100}, {"y": 50}]), "root".
//
// Node object:
//   "type", "name", "position", "scale", "rotation", "pivot" (the origin, nodes
//   that draw a rectangle), "enabled", "visible", "layer"
//   optional: "pause_mode", "paused", "tags", "editor_locked", "editor_hidden" (editor only)
//   "properties": { <reflected gui:"true" fields> }        (see node_properties.odin)
//   resources by type: "texture"/"origin" (TextureNode), "frames"/"fps"/"loop"/"origin"
//   (FrameAnimationNode), "audio" (Sound/Music), "timer" {duration, auto_start, loop},
//   "shapes" [...] (physics bodies), "ldtk" {project, level}
//   "script": { "path", "properties": {...} }
//   "children": [ ... ]
// Older files (blocks "physics", "particles", "character", "area", "raycast",
// "camera", "texture_path") still load.
// ============================================================================

// --- saving --------------------------------------------------------------------

Scene_SerializeToJSON :: proc(scene: ^Scene, allocator := context.allocator) -> string {
	if scene == nil do return strings.clone("{}", allocator)
	w := Json_Writer{sb = strings.builder_make(allocator)}
	strings.write_byte(&w.sb, '{')
	w.indent = 1
	first := true
	Json_Key(&w, "name", &first)
	Json_String(&w, scene.name)
	Json_Key(&w, "draw_bounds", &first)
	strings.write_string(&w.sb, "true" if scene.drawBounds else "false")
	if scene.backgroundColor.a > 0 {
		c := scene.backgroundColor
		Json_Key(&w, "background", &first)
		fmt.sbprintf(&w.sb, "[%d, %d, %d, %d]", c.r, c.g, c.b, c.a)
	}
	if scene.ambient != {} && scene.ambient != {255, 255, 255, 255} {
		c := scene.ambient
		Json_Key(&w, "ambient", &first)
		fmt.sbprintf(&w.sb, "[%d, %d, %d, %d]", c.r, c.g, c.b, c.a)
	}
	if scene.guideCount > 0 {
		// Editor guides: {"x": 100} is a vertical line, {"y": 50} a horizontal one.
		Json_Key(&w, "guides", &first)
		strings.write_byte(&w.sb, '[')
		for g, i in scene.guides[:scene.guideCount] {
			if i > 0 do strings.write_string(&w.sb, ", ")
			fmt.sbprintf(&w.sb, "{{\"%s\": ", "x" if g.vertical else "y")
			Json_Float(&w, g.pos)
			strings.write_byte(&w.sb, '}')
		}
		strings.write_byte(&w.sb, ']')
	}
	Json_Key(&w, "root", &first)
	if scene.rootNode != nil {
		write_node(&w, scene.rootNode, scene.manager)
	} else {
		strings.write_string(&w.sb, "{}")
	}
	w.indent = 0
	Json_NewLine(&w)
	strings.write_string(&w.sb, "}\n")
	return strings.to_string(w.sb)
}

// Node_SerializeToJSON writes one node and its subtree as a standalone node
// object (used for components/prefabs, duplicate and copy/paste).
Node_SerializeToJSON :: proc(node: ^Node, manager: ^NodeManager, allocator := context.allocator) -> string {
	w := Json_Writer{sb = strings.builder_make(allocator)}
	write_node(&w, node, manager)
	strings.write_byte(&w.sb, '\n')
	return strings.to_string(w.sb)
}

@(private = "file")
write_bool :: proc(w: ^Json_Writer, b: bool) {
	strings.write_string(&w.sb, "true" if b else "false")
}

// asset_rel makes a resolved disk path relative to the project directory so
// saved scenes stay portable (and work from a .ore package).
@(private = "file")
asset_rel :: proc(node: ^Node, path: string) -> string {
	p := strings.trim_prefix(path, "./")
	if node != nil && node.gameContext != nil && node.gameContext.game != nil {
		dir := strings.trim_suffix(node.gameContext.game.assetManager.projectDir, "/")
		if dir != "" && strings.has_prefix(p, dir) && len(p) > len(dir) && p[len(dir)] == '/' {
			return p[len(dir) + 1:]
		}
	}
	return p
}

@(private = "file")
node_shapes :: proc(node: ^Node) -> ^[dynamic]PhysicsShape {
	switch node.typeId {
	case StaticBodyNode: return &(cast(^StaticBodyNode)node).shapes
	case DynamicBodyNode: return &(cast(^DynamicBodyNode)node).shapes
	case CharacterMoverNode: return &(cast(^CharacterMoverNode)node).shapes
	case AreaNode: return &(cast(^AreaNode)node).shapes
	}
	return nil
}

@(private = "file")
write_props :: proc(w: ^Json_Writer, props: []Node_Property) -> bool {
	strings.write_byte(&w.sb, '{')
	w.indent += 1
	first := true
	for p in props {
		if p.runtime do continue
		Json_Key(w, p.name, &first)
		Property_WriteJSON(w, p)
	}
	w.indent -= 1
	if !first do Json_NewLine(w)
	strings.write_byte(&w.sb, '}')
	return !first
}

@(private = "file")
write_node :: proc(w: ^Json_Writer, node: ^Node, manager: ^NodeManager) {
	if node == nil {
		strings.write_string(&w.sb, "null")
		return
	}
	strings.write_byte(&w.sb, '{')
	w.indent += 1
	first := true

	Json_Key(w, "type", &first); Json_String(w, Node_TypeName(node))
	Json_Key(w, "name", &first); Json_String(w, node.name)
	Json_Key(w, "position", &first); Json_Vec2(w, node.position)
	Json_Key(w, "scale", &first); Json_Vec2(w, node.scale)
	Json_Key(w, "rotation", &first); Json_Float(w, node.rotation)
	if Node_HasOrigin(node) {Json_Key(w, "pivot", &first); Json_Vec2(w, node.pivot)} // the origin (node_origin.odin)
	Json_Key(w, "enabled", &first); write_bool(w, node.enabled)
	Json_Key(w, "visible", &first); write_bool(w, node.renderable)
	Json_Key(w, "layer", &first); fmt.sbprintf(&w.sb, "%d", int(node.layer))
	if node.pauseMode != .Inherit {Json_Key(w, "pause_mode", &first); Json_String(w, Pause_ModeName(node.pauseMode))}
	if node.paused {Json_Key(w, "paused", &first); write_bool(w, true)}
	if node.editorLocked {Json_Key(w, "editor_locked", &first); write_bool(w, true)}
	if node.editorHidden {Json_Key(w, "editor_hidden", &first); write_bool(w, true)}
	if len(node.tags) > 0 {
		Json_Key(w, "tags", &first)
		strings.write_byte(&w.sb, '[')
		for t, i in node.tags {
			if i > 0 do strings.write_string(&w.sb, ", ")
			Json_String(w, t)
		}
		strings.write_byte(&w.sb, ']')
	}

	// A linked component instance saves only its link: everything below the
	// instance root comes from the component file.
	if node.componentPath != "" && node != serializeFullInstance {
		Json_Key(w, "component", &first); Json_String(w, node.componentPath)
		if ov := Component_OverridesJSON(node, manager); ov != "" {
			Json_Key(w, "overrides", &first); strings.write_string(&w.sb, ov)
		}
		write_connections(w, node, &first)
		w.indent -= 1
		Json_NewLine(w)
		strings.write_byte(&w.sb, '}')
		return
	}

	// Type-specific resources.
	switch node.typeId {
	case TextureNode:
		tn := cast(^TextureNode)node
		if tn.filePath != "" {
			Json_Key(w, "texture", &first); Json_String(w, asset_rel(node, tn.filePath))
		}
		if tn.origin != {0, 0} {
			Json_Key(w, "origin", &first); Json_Vec2(w, tn.origin)
		}
	case FrameAnimationNode:
		fan := cast(^FrameAnimationNode)node
		Json_Key(w, "fps", &first); Json_Float(w, fan.ticker.framesPerSecond)
		Json_Key(w, "loop", &first); write_bool(w, fan.loop)
		Json_Key(w, "frames", &first)
		strings.write_byte(&w.sb, '[')
		n := 0
		for f in fan.frames {
			if f == nil do continue
			if n > 0 do strings.write_string(&w.sb, ", ")
			Json_String(w, asset_rel(node, f.filePath))
			n += 1
		}
		strings.write_byte(&w.sb, ']')
	case SoundNode:
		sn := cast(^SoundNode)node
		if sn.audio != nil && sn.audio.filePath != "" {
			Json_Key(w, "audio", &first); Json_String(w, asset_rel(node, sn.audio.filePath))
		}
	case MusicNode:
		mn := cast(^MusicNode)node
		if mn.music != nil && mn.music.filePath != "" {
			Json_Key(w, "audio", &first); Json_String(w, asset_rel(node, mn.music.filePath))
		}
	case LineNode:
		ln := cast(^LineNode)node
		Json_Key(w, "points", &first)
		strings.write_byte(&w.sb, '[')
		for p, i in ln.points {
			if i > 0 do strings.write_string(&w.sb, ", ")
			strings.write_byte(&w.sb, '[')
			Json_Float(w, p.x)
			strings.write_string(&w.sb, ", ")
			Json_Float(w, p.y)
			strings.write_byte(&w.sb, ']')
		}
		strings.write_byte(&w.sb, ']')
	case JointNode:
		jn := cast(^JointNode)node
		Json_Key(w, "joint", &first)
		strings.write_string(&w.sb, "{\"a\": ")
		Json_String(w, jn.bodyA)
		strings.write_string(&w.sb, ", \"b\": ")
		Json_String(w, jn.bodyB)
		strings.write_byte(&w.sb, '}')
	case StateMachineNode:
		Json_Key(w, "state_machine", &first)
		write_state_machine(w, cast(^StateMachineNode)node)
	case TimerNode:
		tm := cast(^TimerNode)node
		Json_Key(w, "timer", &first)
		fmt.sbprintf(&w.sb, "{{\"duration\": ")
		Json_Float(w, f32(time.duration_seconds(tm.duration)))
		fmt.sbprintf(&w.sb, ", \"auto_start\": %t, \"loop\": %t}}", tm.running, tm.loop)
	case AnimationPlayerNode:
		apn := cast(^AnimationPlayerNode)node
		Json_Key(w, "fps", &first); Json_Float(w, apn.fps)
		Json_Key(w, "animation", &first); Json_String(w, AnimationPlayerNode_GetAnimationName(apn))
		if apn.defaultAnimation != "" {Json_Key(w, "default_animation", &first); Json_String(w, apn.defaultAnimation)}
		Json_Key(w, "animations", &first)
		strings.write_byte(&w.sb, '[')
		w.indent += 1
		n := 0
		for a in apn.animations {
			if a == nil do continue
			if n > 0 do strings.write_byte(&w.sb, ',')
			n += 1
			Json_NewLine(w)
			fmt.sbprintf(&w.sb, "{{\"name\": ")
			Json_String(w, a.name)
			fmt.sbprintf(&w.sb, ", \"loop\": %t, \"flip_x\": %t, \"flip_y\": %t", a.loop, a.flipX, a.flipY)
			if a.reverse do strings.write_string(&w.sb, ", \"reverse\": true")
			if a.fps > 0 {strings.write_string(&w.sb, ", \"fps\": "); Json_Float(w, a.fps)}
			if a.renderFrame == SSA_RenderFrame {
				ssa := cast(^SpriteSheetAnimation)a
				strings.write_string(&w.sb, ", \"sheet\": ")
				Json_String(w, asset_rel(node, ssa.spriteSheet.filePath) if ssa.spriteSheet != nil else "")
				fmt.sbprintf(&w.sb, ", \"grid\": [%d, %d], \"start\": %d, \"end\": %d", ssa.grid.x, ssa.grid.y, ssa.startFrame, ssa.endFrame)
				if ssa.margin != {} do fmt.sbprintf(&w.sb, ", \"margin\": [%d, %d]", ssa.margin.x, ssa.margin.y)
				if ssa.spacing != {} do fmt.sbprintf(&w.sb, ", \"spacing\": [%d, %d]", ssa.spacing.x, ssa.spacing.y)
				if len(ssa.cells) > 0 {
					strings.write_string(&w.sb, ", \"cells\": [")
					for c, ci in ssa.cells {
						if ci > 0 do strings.write_string(&w.sb, ", ")
						fmt.sbprintf(&w.sb, "%d", c)
					}
					strings.write_byte(&w.sb, ']')
				}
			} else if a.renderFrame == FA_RenderFrame {
				fa := cast(^FrameAnimation)a
				// A range shorter than the frames.
				if fa.startFrame != 0 || fa.endFrame != len(fa.frames) - 1 do fmt.sbprintf(&w.sb, ", \"start\": %d, \"end\": %d", fa.startFrame, fa.endFrame)
				strings.write_string(&w.sb, ", \"frames\": [")
				for f, fi in fa.frames {
					if fi > 0 do strings.write_string(&w.sb, ", ")
					Json_String(w, asset_rel(node, f.filePath))
				}
				strings.write_byte(&w.sb, ']')
			}
			if len(a.tracks) > 0 {
				strings.write_string(&w.sb, ", \"tracks\": [")
				for tr, ti in a.tracks {
					if ti > 0 do strings.write_string(&w.sb, ", ")
					strings.write_string(&w.sb, "{\"target\": ")
					Json_String(w, tr.target)
					strings.write_string(&w.sb, ", \"property\": ")
					Json_String(w, tr.property)
					if tr.kind == .Method do strings.write_string(&w.sb, ", \"kind\": \"method\"")
					if tr.kind == .Audio do strings.write_string(&w.sb, ", \"kind\": \"audio\"")
					strings.write_string(&w.sb, ", \"keys\": [")
					for k, ki in tr.keys {
						if ki > 0 do strings.write_string(&w.sb, ", ")
						strings.write_byte(&w.sb, '[')
						Json_Float(w, k.frame)
						if tr.kind != .Property {
							// Event keys: [frame, "method or sound"]
							strings.write_string(&w.sb, ", ")
							Json_String(w, k.text)
							strings.write_byte(&w.sb, ']')
							continue
						}
						for v in k.value {
							strings.write_string(&w.sb, ", ")
							Json_Float(w, v)
						}
						if k.ease != .Linear do fmt.sbprintf(&w.sb, ", \"%s\"", Ease_Name(k.ease))
						strings.write_byte(&w.sb, ']')
					}
					strings.write_string(&w.sb, "]}")
				}
				strings.write_byte(&w.sb, ']')
			}
			strings.write_byte(&w.sb, '}')
		}
		w.indent -= 1
		if n > 0 do Json_NewLine(w)
		strings.write_byte(&w.sb, ']')
	case ParticleEmitterNode:
		pen := cast(^ParticleEmitterNode)node
		ramp := &pen.emitter.colorRamp
		Json_Key(w, "color_ramp", &first)
		strings.write_byte(&w.sb, '[')
		for i in 0 ..< ramp.count {
			st := ramp.stops[i]
			if i > 0 do strings.write_string(&w.sb, ", ")
			strings.write_byte(&w.sb, '[')
			Json_Float(w, st.position)
			fmt.sbprintf(&w.sb, ", %d, %d, %d, %d]", st.color.r, st.color.g, st.color.b, st.color.a)
		}
		strings.write_byte(&w.sb, ']')
	case TileMapNode:
		tm := cast(^TileMapNode)node
		Json_Key(w, "tilemap", &first)
		strings.write_string(&w.sb, "{\"tileset\": ")
		Json_String(w, asset_rel(node, tm.tilesetPath))
		fmt.sbprintf(&w.sb, ", \"tile_size\": [%d, %d], \"map_size\": [%d, %d]", tm.tileSize.x, tm.tileSize.y, tm.mapSize.x, tm.mapSize.y)
		strings.write_string(&w.sb, ", \"data\": ")
		TileMapNode_EncodeRLE(tm, &w.sb)
		strings.write_byte(&w.sb, '}')
	case CameraNode:
		if cam := cast(^CameraNode)node; cam.followTarget != "" {
			Json_Key(w, "follow", &first)
			Json_String(w, cam.followTarget)
		}
	case LdtkLevelNode:
		ln := cast(^LdtkLevelNode)node
		if ln.projectPath != "" {
			Json_Key(w, "ldtk", &first)
			strings.write_string(&w.sb, "{\"project\": ")
			Json_String(w, asset_rel(node, ln.projectPath))
			strings.write_string(&w.sb, ", \"level\": ")
			Json_String(w, ln.levelIdentifier)
			Ldtk_WriteNodeConfig(w, ln)
			strings.write_byte(&w.sb, '}')
		}
	}

	if shapes := node_shapes(node); shapes != nil && len(shapes) > 0 {
		Json_Key(w, "shapes", &first)
		strings.write_byte(&w.sb, '[')
		w.indent += 1
		for &shape, i in shapes {
			if i > 0 do strings.write_byte(&w.sb, ',')
			Json_NewLine(w)
			write_shape(w, &shape)
		}
		w.indent -= 1
		Json_NewLine(w)
		strings.write_byte(&w.sb, ']')
	}

	// Reflected properties.
	props := Node_CollectProperties(node)
	has_saved := false
	for p in props {
		if !p.runtime {has_saved = true; break}
	}
	if has_saved {
		Json_Key(w, "properties", &first)
		write_props(w, props)
	}

	// Script with its current property values.
	if node.scriptInstance != nil {
		inst := cast(^ScriptInstance)node.scriptInstance
		Json_Key(w, "script", &first)
		strings.write_byte(&w.sb, '{')
		w.indent += 1
		sfirst := true
		Json_Key(w, "path", &sfirst); Json_String(w, inst.modulePath)
		if len(inst.properties) > 0 {
			Json_Key(w, "properties", &sfirst)
			write_script_props(w, inst)
		}
		w.indent -= 1
		Json_NewLine(w)
		strings.write_byte(&w.sb, '}')
	}

	write_connections(w, node, &first)
	write_material(w, node, &first)

	if manager != nil {
		all := GetChildren(manager, node)
		defer delete(all)
		children := make([dynamic]^Node, context.temp_allocator)
		for c in all do if !c.transient do append(&children, c)
		if len(children) > 0 {
			Json_Key(w, "children", &first)
			strings.write_byte(&w.sb, '[')
			w.indent += 1
			for child, i in children {
				if i > 0 do strings.write_byte(&w.sb, ',')
				Json_NewLine(w)
				write_node(w, child, manager)
			}
			w.indent -= 1
			Json_NewLine(w)
			strings.write_byte(&w.sb, ']')
		}
	}

	w.indent -= 1
	Json_NewLine(w)
	strings.write_byte(&w.sb, '}')
}

// "material": {"shader": "...", "blend": "additive", "params": {"amount": 0.5,
// "flash_color": [1, 0, 0, 1], "noise": "textures/noise.png"}}
@(private = "file")
write_material :: proc(w: ^Json_Writer, node: ^Node, first: ^bool) {
	m := node.material
	if m == nil || (m.shader == "" && m.blend == .Alpha && len(m.params) == 0) do return
	Json_Key(w, "material", first)
	strings.write_string(&w.sb, "{\"shader\": ")
	Json_String(w, m.shader)
	fmt.sbprintf(&w.sb, ", \"blend\": \"%s\"", Material_BlendName(m.blend))
	if len(m.params) > 0 {
		strings.write_string(&w.sb, ", \"params\": {")
		for p, i in m.params {
			if i > 0 do strings.write_string(&w.sb, ", ")
			Json_String(w, p.name)
			strings.write_string(&w.sb, ": ")
			if p.texture != "" {
				Json_String(w, p.texture)
			} else {
				fmt.sbprintf(&w.sb, "[%g, %g, %g, %g]", p.value.x, p.value.y, p.value.z, p.value.w)
			}
		}
		strings.write_byte(&w.sb, '}')
	}
	strings.write_byte(&w.sb, '}')
}

@(private = "file")
read_material :: proc(node: ^Node, obj: json.Object) {
	mo, ok := sj_obj(obj, "material")
	if !ok do return
	m := Node_EnsureMaterial(node)
	m.shader = strings.clone(sj_string(mo, "shader", ""), node.allocator)
	m.blend = Material_BlendParse(sj_string(mo, "blend", "alpha"))
	clear(&m.params)
	if params, has := sj_obj(mo, "params"); has {
		for name, v in params {
			#partial switch x in v {
			case json.String:
				Material_SetParam(node, name, {}, string(x))
			case json.Array:
				val: [4]f32
				for el, i in x {
					if i >= 4 do break
					#partial switch n in el {
					case json.Float:   val[i] = f32(n)
					case json.Integer: val[i] = f32(n)
					}
				}
				Material_SetParam(node, name, val)
			case json.Float:
				Material_SetParam(node, name, {f32(x), 0, 0, 0})
			case json.Integer:
				Material_SetParam(node, name, {f32(x), 0, 0, 0})
			}
		}
	}
}

@(private = "file")
write_connections :: proc(w: ^Json_Writer, node: ^Node, first: ^bool) {
	saved := 0
	for c in node.signalConnections do if c.node == nil do saved += 1
	if saved == 0 do return
	Json_Key(w, "connections", first)
	strings.write_byte(&w.sb, '[')
	n := 0
	for c in node.signalConnections {
		if c.node != nil do continue // runtime-only direct connection
		if n > 0 do strings.write_string(&w.sb, ", ")
		n += 1
		strings.write_string(&w.sb, "{\"signal\": ")
		Json_String(w, c.signal)
		strings.write_string(&w.sb, ", \"target\": ")
		Json_String(w, c.target)
		strings.write_string(&w.sb, ", \"method\": ")
		Json_String(w, c.method)
		strings.write_byte(&w.sb, '}')
	}
	strings.write_byte(&w.sb, ']')
}

@(private = "file")
read_connections :: proc(node: ^Node, obj: json.Object) {
	arr, ok := sj_arr(obj, "connections")
	if !ok do return
	clear(&node.signalConnections)
	for v in arr {
		co, isObj := v.(json.Object)
		if !isObj do continue
		sig := sj_string(co, "signal", "")
		method := sj_string(co, "method", "")
		if sig == "" || method == "" do continue
		Node_AddConnection(node, sig, sj_string(co, "target", "."), method)
	}
}

@(private = "file")
write_shape :: proc(w: ^Json_Writer, shape: ^PhysicsShape) {
	strings.write_byte(&w.sb, '{')
	first := true
	for p in Struct_CollectProperties(PhysicsShape, shape) {
		if !first do strings.write_string(&w.sb, ", ")
		first = false
		Json_String(w, p.name)
		strings.write_string(&w.sb, ": ")
		Property_WriteJSON(w, p)
	}
	if shape.type == .Polygon && shape.vertexCount > 0 {
		strings.write_string(&w.sb, ", \"vertices\": [")
		for i in 0 ..< min(shape.vertexCount, len(shape.vertices)) {
			if i > 0 do strings.write_string(&w.sb, ", ")
			Json_Vec2(w, shape.vertices[i])
		}
		strings.write_byte(&w.sb, ']')
	}
	if len(shape.chainPoints) > 0 {
		strings.write_string(&w.sb, ", \"chain_points\": [")
		for pt, i in shape.chainPoints {
			if i > 0 do strings.write_string(&w.sb, ", ")
			Json_Vec2(w, pt)
		}
		strings.write_byte(&w.sb, ']')
	}
	strings.write_byte(&w.sb, '}')
}

@(private = "file")
write_script_props :: proc(w: ^Json_Writer, inst: ^ScriptInstance) {
	// Sorted keys keep saved files stable (map order is random).
	keys := make([dynamic]string, context.temp_allocator)
	for k in inst.properties do append(&keys, k)
	for i in 1 ..< len(keys) {
		for j := i; j > 0 && keys[j] < keys[j - 1]; j -= 1 {
			keys[j], keys[j - 1] = keys[j - 1], keys[j]
		}
	}
	strings.write_byte(&w.sb, '{')
	w.indent += 1
	first := true
	for k in keys {
		v := inst.properties[k]
		Json_Key(w, k, &first)
		switch v.type {
		case .Float: Json_Float(w, v.valFloat)
		case .Int: fmt.sbprintf(&w.sb, "%d", v.valInt)
		case .String:
			// Lists (array / curve / gradient) are saved as JSON, not as a string.
			mgr := inst.scriptManager if inst.scriptManager != nil else &scriptManager
			if Script_IsJsonKind(script_prop_kind(inst, k, mgr)) && v.valString != "" do strings.write_string(&w.sb, v.valString)
			else do Json_String(w, v.valString)
		case .Boolean: write_bool(w, v.valBool)
		case .Vector2: Json_Vec2(w, v.valVec2)
		case .Color:
			strings.write_byte(&w.sb, '[')
			for c, ci in v.valColor {
				if ci > 0 do strings.write_string(&w.sb, ", ")
				Json_Float(w, c)
			}
			strings.write_byte(&w.sb, ']')
		}
	}
	w.indent -= 1
	if !first do Json_NewLine(w)
	strings.write_byte(&w.sb, '}')
}

// --- loading -----------------------------------------------------------------------

// Scene_ReadJSONName returns the "name" stored in scene JSON ("" if none).
Scene_ReadJSONName :: proc(jsonBytes: []u8, allocator := context.temp_allocator) -> string {
	val, err := json.parse(jsonBytes, allocator = context.temp_allocator)
	if err != .None do return ""
	if obj, ok := val.(json.Object); ok {
		return strings.clone(sj_string(obj, "name", ""), allocator)
	}
	return ""
}

// Scene_InstantiateFromJSON adds the scene file's nodes under the scene root.
// The scene keeps its registered name (the file's "name" is only used when
// the scene has none).
Scene_InstantiateFromJSON :: proc(scene: ^Scene, jsonBytes: []u8, gameContext: ^GameContext = nil) -> bool {
	if scene == nil || len(jsonBytes) == 0 do return false

	parsedVal, err := json.parse(jsonBytes, allocator = context.temp_allocator)
	if err != .None {
		log.errorf("[SceneLoader] Failed to parse scene JSON: %v", err)
		return false
	}
	rootObj, isObj := parsedVal.(json.Object)
	if !isObj do return false

	if scene.name == "" {
		scene.name = strings.clone(sj_string(rootObj, "name", "Scene"))
	}
	scene.drawBounds = sj_bool(rootObj, "draw_bounds", false)
	scene.backgroundColor = {}
	if bg, ok := sj_arr(rootObj, "background"); ok && len(bg) == 4 {
		for v, i in bg {
			n: f64
			#partial switch x in v {
			case json.Integer: n = f64(x)
			case json.Float:   n = f64(x)
			}
			scene.backgroundColor[i] = u8(clamp(n, 0, 255))
		}
	}
	scene.ambient = {}
	if am, ok := sj_arr(rootObj, "ambient"); ok && len(am) == 4 {
		for v, i in am {
			n: f64
			#partial switch x in v {
			case json.Integer: n = f64(x)
			case json.Float:   n = f64(x)
			}
			scene.ambient[i] = u8(clamp(n, 0, 255))
		}
	}
	scene.guideCount = 0
	if gs, ok := sj_arr(rootObj, "guides"); ok {
		for v in gs {
			g, isObj := v.(json.Object)
			if !isObj || scene.guideCount >= SCENE_MAX_GUIDES do continue
			if "x" in g {
				scene.guides[scene.guideCount] = {true, sj_float(g, "x", 0)}
			} else if "y" in g {
				scene.guides[scene.guideCount] = {false, sj_float(g, "y", 0)}
			} else do continue
			scene.guideCount += 1
		}
	}
	if scene.rootNode != nil && gameContext != nil {
		scene.rootNode.gameContext = gameContext
	}

	if rootNodeObj, hasRoot := sj_obj(rootObj, "root"); hasRoot {
		if childrenArr, hasChildren := sj_arr(rootNodeObj, "children"); hasChildren {
			for childVal in childrenArr {
				if childObj, ok := childVal.(json.Object); ok {
					_ = read_node(scene, childObj, scene.rootNode, gameContext)
				}
			}
		}
	}

	// The scene's camera is its current CameraNode. Old files also carry a
	// scene-level "camera" block: honour it only if no camera node exists, so
	// a load/save cycle never adds another camera.
	if scene.camera == nil {
		scene.camera = find_current_camera(scene)
	}
	if camObj, hasCam := sj_obj(rootObj, "camera"); hasCam && scene.camera == nil {
		cam := CameraNode_Create(scene, "MainCamera", true)
		cam.gameContext = gameContext
		targetPos := sj_vec2(camObj, "target_position", {640.0, 360.0})
		CameraNode_SetTargetPosition(cam, targetPos)
		cam.currentPosition = targetPos
		CameraNode_SetZoom(cam, sj_float(camObj, "zoom", 1.0))
		scene.camera = cam
	}
	return true
}

@(private = "file")
find_current_camera :: proc(scene: ^Scene) -> ^CameraNode {
	first: ^CameraNode
	check :: proc(n: ^Node, first: ^^CameraNode) -> ^CameraNode {
		if n != nil && n.typeId == CameraNode {
			cam := cast(^CameraNode)n
			if first^ == nil do first^ = cam
			if cam.isCurrent do return cam
		}
		return nil
	}
	for n in scene.manager.addition {
		if c := check(n, &first); c != nil do return c
	}
	for n in scene.manager.nodes {
		if c := check(n, &first); c != nil do return c
	}
	return first
}

// Scene_InstantiateNodeFromJSON builds one node object (and its subtree)
// under `parent` (the root when nil). Accepts a bare node object or a
// component file whose node is under "root"/"node".
Scene_InstantiateNodeFromJSON :: proc(scene: ^Scene, jsonBytes: []u8, parent: ^Node = nil, gameContext: ^GameContext = nil) -> ^Node {
	if scene == nil || len(jsonBytes) == 0 do return nil
	parsedVal, err := json.parse(jsonBytes, allocator = context.temp_allocator)
	if err != .None {
		log.errorf("[SceneLoader] Failed to parse node JSON: %v", err)
		return nil
	}
	obj, isObj := parsedVal.(json.Object)
	if !isObj do return nil
	if inner, ok := sj_obj(obj, "node"); ok do obj = inner
	else if inner, ok := sj_obj(obj, "root"); ok && sj_string(obj, "type", "") == "" do obj = inner
	target := parent if parent != nil else scene.rootNode
	return read_node(scene, obj, target, gameContext)
}

@(private = "file")
resource_manager :: proc(ctx: ^GameContext) -> ^ResourceManager {
	if ctx != nil && ctx.game != nil do return &ctx.game.resourceManager
	return nil
}

@(private = "file")
load_texture_into :: proc(tn: ^TextureNode, path: string, ctx: ^GameContext) {
	tn.filePath = strings.clone(path, tn.allocator)
	rm := resource_manager(ctx)
	if rm == nil || !rl.IsWindowReady() do return
	tex, ok := rm.loadTexture(rm, Project_ResolveAssetPath(ctx, path))
	if ok && tex != nil {
		tn.texture = tex
		tn.size = {f32(tex.texture.width), f32(tex.texture.height)}
	}
}

@(private = "file")
componentDepth: int

@(private = "file")
read_node :: proc(scene: ^Scene, obj: json.Object, parent: ^Node, ctx: ^GameContext) -> ^Node {
	// Linked component instance: build the subtree from the component file,
	// then apply the instance's own name and transform.
	if compPath := sj_string(obj, "component", ""); compPath != "" {
		if inst := read_component_instance(scene, compPath, obj, parent, ctx); inst != nil do return inst
	}
	typeStr := sj_string(obj, "type", "Node")
	node := Node_CreateByTypeName(scene, typeStr, parent)
	if node == nil do return nil
	node.gameContext = ctx

	node.name = strings.clone(sj_string(obj, "name", typeStr), node.allocator)
	node.position = sj_vec2(obj, "position", {0, 0})
	node.scale = sj_vec2(obj, "scale", {1, 1})
	node.rotation = sj_float(obj, "rotation", 0)
	node.enabled = sj_bool(obj, "enabled", true)
	node.renderable = sj_bool(obj, "visible", node.renderable)
	node.layer = RenderLayer(math.clamp(sj_int(obj, "layer", int(node.layer)), 0, len(RenderLayer) - 1))
	node.pauseMode = Pause_ModeParse(sj_string(obj, "pause_mode", ""))
	node.paused = sj_bool(obj, "paused", false)
	node.editorLocked = sj_bool(obj, "editor_locked", false)
	node.editorHidden = sj_bool(obj, "editor_hidden", false)
	read_tags(node, obj)

	read_legacy_blocks(node, obj, ctx)

	// Reflected properties.
	if propsObj, ok := sj_obj(obj, "properties"); ok {
		props := Node_CollectProperties(node)
		for key, val in propsObj {
			for p in props {
				if p.name == key && !p.runtime {
					Property_ReadJSON(node, p, val)
					break
				}
			}
		}
	}

	// Type-specific resources.
	switch node.typeId {
	case TextureNode:
		tn := cast(^TextureNode)node
		if path := sj_texture_path(obj); path != "" do load_texture_into(tn, path, ctx)
	case FrameAnimationNode:
		fan := cast(^FrameAnimationNode)node
		fan.loop = sj_bool(obj, "loop", true)
		fan.ticker->setFPS(sj_float(obj, "fps", 12))
		if rm := resource_manager(ctx); rm != nil {
			if frames, ok := sj_arr(obj, "frames"); ok {
				for f in frames {
					if s, is_str := f.(json.String); is_str {
						FrameAnimationNode_AddFrame(fan, rm, Project_ResolveAssetPath(ctx, s))
					}
				}
			}
		}
		FrameAnimationNode_Start(fan)
	case SoundNode:
		sn := cast(^SoundNode)node
		if path := sj_string(obj, "audio", ""); path != "" {
			if rm := resource_manager(ctx); rm != nil && rl.IsAudioDeviceReady() {
				if snd, ok := rm.loadAudioSound(rm, Project_ResolveAssetPath(ctx, path)); ok do sn.audio = snd
			}
		}
	case MusicNode:
		mn := cast(^MusicNode)node
		if path := sj_string(obj, "audio", ""); path != "" {
			if rm := resource_manager(ctx); rm != nil && rl.IsAudioDeviceReady() {
				if mus, ok := rm.loadAudioMusic(rm, Project_ResolveAssetPath(ctx, path)); ok && mus != nil {
					mn.music = mus
					mus.music.looping = mn.looping
					mn.timeLength = rl.GetMusicTimeLength(mus.music)
				}
			}
		}
	case StateMachineNode:
		if smObj, ok := sj_obj(obj, "state_machine"); ok do read_state_machine(cast(^StateMachineNode)node, smObj)
	case JointNode:
		if jo, ok := sj_obj(obj, "joint"); ok do JointNode_SetBodies(cast(^JointNode)node, sj_string(jo, "a", ""), sj_string(jo, "b", ""))
	case LineNode:
		ln := cast(^LineNode)node
		if pts, ok := sj_arr(obj, "points"); ok {
			clear(&ln.points)
			for v in pts {
				if pa, pok := v.(json.Array); pok && len(pa) >= 2 {
					x, _ := json_number(pa[0])
					y, _ := json_number(pa[1])
					append(&ln.points, [2]f32{x, y})
				}
			}
		}
	case TimerNode:
		tm := cast(^TimerNode)node
		if timerObj, ok := sj_obj(obj, "timer"); ok {
			tm->setDuration(sj_float(timerObj, "duration", 1.0))
			tm.running = sj_bool(timerObj, "auto_start", false)
			tm.loop = sj_bool(timerObj, "loop", false)
		}
	case CameraNode:
		cam := cast(^CameraNode)node
		cam.zoom = cam.targetZoom
		cam.currentZoom = cam.targetZoom
		cam.currentPosition = cam.targetPosition
		if cam.isCurrent do scene.camera = cam
		// Follow target: a path relative to the camera, resolved when ready.
		if f := sj_string(obj, "follow", ""); f != "" {
			cam.followTarget = strings.clone(f, cam.allocator)
			cam.followResolved = false
		}
	case AnimationPlayerNode:
		apn := cast(^AnimationPlayerNode)node
		rm := resource_manager(ctx)
		if anims, ok := sj_arr(obj, "animations"); ok {
			for av in anims {
				ao, is_obj := av.(json.Object)
				if !is_obj do continue
				name := sj_string(ao, "name", "animation")
				loop := sj_bool(ao, "loop", true)
				anim: ^Animation
				if sheet := sj_string(ao, "sheet", ""); sheet != "" || sj_obj_has(ao, "grid") {
					grid := sj_vec2(ao, "grid", {1, 1})
					ssa := AnimationPlayerNode_AddSheetAnimation(apn, rm, name,
						Project_ResolveAssetPath(ctx, sheet) if sheet != "" else "",
						{int(grid.x), int(grid.y)}, sj_int(ao, "start", 0), sj_int(ao, "end", 0), loop)
					m := sj_vec2(ao, "margin", {})
					sp := sj_vec2(ao, "spacing", {})
					ssa.margin, ssa.spacing = {int(m.x), int(m.y)}, {int(sp.x), int(sp.y)}
					if cells, has := sj_arr(ao, "cells"); has {
						list := make([dynamic]int, context.temp_allocator)
						for cv in cells {
							#partial switch x in cv {
							case json.Integer: append(&list, int(x))
							case json.Float: append(&list, int(x))
							}
						}
						SpriteSheetAnimation_SetCells(ssa, list[:], apn.allocator)
					}
					anim = ssa
				} else {
					paths := make([dynamic]string, context.temp_allocator)
					if frames, has := sj_arr(ao, "frames"); has {
						for f in frames {
							if fs, is_str := f.(json.String); is_str do append(&paths, Project_ResolveAssetPath(ctx, fs))
						}
					}
					fa := AnimationPlayerNode_AddFrameAnimation(apn, rm, name, paths[:], loop)
					if sj_obj_has(ao, "start") || sj_obj_has(ao, "end") {
						Animation_SetRange(fa, sj_int(ao, "start", 0), sj_int(ao, "end", len(fa.frames) - 1))
					}
					anim = fa
				}
				anim.reverse = sj_bool(ao, "reverse", false)
				anim.fps = sj_float(ao, "fps", 0)
				anim.flipX = sj_bool(ao, "flip_x", false)
				anim.flipY = sj_bool(ao, "flip_y", false)
				if tracks, has := sj_arr(ao, "tracks"); has {
					for tv in tracks {
						to, isObj := tv.(json.Object)
						if !isObj do continue
						track := Animation_AddTrack(apn, anim, sj_string(to, "target", "."), sj_string(to, "property", ""))
						switch sj_string(to, "kind", "") {
						case "method": track.kind = .Method
						case "audio":  track.kind = .Audio
						}
						keys, _ := sj_arr(to, "keys")
						for kv in keys {
							ka, isArr := kv.(json.Array)
							if !isArr || len(ka) < 2 do continue
							num :: proc(v: json.Value) -> f32 {
								#partial switch x in v {
								case json.Integer: return f32(x)
								case json.Float:   return f32(x)
								}
								return 0
							}
							key := Track_Key{frame = num(ka[0])}
							if text, isStr := ka[1].(json.String); isStr {
								key.text = strings.clone(string(text), apn.allocator)
								append(&track.keys, key)
								continue
							}
							for i in 1 ..< min(len(ka), 5) do key.value[i - 1] = num(ka[i])
							if len(ka) >= 6 {
								if name, isStr := ka[5].(json.String); isStr do key.ease, _ = Ease_Parse(string(name))
							}
							append(&track.keys, key)
						}
					}
				}
			}
		}
		AnimationPlayerNode_SetFPS(apn, sj_float(obj, "fps", 12))
		apn.defaultAnimation = strings.clone(sj_string(obj, "default_animation", ""), apn.allocator)
		cur := apn.defaultAnimation if apn.defaultAnimation != "" else sj_string(obj, "animation", "")
		if cur != "" do AnimationPlayerNode_SetAnimationByName(apn, cur)
		if a := AnimationPlayerNode_GetAnimation(apn); a != nil do apn.currentFrame = a.startFrame
	case ParticleEmitterNode:
		pen := cast(^ParticleEmitterNode)node
		if stops, ok := sj_arr(obj, "color_ramp"); ok && len(stops) >= 1 {
			ramp := &pen.emitter.colorRamp
			ramp.count = 0
			for sv in stops {
				sa, isArr := sv.(json.Array)
				if !isArr || len(sa) < 5 || ramp.count >= MAX_COLOR_STOPS do continue
				num :: proc(v: json.Value) -> f32 {
					#partial switch x in v {
					case json.Integer: return f32(x)
					case json.Float:   return f32(x)
					}
					return 0
				}
				ramp.stops[ramp.count] = {position = num(sa[0]), color = {u8(num(sa[1])), u8(num(sa[2])), u8(num(sa[3])), u8(num(sa[4]))}}
				ramp.count += 1
			}
			ColorRamp_Sort(ramp)
		}
	case TileMapNode:
		tm := cast(^TileMapNode)node
		if tmObj, ok := sj_obj(obj, "tilemap"); ok {
			ts := sj_vec2(tmObj, "tile_size", {f32(tm.tileSize.x), f32(tm.tileSize.y)})
			ms := sj_vec2(tmObj, "map_size", {f32(tm.mapSize.x), f32(tm.mapSize.y)})
			tm.tileSize = {max(int(ts.x), 1), max(int(ts.y), 1)}
			tm.mapSize = {max(int(ms.x), 1), max(int(ms.y), 1)}
			// Start from an empty map of that size.
			tm.builtSize = {}
			clear(&tm.tiles)
			TileMapNode_Layout(tm)
			if ts := sj_string(tmObj, "tileset", ""); ts != "" do TileMapNode_SetTileset(tm, ts, ctx)
			if data, has := sj_arr(tmObj, "data"); has {
				i := 0
				for run in data {
					ra, isArr := run.(json.Array)
					if !isArr || len(ra) < 2 do continue
					jnum :: proc(v: json.Value) -> int {
						#partial switch x in v {
						case json.Integer: return int(x)
						case json.Float:   return int(x)
						}
						return 0
					}
					cnt, tile := jnum(ra[0]), jnum(ra[1])
					for _ in 0 ..< int(cnt) {
						if i >= len(tm.tiles) do break
						tm.tiles[i] = i32(tile)
						i += 1
					}
				}
				TileMapNode_Changed(tm)
			}
		}
	case LdtkLevelNode:
		if ldtkObj, ok := sj_obj(obj, "ldtk"); ok {
			Ldtk_ReadNodeConfig(cast(^LdtkLevelNode)node, ldtkObj, obj, Project_ResolveAssetPath(ctx, sj_string(ldtkObj, "project", "")))
		}
	}

	if shapes := node_shapes(node); shapes != nil {
		if arr, ok := sj_arr(obj, "shapes"); ok {
			clear(shapes)
			for v in arr {
				if so, is_obj := v.(json.Object); is_obj do append(shapes, read_shape(node, so))
			}
		}
	}

	// Old files put a texture on any node: show it with a child sprite.
	if node.typeId != TextureNode && node.typeId != FrameAnimationNode {
		if path := sj_texture_path(obj); path != "" {
			tn := cast(^TextureNode)Node_CreateByTypeName(scene, "TextureNode", node)
			tn.name = strings.clone("Sprite", tn.allocator)
			tn.layer = node.layer
			tn.gameContext = ctx
			load_texture_into(tn, path, ctx)
		}
	}

	if scriptObj, ok := sj_obj(obj, "script"); ok {
		if scriptPath := sj_string(scriptObj, "path", ""); scriptPath != "" {
			overrides: map[string]ScriptValue = nil
			if propsObj, has := sj_obj(scriptObj, "properties"); has {
				overrides = parse_script_overrides(propsObj, context.temp_allocator)
			}
			sm := ctx.scriptManager if ctx != nil else nil
			if node.typeId == ScriptNode {
				(cast(^ScriptNode)node).scriptPath = strings.clone(scriptPath, node.allocator)
			}
			_ = Script_AttachToNode(node, scriptPath, overrides, sm)
		}
	}

	if Node_HasOrigin(node) do read_origin(node, obj, ctx)
	read_connections(node, obj)
	read_material(node, obj)

	if children, ok := sj_arr(obj, "children"); ok {
		for c in children {
			if co, is_obj := c.(json.Object); is_obj do _ = read_node(scene, co, node, ctx)
		}
	}
	return node
}

// read_origin: the node's origin ("pivot", a fraction of its drawn size);
// scenes saved before it keep their look: a TextureNode's / animation's
// pixel "origin" converts, AnimationPlayers stay drawn from the top-left,
// nine-slices and text follow their old "centered" flag.
@(private = "file")
read_origin :: proc(node: ^Node, obj: json.Object, ctx: ^GameContext) {
	legacyPx := sj_vec2(obj, "origin", {0, 0})
	if _, has := obj["pivot"]; has {
		node.pivot = sj_vec2(obj, "pivot", {0.5, 0.5})
		if node.typeId == TextureNode && legacyPx != {0, 0} do (cast(^TextureNode)node).origin = legacyPx // the pixel override
		return
	}
	switch node.typeId {
	case TextureNode, FrameAnimationNode:
		if legacyPx == {0, 0} do return // the centre
		size := Node_OriginSize(node, ctx)
		if size.x > 0 && size.y > 0 {
			node.pivot = legacyPx / size
		} else if node.typeId == TextureNode {
			(cast(^TextureNode)node).origin = legacyPx // no texture loaded (headless): keep the pixels
		}
	case AnimationPlayerNode:
		node.pivot = {0, 0}
	case NineSliceNode, TextNode:
		centered := false
		if props, ok := sj_obj(obj, "properties"); ok do centered = bool(props["centered"].(json.Boolean) or_else false)
		node.pivot = {0.5, 0.5} if centered else {0, 0}
	}
}

@(private = "file")
read_shape :: proc(node: ^Node, obj: json.Object) -> PhysicsShape {
	shape: PhysicsShape
	typeName := strings.to_lower(sj_string(obj, "type", "box"), context.temp_allocator)
	stype: PhysicsShapeType = .Box
	for t in PhysicsShapeType {
		if strings.equal_fold(fmt.tprint(t), typeName) do stype = t
	}
	PhysicsShape_InitDefault(&shape, stype)
	props := Struct_CollectProperties(PhysicsShape, &shape)
	for key, val in obj {
		for p in props {
			if p.name == key {
				Property_ReadJSON(node, p, val)
				break
			}
		}
	}
	if verts, ok := sj_arr(obj, "vertices"); ok {
		shape.vertexCount = 0
		for v in verts {
			if arr, is_arr := v.(json.Array); is_arr && len(arr) >= 2 && shape.vertexCount < len(shape.vertices) {
				x, _ := json_number(arr[0])
				y, _ := json_number(arr[1])
				shape.vertices[shape.vertexCount] = {x, y}
				shape.vertexCount += 1
			}
		}
	}
	if pts, ok := sj_arr(obj, "chain_points"); ok {
		shape.chainPoints = make([dynamic][2]f32, node.allocator)
		for v in pts {
			if arr, is_arr := v.(json.Array); is_arr && len(arr) >= 2 {
				x, _ := json_number(arr[0])
				y, _ := json_number(arr[1])
				append(&shape.chainPoints, [2]f32{x, y})
			}
		}
	}
	return shape
}

// read_legacy_blocks applies the pre-"properties" format.
@(private = "file")
read_legacy_blocks :: proc(node: ^Node, obj: json.Object, ctx: ^GameContext) {
	legacy_shape :: proc(shapeObj: json.Object, sensor: bool, default_size: [2]f32) -> PhysicsShape {
		shape: PhysicsShape
		if strings.equal_fold(sj_string(shapeObj, "type", "box"), "circle") {
			PhysicsShape_InitDefault(&shape, .Circle)
			shape.radius = sj_float(shapeObj, "radius", 16)
		} else {
			PhysicsShape_InitDefault(&shape, .Box)
			shape.size = sj_vec2(shapeObj, "size", default_size)
		}
		shape.density = sj_float(shapeObj, "density", 1.0)
		shape.friction = sj_float(shapeObj, "friction", 0.3)
		shape.restitution = sj_float(shapeObj, "restitution", 0.0)
		shape.isSensor = sensor
		return shape
	}
	switch node.typeId {
	case DynamicBodyNode:
		db := cast(^DynamicBodyNode)node
		if phys, ok := sj_obj(obj, "physics"); ok {
			db.gravityScale = sj_float(phys, "gravity_scale", db.gravityScale)
			db.fixedRotation = sj_bool(phys, "fixed_rotation", db.fixedRotation)
			db.linearDamping = sj_float(phys, "linear_damping", db.linearDamping)
			db.angularDamping = sj_float(phys, "angular_damping", db.angularDamping)
			if s, has := sj_obj(phys, "shape"); has do append(&db.shapes, legacy_shape(s, false, {32, 32}))
		}
	case StaticBodyNode:
		sb := cast(^StaticBodyNode)node
		if phys, ok := sj_obj(obj, "physics"); ok {
			if s, has := sj_obj(phys, "shape"); has do append(&sb.shapes, legacy_shape(s, false, {64, 64}))
		}
	case AreaNode:
		ar := cast(^AreaNode)node
		if area, ok := sj_obj(obj, "area"); ok {
			if s, has := sj_obj(area, "shape"); has do append(&ar.shapes, legacy_shape(s, true, {64, 64}))
		}
	case CharacterMoverNode:
		cm := cast(^CharacterMoverNode)node
		if ch, ok := sj_obj(obj, "character"); ok {
			cm.maxSpeed = sj_float(ch, "speed", cm.maxSpeed)
			cm.jumpSpeed = sj_float(ch, "jump_speed", cm.jumpSpeed)
			cm.radius = sj_float(ch, "radius", cm.radius)
			cm.height = sj_float(ch, "height", cm.height)
		}
	case RaycastNode:
		rc := cast(^RaycastNode)node
		if ray, ok := sj_obj(obj, "raycast"); ok {
			rc.direction = sj_vec2(ray, "direction", rc.direction)
			rc.length = sj_float(ray, "length", rc.length)
		}
	case ParticleEmitterNode:
		pen := cast(^ParticleEmitterNode)node
		if part, ok := sj_obj(obj, "particles"); ok {
			pen.emitter.amount = sj_int(part, "amount", pen.emitter.amount)
			pen.emitter.lifetime = sj_float(part, "lifetime", pen.emitter.lifetime)
			pen.emitter.emitting = sj_bool(part, "emitting", pen.emitter.emitting)
			pen.emitter.continuous = sj_bool(part, "continuous", pen.emitter.continuous)
			pen.emitter.velocity = sj_float(part, "velocity", pen.emitter.velocity)
		}
	case CameraNode:
		cam := cast(^CameraNode)node
		if camObj, ok := sj_obj(obj, "camera"); ok {
			CameraNode_SetZoom(cam, sj_float(camObj, "zoom", 1.0))
		}
	}
}

// Json_Compact: a JSON value as compact text, whole numbers without
// decimals ("[4, 5]", not "[4.0000000000000000,5.0000000000000000]").
Json_Compact :: proc(v: json.Value) -> string {
	sb := strings.builder_make(context.temp_allocator)
	write :: proc(sb: ^strings.Builder, v: json.Value) {
		switch x in v {
		case json.Null:    strings.write_string(sb, "null")
		case json.Integer: fmt.sbprintf(sb, "%d", x)
		case json.Float:
			if x == f64(i64(x)) do fmt.sbprintf(sb, "%d", i64(x))
			else do fmt.sbprintf(sb, "%v", x)
		case json.Boolean: strings.write_string(sb, "true" if x else "false")
		case json.String:  fmt.sbprintf(sb, "%q", x)
		case json.Array:
			strings.write_byte(sb, '[')
			for e, i in x {
				if i > 0 do strings.write_string(sb, ", ")
				write(sb, e)
			}
			strings.write_byte(sb, ']')
		case json.Object:
			strings.write_byte(sb, '{')
			i := 0
			for k, e in x {
				if i > 0 do strings.write_string(sb, ", ")
				fmt.sbprintf(sb, "%q: ", k)
				write(sb, e)
				i += 1
			}
			strings.write_byte(sb, '}')
		}
	}
	write(&sb, v)
	return strings.to_string(sb)
}

@(private)
parse_script_overrides :: proc(propsObj: json.Object, allocator := context.temp_allocator) -> map[string]ScriptValue {
	overrides := make(map[string]ScriptValue, len(propsObj), allocator)
	for key, val in propsObj {
		#partial switch v in val {
		case json.Float:
			overrides[key] = ScriptValue{type = .Float, valFloat = f32(v)}
		case json.Integer:
			overrides[key] = ScriptValue{type = .Int, valInt = i64(v)}
		case json.String:
			overrides[key] = ScriptValue{type = .String, valString = strings.clone(v, allocator)}
		case json.Boolean:
			overrides[key] = ScriptValue{type = .Boolean, valBool = bool(v)}
		case json.Array:
			// Also the array's JSON text: list properties (array / curve /
			// gradient) use it whatever its length.
			raw := Json_Compact(val)
			overrides[key] = ScriptValue{type = .String, valString = strings.clone(string(raw), allocator)}
			if len(v) >= 4 {
				c: [4]f32
				for i in 0 ..< 4 do c[i], _ = json_number(v[i])
				overrides[key] = ScriptValue{type = .Color, valColor = c, valString = strings.clone(string(raw), allocator)}
			} else if len(v) >= 2 {
				x, _ := json_number(v[0])
				y, _ := json_number(v[1])
				overrides[key] = ScriptValue{type = .Vector2, valVec2 = {x, y}, valString = strings.clone(string(raw), allocator)}
			}
		}
	}
	return overrides
}


// --- JSON helpers (file-local; project_format.odin and ldtk.odin have their own) ---

@(private = "file")
sj_string :: proc(obj: json.Object, key: string, def: string = "") -> string {
	if s, ok := obj[key].(json.String); ok do return s
	return def
}

@(private = "file")
sj_int :: proc(obj: json.Object, key: string, def: int = 0) -> int {
	#partial switch v in obj[key] {
	case json.Integer: return int(v)
	case json.Float: return int(v)
	}
	return def
}

@(private = "file")
sj_float :: proc(obj: json.Object, key: string, def: f32 = 0) -> f32 {
	if f, ok := json_number(obj[key]); ok do return f
	return def
}

@(private = "file")
sj_bool :: proc(obj: json.Object, key: string, def: bool = false) -> bool {
	if b, ok := obj[key].(json.Boolean); ok do return bool(b)
	return def
}

@(private = "file")
sj_vec2 :: proc(obj: json.Object, key: string, def: [2]f32 = {0, 0}) -> [2]f32 {
	if arr, ok := obj[key].(json.Array); ok && len(arr) >= 2 {
		x, okx := json_number(arr[0])
		y, oky := json_number(arr[1])
		if okx && oky do return {x, y}
	}
	return def
}

@(private = "file")
sj_obj :: proc(obj: json.Object, key: string) -> (json.Object, bool) {
	o, ok := obj[key].(json.Object)
	return o, ok
}

@(private = "file")
read_tags :: proc(node: ^Node, obj: json.Object) {
	clear(&node.tags)
	if arr, ok := sj_arr(obj, "tags"); ok {
		for v in arr do if s, isStr := v.(json.String); isStr do Node_AddTag(node, s)
	}
}

@(private = "file")
sj_arr :: proc(obj: json.Object, key: string) -> (json.Array, bool) {
	a, ok := obj[key].(json.Array)
	return a, ok
}

// sj_texture_path reads "texture" (string or {"path"}) or legacy "texture_path".
@(private = "file")
sj_texture_path :: proc(obj: json.Object) -> string {
	if s := sj_string(obj, "texture_path", ""); s != "" do return s
	#partial switch v in obj["texture"] {
	case json.String: return v
	case json.Object: return sj_string(v, "path", "")
	}
	return ""
}


@(private = "file")
sj_obj_has :: proc(obj: json.Object, key: string) -> bool {
	_, ok := obj[key]
	return ok
}

// Component_ReadFile reads a component (prefab) file through the asset
// manager (project directory or mounted .ore).
Component_ReadFile :: proc(ctx: ^GameContext, compPath: string) -> ([]byte, bool) {
	if ctx != nil && ctx.game != nil {
		if data, ok := AssetManager_ReadFileBytes(&ctx.game.assetManager, compPath, context.temp_allocator); ok do return data, true
	}
	data, err := os.read_entire_file(compPath, context.temp_allocator)
	return data, err == nil
}

@(private = "file")
read_component_instance :: proc(scene: ^Scene, compPath: string, inst: json.Object, parent: ^Node, ctx: ^GameContext) -> ^Node {
	if componentDepth > 8 {
		log.errorf("[SceneLoader] Component '%s' nests too deep (recursive?)", compPath)
		return nil
	}
	data, ok := Component_ReadFile(ctx, compPath)
	if !ok {
		log.errorf("[SceneLoader] Component file not found: %s", compPath)
		return nil
	}
	val, err := json.parse(data, allocator = context.temp_allocator)
	if err != .None do return nil
	obj, isObj := val.(json.Object)
	if !isObj do return nil
	if inner, has := sj_obj(obj, "node"); has do obj = inner
	baseText := Component_PrepareBase(&obj, ctx)
	if ov, has := sj_obj(inst, "overrides"); has do Component_ApplyOverrides(&obj, ov)
	componentDepth += 1
	node := read_node(scene, obj, parent, ctx)
	componentDepth -= 1
	if node == nil do return nil
	node.componentPath = strings.clone(compPath, node.allocator)
	node.componentBase = strings.clone(baseText, node.allocator)
	node.name = strings.clone(sj_string(inst, "name", node.name), node.allocator)
	node.position = sj_vec2(inst, "position", node.position)
	node.scale = sj_vec2(inst, "scale", node.scale)
	node.rotation = sj_float(inst, "rotation", node.rotation)
	if Node_HasOrigin(node) do node.pivot = sj_vec2(inst, "pivot", node.pivot)
	node.enabled = sj_bool(inst, "enabled", node.enabled)
	node.renderable = sj_bool(inst, "visible", node.renderable)
	node.layer = RenderLayer(math.clamp(sj_int(inst, "layer", int(node.layer)), 0, len(RenderLayer) - 1))
	node.pauseMode = Pause_ModeParse(sj_string(inst, "pause_mode", ""))
	node.paused = sj_bool(inst, "paused", false)
	node.editorLocked = sj_bool(inst, "editor_locked", false)
	node.editorHidden = sj_bool(inst, "editor_hidden", false)
	read_tags(node, inst)
	if sj_obj_has(inst, "connections") do read_connections(node, inst)
	return node
}

// Scene_InstantiateComponent adds a linked instance of a component file.
Scene_InstantiateComponent :: proc(scene: ^Scene, compPath: string, parent: ^Node, ctx: ^GameContext) -> ^Node {
	inst := make(json.Object, 0, context.temp_allocator)
	target := parent if parent != nil else scene.rootNode
	return read_component_instance(scene, compPath, inst, target, ctx)
}

// Scene_RefreshComponentInstances rebuilds every linked instance of a
// component (after the component file changed), keeping each instance's
// name, transform and place in the hierarchy. Returns how many it rebuilt.
Scene_RefreshComponentInstances :: proc(scene: ^Scene, compPath: string, ctx: ^GameContext) -> int {
	if scene == nil || scene.manager == nil do return 0
	targets := make([dynamic]^Node, context.temp_allocator)
	for n in scene.manager.nodes {
		if n != nil && n.componentPath == compPath do append(&targets, n)
	}
	count := 0
	for old in targets {
		parent := GetParent(scene.manager, old)
		if parent == nil do continue
		index := 0
		for c, i in GetChildrenView(scene.manager, parent) {
			if c == old {index = i; break}
		}
		// The instance's own state is its JSON (link + transform).
		instJson := Node_SerializeToJSON(old, scene.manager, context.temp_allocator)
		RemoveNode(scene.manager, old)
		ProcessNodeQueues(scene.manager, ctx)
		fresh := Scene_InstantiateNodeFromJSON(scene, transmute([]u8)instJson, parent, ctx)
		if fresh == nil do continue
		MoveChild(scene.manager, parent, fresh, index)
		count += 1
	}
	ProcessNodeQueues(scene.manager, ctx)
	return count
}

// Node_UnlinkComponent turns an instance into ordinary nodes.
Node_UnlinkComponent :: proc(node: ^Node) {
	node.componentPath = ""
	node.componentBase = ""
}

// Node_ComponentRoot returns the linked instance a node belongs to (the
// node itself, an ancestor, or nil).
Node_ComponentRoot :: proc(manager: ^NodeManager, node: ^Node) -> ^Node {
	for n := node; n != nil; n = GetParent(manager, n) {
		if n.componentPath != "" do return n
	}
	return nil
}

// --- StateMachineNode ------------------------------------------------------------
// "state_machine": {"initial", "player", "autostart",
//   "params": [[name, value], ...],
//   "states": [{"name", "animation", "child", "pos": [x, y],
//               "min_time", "interruptible": false, "leave_when": [...], "enter_when": [...]}, ...],
//   "transitions": [{"from", "to", "blend", "when": [[op, param, value], ...]}, ...]}
// Conditions: ["true"|"false"|"trigger", param], ["=="|"!="|">"|"<", param, value],
// ["finished"], ["after", seconds], ["call", method], ["or"] (starts another group).

@(private = "file")
write_sm_conditions :: proc(w: ^Json_Writer, conds: []SM_Condition) {
	strings.write_byte(&w.sb, '[')
	for c, j in conds {
		if j > 0 do strings.write_string(&w.sb, ", ")
		strings.write_byte(&w.sb, '[')
		Json_String(w, SM_OP_NAMES[c.op])
		if SM_Op_UsesParam(c.op) {strings.write_string(&w.sb, ", "); Json_String(w, c.param)}
		if SM_Op_UsesValue(c.op) {strings.write_string(&w.sb, ", "); Json_Float(w, c.value)}
		strings.write_byte(&w.sb, ']')
	}
	strings.write_byte(&w.sb, ']')
}

@(private = "file")
read_sm_conditions :: proc(sm: ^StateMachineNode, list: ^[dynamic]SM_Condition, arr: json.Array) {
	for cv in arr {
		ca, cok := cv.(json.Array)
		if !cok || len(ca) < 1 do continue
		opName, _ := ca[0].(json.String)
		op, opok := SM_Op_Parse(opName)
		if !opok do continue
		c := SM_Condition{op = op}
		k := 1
		if SM_Op_UsesParam(op) && k < len(ca) {
			if s, sok := ca[k].(json.String); sok do c.param = strings.clone(s, sm.allocator)
			k += 1
		}
		if SM_Op_UsesValue(op) && k < len(ca) {
			if f, fok := json_number(ca[k]); fok do c.value = f
		}
		if list.allocator.procedure == nil do list.allocator = sm.allocator
		append(list, c)
	}
}

@(private = "file")
write_state_machine :: proc(w: ^Json_Writer, sm: ^StateMachineNode) {
	strings.write_byte(&w.sb, '{')
	w.indent += 1
	Json_NewLine(w); strings.write_string(&w.sb, "\"initial\": "); Json_String(w, sm.initial)
	strings.write_string(&w.sb, ", \"player\": "); Json_String(w, sm.player)
	fmt.sbprintf(&w.sb, ", \"autostart\": %t, \"any_pos\": [", sm.autostart)
	Json_Float(w, sm.anyPos.x)
	strings.write_string(&w.sb, ", ")
	Json_Float(w, sm.anyPos.y)
	strings.write_string(&w.sb, "],")
	Json_NewLine(w); strings.write_string(&w.sb, "\"params\": [")
	for p, i in sm.params {
		if i > 0 do strings.write_string(&w.sb, ", ")
		strings.write_byte(&w.sb, '[')
		Json_String(w, p.name)
		strings.write_string(&w.sb, ", ")
		Json_Float(w, p.value)
		strings.write_byte(&w.sb, ']')
	}
	strings.write_string(&w.sb, "],")
	Json_NewLine(w); strings.write_string(&w.sb, "\"states\": [")
	w.indent += 1
	for s, i in sm.states {
		if i > 0 do strings.write_byte(&w.sb, ',')
		Json_NewLine(w)
		strings.write_string(&w.sb, "{\"name\": "); Json_String(w, s.name)
		if s.animation != "" {strings.write_string(&w.sb, ", \"animation\": "); Json_String(w, s.animation)}
		if s.child != "" {strings.write_string(&w.sb, ", \"child\": "); Json_String(w, s.child)}
		strings.write_string(&w.sb, ", \"pos\": [")
		Json_Float(w, s.pos.x)
		strings.write_string(&w.sb, ", ")
		Json_Float(w, s.pos.y)
		strings.write_byte(&w.sb, ']')
		if s.minTime > 0 {strings.write_string(&w.sb, ", \"min_time\": "); Json_Float(w, s.minTime)}
		if s.noInterrupt do strings.write_string(&w.sb, ", \"interruptible\": false")
		if len(s.leaveWhen) > 0 {strings.write_string(&w.sb, ", \"leave_when\": "); write_sm_conditions(w, s.leaveWhen[:])}
		if len(s.enterWhen) > 0 {strings.write_string(&w.sb, ", \"enter_when\": "); write_sm_conditions(w, s.enterWhen[:])}
		strings.write_byte(&w.sb, '}')
	}
	w.indent -= 1
	if len(sm.states) > 0 do Json_NewLine(w)
	strings.write_string(&w.sb, "],")
	Json_NewLine(w); strings.write_string(&w.sb, "\"transitions\": [")
	w.indent += 1
	for t, i in sm.transitions {
		if i > 0 do strings.write_byte(&w.sb, ',')
		Json_NewLine(w)
		strings.write_string(&w.sb, "{\"from\": "); Json_String(w, t.from)
		strings.write_string(&w.sb, ", \"to\": "); Json_String(w, t.to)
		if t.blend > 0 {strings.write_string(&w.sb, ", \"blend\": "); Json_Float(w, t.blend)}
		strings.write_string(&w.sb, ", \"when\": ")
		write_sm_conditions(w, t.conditions[:])
		strings.write_byte(&w.sb, '}')
	}
	w.indent -= 1
	if len(sm.transitions) > 0 do Json_NewLine(w)
	strings.write_byte(&w.sb, ']')
	w.indent -= 1
	Json_NewLine(w)
	strings.write_byte(&w.sb, '}')
}

@(private = "file")
read_state_machine :: proc(sm: ^StateMachineNode, obj: json.Object) {
	clear(&sm.states)
	clear(&sm.transitions)
	clear(&sm.params)
	sm.autostart = sj_bool(obj, "autostart", true)
	if pa, pok := sj_arr(obj, "any_pos"); pok && len(pa) == 2 {
		x, _ := json_number(pa[0])
		y, _ := json_number(pa[1])
		sm.anyPos = {x, y}
	}
	sm.player = strings.clone(sj_string(obj, "player", ""), sm.allocator)
	sm.playerNode = nil
	if arr, ok := sj_arr(obj, "params"); ok {
		for v in arr {
			p, pok := v.(json.Array)
			if !pok || len(p) < 1 do continue
			name, nok := p[0].(json.String)
			if !nok do continue
			val: f32
			if len(p) > 1 {
				if f, fok := json_number(p[1]); fok do val = f
				else if b, bok := p[1].(json.Boolean); bok do val = 1 if b else 0
			}
			StateMachine_SetParam(sm, name, val)
		}
	}
	if arr, ok := sj_arr(obj, "states"); ok {
		for v in arr {
			so, sok := v.(json.Object)
			if !sok do continue
			name := sj_string(so, "name", "")
			if name == "" do continue
			i := StateMachine_AddState(sm, name, sj_string(so, "animation", ""))
			sm.states[i].child = strings.clone(sj_string(so, "child", ""), sm.allocator)
			if pa, pok := sj_arr(so, "pos"); pok && len(pa) == 2 {
				x, _ := json_number(pa[0])
				y, _ := json_number(pa[1])
				sm.states[i].pos = {x, y}
			}
			st := &sm.states[i]
			st.minTime = sj_float(so, "min_time", 0)
			st.noInterrupt = !sj_bool(so, "interruptible", true)
			if a, aok := sj_arr(so, "leave_when"); aok do read_sm_conditions(sm, &st.leaveWhen, a)
			if a, aok := sj_arr(so, "enter_when"); aok do read_sm_conditions(sm, &st.enterWhen, a)
		}
	}
	if arr, ok := sj_arr(obj, "transitions"); ok {
		for v in arr {
			to, tok := v.(json.Object)
			if !tok do continue
			t := StateMachine_AddTransition(sm, sj_string(to, "from", SM_ANY), sj_string(to, "to", ""), sj_float(to, "blend", 0))
			when_arr, _ := sj_arr(to, "when")
			read_sm_conditions(sm, &t.conditions, when_arr)
		}
	}
	sm.initial = ""
	if init := sj_string(obj, "initial", ""); init != "" {
		if i := StateMachine_FindState(sm, init); i >= 0 do sm.initial = sm.states[i].name
	}
	if sm.initial == "" && len(sm.states) > 0 do sm.initial = sm.states[0].name
	sm.current = -1
	sm.previous = -1
	sm.running = false
}
