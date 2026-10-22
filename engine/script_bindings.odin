package engine

import "base:runtime"
import "core:c"
import "core:log"
import "core:math"
import "core:os"
import "core:strings"
import "core:time"
import "core:encoding/uuid"
import lua "vendor:lua/5.4"
import rl "vendor:raylib"
import b2 "vendor:box2d"

// ============================================================================
// Lua Engine API Bindings (Node, Input, Audio, Physics, Camera, Scene, Log, Engine)
// ============================================================================

NodeUserData :: struct {
	node:   ^Node,
	nodeId: uuid.Identifier,
}

push_node_userdata :: proc(L: ^lua.State, node: ^Node) {
	if node == nil || !Node_IsAlive(node) {
		lua.pushnil(L)
		return
	}
	ud := cast(^NodeUserData)lua.newuserdatauv(L, size_of(NodeUserData), 0)
	ud.node = node
	ud.nodeId = node.id

	lua.L_getmetatable(L, "Engine.Node")
	lua.setmetatable(L, -2)
}

// to_node_userdata resolves a Lua node reference through the live-node
// registry by id, so references to destroyed nodes yield (nil, false)
// instead of reading freed memory.
to_node_userdata :: proc(L: ^lua.State, idx: c.int) -> (^Node, bool) {
	ud := cast(^NodeUserData)lua.L_testudata(L, idx, "Engine.Node")
	if ud == nil do return nil, false
	node := Node_FromId(ud.nodeId)
	if node == nil do return nil, false
	return node, true
}

get_script_manager :: proc(L: ^lua.State) -> ^ScriptManager {
	lua.getfield(L, lua.REGISTRYINDEX, "__Engine_ScriptManager")
	mgr := cast(^ScriptManager)lua.touserdata(L, -1)
	lua.pop(L, 1)
	return mgr
}

// ----------------------------------------------------------------------------
// Node Core & Hierarchy Bindings
// ----------------------------------------------------------------------------

@(private="file")
lua_node_get_type :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushstring(L, "Unknown")
		return 1
	}
	typeName := "Node"
	switch node.typeId {
	case Node: typeName = "Node"
	case TextureNode: typeName = "TextureNode"
	case ScriptNode: typeName = "ScriptNode"
	case CameraNode: typeName = "CameraNode"
	case ParticleEmitterNode: typeName = "ParticleEmitterNode"
	case AnimationPlayerNode: typeName = "AnimationPlayerNode"
	case TimerNode: typeName = "TimerNode"
	case SoundNode: typeName = "SoundNode"
	case MusicNode: typeName = "MusicNode"
	case DynamicBodyNode: typeName = "DynamicBodyNode"
	case StaticBodyNode: typeName = "StaticBodyNode"
	case CharacterMoverNode: typeName = "CharacterMoverNode"
	case AreaNode: typeName = "AreaNode"
	case RaycastNode: typeName = "RaycastNode"
	case LdtkLevelNode: typeName = "LdtkLevelNode"
	case LightNode: typeName = "LightNode"
	case StateMachineNode: typeName = "StateMachineNode"
	case JointNode: typeName = "JointNode"
	case TextNode: typeName = "TextNode"
	case DialogueNode: typeName = "DialogueNode"
	case NineSliceNode: typeName = "NineSliceNode"
	case ParallaxNode: typeName = "ParallaxNode"
	case LineNode: typeName = "LineNode"
	case TrailNode: typeName = "TrailNode"
	case PostEffectNode: typeName = "PostEffectNode"
	case TileMapNode: typeName = "TileMapNode"
	}
	nameC := strings.clone_to_cstring(typeName, context.temp_allocator)
	lua.pushstring(L, nameC)
	return 1
}

@(private="file")
lua_node_get_name :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushnil(L)
		return 1
	}
	nameC := strings.clone_to_cstring(node.name, context.temp_allocator)
	lua.pushstring(L, nameC)
	return 1
}

@(private="file")
lua_node_set_name :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	nameC := lua.tostring(L, 2)
	if nameC != nil {
		node.name = strings.clone(string(nameC), node.allocator)
	}
	return 0
}

@(private="file")
lua_node_get_position :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	lua.pushnumber(L, lua.Number(node.position.x))
	lua.pushnumber(L, lua.Number(node.position.y))
	return 2
}

@(private="file")
lua_node_set_position :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	x := f32(lua.tonumber(L, 2))
	y := f32(lua.tonumber(L, 3))
	node.position = {x, y}
	return 0
}

@(private="file")
lua_node_translate :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	dx := f32(lua.tonumber(L, 2))
	dy := f32(lua.tonumber(L, 3))
	node.position.x += dx
	node.position.y += dy
	return 0
}

@(private="file")
lua_node_get_rotation :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushnumber(L, 0)
		return 1
	}
	lua.pushnumber(L, lua.Number(node.rotation))
	return 1
}

@(private="file")
lua_node_set_rotation :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	rot := f32(lua.tonumber(L, 2))
	node.rotation = rot
	return 0
}

@(private="file")
lua_node_rotate :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	dRot := f32(lua.tonumber(L, 2))
	node.rotation += dRot
	return 0
}

@(private="file")
lua_node_get_scale :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushnumber(L, 1)
		lua.pushnumber(L, 1)
		return 2
	}
	lua.pushnumber(L, lua.Number(node.scale.x))
	lua.pushnumber(L, lua.Number(node.scale.y))
	return 2
}

@(private="file")
lua_node_set_scale :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	sx := f32(lua.tonumber(L, 2))
	sy := f32(lua.tonumber(L, 3))
	if lua.gettop(L) == 2 {
		sy = sx
	}
	node.scale = {sx, sy}
	return 0
}

// node:get_node(path): a node by path relative to this one ("Gun",
// "../Player", "." self); nil if missing.
@(private="file")
lua_node_get_node :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.gameContext == nil || node.gameContext.scene == nil || lua.type(L, 2) != .STRING {
		lua.pushnil(L)
		return 1
	}
	push_node_userdata(L, Node_ResolvePath(node.gameContext.scene.manager, node, string(lua.tostring(L, 2))))
	return 1
}

// node:set_texture(path): a TextureNode shows another image (project path).
@(private="file")
lua_node_set_texture :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != TextureNode || lua.type(L, 2) != .STRING {
		lua.pushboolean(L, false)
		return 1
	}
	tn := cast(^TextureNode)node
	rm := Node_ResourceManager(node)
	path := string(lua.tostring(L, 2))
	if rm == nil {
		lua.pushboolean(L, false)
		return 1
	}
	tex, loaded := rm.loadTexture(rm, Project_ResolveAssetPath(node.gameContext, path))
	if loaded && tex != nil {
		TextureNode_SetTexture(tn, tex)
		tn.filePath = strings.clone(path, tn.allocator)
		tn.size = {f32(tex.texture.width), f32(tex.texture.height)}
	}
	lua.pushboolean(L, b32(loaded))
	return 1
}

@(private="file")
lua_node_get_global_position :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	lua.pushnumber(L, lua.Number(node.globalPosition.x))
	lua.pushnumber(L, lua.Number(node.globalPosition.y))
	return 2
}

@(private="file")
lua_node_get_global_rotation :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushnumber(L, 0)
		return 1
	}
	lua.pushnumber(L, lua.Number(node.globalRotation))
	return 1
}

@(private="file")
lua_node_is_enabled :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushboolean(L, false)
		return 1
	}
	lua.pushboolean(L, b32(node.enabled))
	return 1
}

@(private="file")
lua_node_set_enabled :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	enabled := lua.toboolean(L, 2)
	node.enabled = bool(enabled)
	return 0
}

@(private="file")
lua_node_is_visible :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushboolean(L, false)
		return 1
	}
	lua.pushboolean(L, b32(node.renderable))
	return 1
}

@(private="file")
lua_node_set_visible :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	visible := lua.toboolean(L, 2)
	node.renderable = bool(visible)
	return 0
}

@(private="file")
lua_node_get_parent :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.gameContext == nil || node.gameContext.scene == nil {
		lua.pushnil(L)
		return 1
	}
	parent := GetParent(node.gameContext.scene.manager, node)
	push_node_userdata(L, parent)
	return 1
}

@(private="file")
lua_node_get_children :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.gameContext == nil || node.gameContext.scene == nil {
		lua.newtable(L)
		return 1
	}
	children := GetChildren(node.gameContext.scene.manager, node)
	defer delete(children)

	lua.createtable(L, c.int(len(children)), 0)
	for child, i in children {
		push_node_userdata(L, child)
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

@(private="file")
lua_node_get_child :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.gameContext == nil || node.gameContext.scene == nil {
		lua.pushnil(L)
		return 1
	}
	nameC := lua.tostring(L, 2)
	if nameC == nil {
		lua.pushnil(L)
		return 1
	}
	targetName := string(nameC)
	children := GetChildren(node.gameContext.scene.manager, node)
	defer delete(children)

	for child in children {
		if child.name == targetName {
			push_node_userdata(L, child)
			return 1
		}
	}
	lua.pushnil(L)
	return 1
}

@(private="file")
lua_node_add_child :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	parent, okP := to_node_userdata(L, 1)
	child, okC := to_node_userdata(L, 2)
	if okP && okC && parent.gameContext != nil && parent.gameContext.scene != nil {
		SceneAddChild(parent.gameContext.scene, parent, child)
	}
	return 0
}

@(private="file")
lua_node_remove_child :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	parent, okP := to_node_userdata(L, 1)
	child, okC := to_node_userdata(L, 2)
	if okP && okC && parent.gameContext != nil && parent.gameContext.scene != nil {
		SceneRemoveChild(parent.gameContext.scene, parent, child)
	}
	return 0
}

@(private="file")
lua_node_destroy :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if ok && node.gameContext != nil && node.gameContext.scene != nil {
		SceneRemoveNode(node.gameContext.scene, node)
	}
	return 0
}

// ----------------------------------------------------------------------------
// Physics: DynamicBodyNode Methods
// ----------------------------------------------------------------------------

@(private="file")
lua_node_apply_force :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	fx := f32(lua.tonumber(L, 2))
	fy := f32(lua.tonumber(L, 3))

	if node.typeId == DynamicBodyNode {
		dynBody := cast(^DynamicBodyNode)node
		if dynBody.bodyId.index1 != 0 {
			DynamicBodyNode_ApplyForce(dynBody, [2]f32{fx, fy})
		}
	}
	return 0
}

@(private="file")
lua_node_apply_impulse :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	ix := f32(lua.tonumber(L, 2))
	iy := f32(lua.tonumber(L, 3))

	if node.typeId == DynamicBodyNode {
		dynBody := cast(^DynamicBodyNode)node
		if dynBody.bodyId.index1 != 0 {
			DynamicBodyNode_ApplyImpulse(dynBody, [2]f32{ix, iy})
		}
	}
	return 0
}

@(private="file")
lua_node_get_linear_velocity :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	if node.typeId == DynamicBodyNode {
		dynBody := cast(^DynamicBodyNode)node
		if dynBody.bodyId.index1 != 0 && b2.Body_IsValid(dynBody.bodyId) {
			vel := b2.Body_GetLinearVelocity(dynBody.bodyId)
			lua.pushnumber(L, lua.Number(vel.x))
			lua.pushnumber(L, lua.Number(vel.y))
			return 2
		}
	} else if node.typeId == CharacterMoverNode {
		cm := cast(^CharacterMoverNode)node
		lua.pushnumber(L, lua.Number(cm.velocity.x))
		lua.pushnumber(L, lua.Number(cm.velocity.y))
		return 2
	}
	lua.pushnumber(L, 0)
	lua.pushnumber(L, 0)
	return 2
}

@(private="file")
lua_node_set_linear_velocity :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	vx := f32(lua.tonumber(L, 2))
	vy := f32(lua.tonumber(L, 3))
	if node.typeId == DynamicBodyNode {
		dynBody := cast(^DynamicBodyNode)node
		if dynBody.bodyId.index1 != 0 && b2.Body_IsValid(dynBody.bodyId) {
			b2.Body_SetLinearVelocity(dynBody.bodyId, [2]f32{vx, vy})
			b2.Body_SetAwake(dynBody.bodyId, true)
		}
	} else if node.typeId == CharacterMoverNode {
		cm := cast(^CharacterMoverNode)node
		cm.velocity = {vx, vy}
	}
	return 0
}

@(private="file")
lua_node_get_angular_velocity :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushnumber(L, 0)
		return 1
	}
	if node.typeId == DynamicBodyNode {
		dynBody := cast(^DynamicBodyNode)node
		if dynBody.bodyId.index1 != 0 && b2.Body_IsValid(dynBody.bodyId) {
			w := math.to_degrees(b2.Body_GetAngularVelocity(dynBody.bodyId))
			lua.pushnumber(L, lua.Number(w))
			return 1
		}
	}
	lua.pushnumber(L, 0)
	return 1
}

@(private="file")
lua_node_set_angular_velocity :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	w := f32(lua.tonumber(L, 2))
	if node.typeId == DynamicBodyNode {
		dynBody := cast(^DynamicBodyNode)node
		if dynBody.bodyId.index1 != 0 && b2.Body_IsValid(dynBody.bodyId) {
			b2.Body_SetAngularVelocity(dynBody.bodyId, math.to_radians(w))
			b2.Body_SetAwake(dynBody.bodyId, true)
		}
	}
	return 0
}

@(private="file")
lua_node_get_gravity_scale :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushnumber(L, 1)
		return 1
	}
	if node.typeId == DynamicBodyNode {
		db := cast(^DynamicBodyNode)node
		lua.pushnumber(L, lua.Number(db.gravityScale))
		return 1
	} else if node.typeId == CharacterMoverNode {
		cm := cast(^CharacterMoverNode)node
		lua.pushnumber(L, lua.Number(cm.gravityScale))
		return 1
	}
	lua.pushnumber(L, 1)
	return 1
}

@(private="file")
lua_node_set_gravity_scale :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	scale := f32(lua.tonumber(L, 2))
	if node.typeId == DynamicBodyNode {
		db := cast(^DynamicBodyNode)node
		db.gravityScale = scale
		if b2.Body_IsValid(db.bodyId) {
			b2.Body_SetGravityScale(db.bodyId, scale)
		}
	} else if node.typeId == CharacterMoverNode {
		cm := cast(^CharacterMoverNode)node
		cm.gravityScale = scale
	}
	return 0
}

@(private="file")
lua_node_is_fixed_rotation :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushboolean(L, false)
		return 1
	}
	if node.typeId == DynamicBodyNode {
		db := cast(^DynamicBodyNode)node
		lua.pushboolean(L, b32(db.fixedRotation))
		return 1
	}
	lua.pushboolean(L, false)
	return 1
}

@(private="file")
lua_node_set_fixed_rotation :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	fixed := lua.toboolean(L, 2)
	if node.typeId == DynamicBodyNode {
		db := cast(^DynamicBodyNode)node
		db.fixedRotation = bool(fixed)
		if b2.Body_IsValid(db.bodyId) {
			b2.Body_SetFixedRotation(db.bodyId, bool(fixed))
		}
	}
	return 0
}

@(private="file")
lua_node_set_linear_damping :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	damping := f32(lua.tonumber(L, 2))
	if node.typeId == DynamicBodyNode {
		db := cast(^DynamicBodyNode)node
		db.linearDamping = damping
		if b2.Body_IsValid(db.bodyId) {
			b2.Body_SetLinearDamping(db.bodyId, damping)
		}
	}
	return 0
}

@(private="file")
lua_node_set_angular_damping :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	damping := f32(lua.tonumber(L, 2))
	if node.typeId == DynamicBodyNode {
		db := cast(^DynamicBodyNode)node
		db.angularDamping = damping
		if b2.Body_IsValid(db.bodyId) {
			b2.Body_SetAngularDamping(db.bodyId, damping)
		}
	}
	return 0
}

@(private="file")
lua_node_is_awake :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushboolean(L, false)
		return 1
	}
	if node.typeId == DynamicBodyNode {
		db := cast(^DynamicBodyNode)node
		if b2.Body_IsValid(db.bodyId) {
			lua.pushboolean(L, b32(b2.Body_IsAwake(db.bodyId)))
			return 1
		}
	}
	lua.pushboolean(L, false)
	return 1
}

@(private="file")
lua_node_set_awake :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	awake := lua.toboolean(L, 2)
	if node.typeId == DynamicBodyNode {
		db := cast(^DynamicBodyNode)node
		if b2.Body_IsValid(db.bodyId) {
			b2.Body_SetAwake(db.bodyId, bool(awake))
		}
	}
	return 0
}

// ----------------------------------------------------------------------------
// Physics: CharacterMoverNode Methods
// ----------------------------------------------------------------------------

@(private="file")
lua_node_character_move :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CharacterMoverNode do return 0
	dirX := f32(lua.tonumber(L, 2))
	jump := lua.toboolean(L, 3)

	cm := cast(^CharacterMoverNode)node
	cm.targetSpeedX = dirX * cm.maxSpeed
	if jump && cm.isGrounded {
		cm.velocity.y = -cm.jumpSpeed
		cm.isGrounded = false
	}
	return 0
}

@(private="file")
lua_node_character_is_grounded :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CharacterMoverNode {
		lua.pushboolean(L, false)
		return 1
	}
	cm := cast(^CharacterMoverNode)node
	lua.pushboolean(L, b32(cm.isGrounded))
	return 1
}

@(private="file")
lua_node_character_get_velocity :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CharacterMoverNode {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	cm := cast(^CharacterMoverNode)node
	lua.pushnumber(L, lua.Number(cm.velocity.x))
	lua.pushnumber(L, lua.Number(cm.velocity.y))
	return 2
}

@(private="file")
lua_node_character_set_velocity :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CharacterMoverNode do return 0
	vx := f32(lua.tonumber(L, 2))
	vy := f32(lua.tonumber(L, 3))
	cm := cast(^CharacterMoverNode)node
	cm.velocity = {vx, vy}
	return 0
}

@(private="file")
lua_node_character_set_speed :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CharacterMoverNode do return 0
	spd := f32(lua.tonumber(L, 2))
	cm := cast(^CharacterMoverNode)node
	cm.maxSpeed = spd
	return 0
}

@(private="file")
lua_node_character_set_jump_speed :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CharacterMoverNode do return 0
	jspd := f32(lua.tonumber(L, 2))
	cm := cast(^CharacterMoverNode)node
	cm.jumpSpeed = jspd
	return 0
}

@(private="file")
mover_arg :: proc(L: ^lua.State) -> ^CharacterMoverNode {
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CharacterMoverNode do return nil
	return cast(^CharacterMoverNode)node
}

// character_move_and_slide([dt]) -> collided: moves by the velocity, sliding
// along surfaces (Godot's move_and_slide). The node switches to Script mode.
@(private="file")
lua_node_character_move_and_slide :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cm := mover_arg(L)
	if cm == nil {
		lua.pushboolean(L, false)
		return 1
	}
	cm.controlMode = .Script
	dt := f32(lua.tonumber(L, 2)) if lua.type(L, 2) == .NUMBER else cm.frameDelta
	ctx := cm.gameContext
	lua.pushboolean(L, b32(CharacterMoverNode_MoveAndSlide(cm, ctx, dt)))
	return 1
}

@(private="file")
lua_node_character_contact :: proc(L: ^lua.State, which: int) -> c.int {
	cm := mover_arg(L)
	v := false
	if cm != nil {
		switch which {
		case 0: v = cm.isOnFloor
		case 1: v = cm.isOnWall
		case 2: v = cm.isOnCeiling
		}
	}
	lua.pushboolean(L, b32(v))
	return 1
}

@(private="file")
lua_node_character_is_on_floor :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	return lua_node_character_contact(L, 0)
}

@(private="file")
lua_node_character_is_on_wall :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	return lua_node_character_contact(L, 1)
}

@(private="file")
lua_node_character_is_on_ceiling :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	return lua_node_character_contact(L, 2)
}

@(private="file")
push_vec :: proc(L: ^lua.State, v: [2]f32) -> c.int {
	lua.pushnumber(L, lua.Number(v.x))
	lua.pushnumber(L, lua.Number(v.y))
	return 2
}

@(private="file")
lua_node_character_get_floor_normal :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cm := mover_arg(L)
	return push_vec(L, cm.floorNormal if cm != nil else {})
}

@(private="file")
lua_node_character_get_wall_normal :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cm := mover_arg(L)
	return push_vec(L, cm.wallNormal if cm != nil else {})
}

@(private="file")
lua_node_character_get_last_motion :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cm := mover_arg(L)
	return push_vec(L, cm.lastMotion if cm != nil else {})
}

@(private="file")
lua_node_character_get_gravity :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cm := mover_arg(L)
	return push_vec(L, CharacterMoverNode_Gravity(cm, cm.gameContext) if cm != nil else {})
}

@(private="file")
lua_node_character_set_gravity_scale :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	if cm := mover_arg(L); cm != nil do cm.gravityScale = f32(lua.tonumber(L, 2))
	return 0
}

// character_set_control_mode("script" | "builtin")
@(private="file")
lua_node_character_set_control_mode :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	if cm := mover_arg(L); cm != nil && lua.type(L, 2) == .STRING {
		cm.controlMode = .BuiltIn if string(lua.tostring(L, 2)) == "builtin" else .Script
	}
	return 0
}

// ----------------------------------------------------------------------------
// Physics: AreaNode (Sensors)
// ----------------------------------------------------------------------------

@(private="file")
lua_node_area_is_overlapping :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AreaNode {
		lua.pushboolean(L, false)
		return 1
	}
	area := cast(^AreaNode)node
	lua.pushboolean(L, b32(area.hasOverlaps))
	return 1
}

@(private="file")
lua_node_area_get_overlap_count :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AreaNode {
		lua.pushinteger(L, 0)
		return 1
	}
	area := cast(^AreaNode)node
	lua.pushinteger(L, lua.Integer(area.overlapCount))
	return 1
}

@(private="file")
lua_node_area_get_overlapping_nodes :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AreaNode {
		lua.newtable(L)
		return 1
	}
	area := cast(^AreaNode)node
	lua.createtable(L, c.int(len(area.overlappingNodes)), 0)
	for other, i in area.overlappingNodes {
		push_node_userdata(L, other)
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

// ----------------------------------------------------------------------------
// Physics: RaycastNode
// ----------------------------------------------------------------------------

@(private="file")
lua_node_raycast_cast :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	sm := get_script_manager(L)
	if !ok || node.typeId != RaycastNode || sm == nil || sm.game == nil do return 0
	rc := cast(^RaycastNode)node
	RaycastNode_CastNow(rc, sm.game.physicsWorld.worldId)
	return 0
}

@(private="file")
lua_node_raycast_is_colliding :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != RaycastNode {
		lua.pushboolean(L, false)
		return 1
	}
	rc := cast(^RaycastNode)node
	lua.pushboolean(L, b32(rc.isColliding))
	return 1
}

@(private="file")
lua_node_raycast_get_hit_point :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != RaycastNode {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	rc := cast(^RaycastNode)node
	lua.pushnumber(L, lua.Number(rc.hitPoint.x))
	lua.pushnumber(L, lua.Number(rc.hitPoint.y))
	return 2
}

@(private="file")
lua_node_raycast_get_hit_normal :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != RaycastNode {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	rc := cast(^RaycastNode)node
	lua.pushnumber(L, lua.Number(rc.hitNormal.x))
	lua.pushnumber(L, lua.Number(rc.hitNormal.y))
	return 2
}

@(private="file")
lua_node_raycast_get_hit_fraction :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != RaycastNode {
		lua.pushnumber(L, 1)
		return 1
	}
	rc := cast(^RaycastNode)node
	lua.pushnumber(L, lua.Number(rc.hitFraction))
	return 1
}

@(private="file")
lua_node_raycast_get_hit_node :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != RaycastNode {
		lua.pushnil(L)
		return 1
	}
	rc := cast(^RaycastNode)node
	push_node_userdata(L, rc.hitNode)
	return 1
}

@(private="file")
lua_node_raycast_set_direction :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != RaycastNode do return 0
	dx := f32(lua.tonumber(L, 2))
	dy := f32(lua.tonumber(L, 3))
	rc := cast(^RaycastNode)node
	rc.direction = {dx, dy}
	return 0
}

@(private="file")
lua_node_raycast_set_length :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != RaycastNode do return 0
	lenVal := f32(lua.tonumber(L, 2))
	rc := cast(^RaycastNode)node
	rc.length = lenVal
	return 0
}

// ----------------------------------------------------------------------------
// Particle Emitter Methods
// ----------------------------------------------------------------------------

@(private="file")
lua_node_particle_start :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != ParticleEmitterNode do return 0
	pen := cast(^ParticleEmitterNode)node
	ParticleEmitterNode_Start(pen)
	return 0
}

@(private="file")
lua_node_particle_stop :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != ParticleEmitterNode do return 0
	pen := cast(^ParticleEmitterNode)node
	ParticleEmitterNode_Stop(pen)
	return 0
}

@(private="file")
lua_node_particle_is_emitting :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != ParticleEmitterNode {
		lua.pushboolean(L, false)
		return 1
	}
	pen := cast(^ParticleEmitterNode)node
	lua.pushboolean(L, b32(pen.emitter.emitting))
	return 1
}

@(private="file")
lua_node_particle_set_amount :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != ParticleEmitterNode do return 0
	amount := int(lua.tointeger(L, 2))
	pen := cast(^ParticleEmitterNode)node
	pen.emitter.amount = amount
	return 0
}

@(private="file")
lua_node_particle_set_lifetime :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != ParticleEmitterNode do return 0
	lifetime := f32(lua.tonumber(L, 2))
	pen := cast(^ParticleEmitterNode)node
	pen.emitter.lifetime = lifetime
	return 0
}

// ----------------------------------------------------------------------------
// TextureNode Methods
// ----------------------------------------------------------------------------

@(private="file")
lua_node_texture_get_size :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != TextureNode {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	tex := cast(^TextureNode)node
	lua.pushnumber(L, lua.Number(tex.size.x))
	lua.pushnumber(L, lua.Number(tex.size.y))
	return 2
}

@(private="file")
lua_node_texture_set_origin :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != TextureNode do return 0
	ox := f32(lua.tonumber(L, 2))
	oy := f32(lua.tonumber(L, 3))
	tex := cast(^TextureNode)node
	tex.origin = {ox, oy}
	return 0
}

@(private="file")
lua_node_texture_get_path :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != TextureNode {
		lua.pushstring(L, "")
		return 1
	}
	tex := cast(^TextureNode)node
	pathC := strings.clone_to_cstring(tex.filePath, context.temp_allocator)
	lua.pushstring(L, pathC)
	return 1
}

// ----------------------------------------------------------------------------
// AnimationPlayerNode Methods
// ----------------------------------------------------------------------------

@(private="file")
lua_node_animation_play :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AnimationPlayerNode do return 0
	apn := cast(^AnimationPlayerNode)node
	// animation_play([name [, blend_seconds]]): blend crossfades property tracks.
	name := string(lua.tostring(L, 2)) if lua.type(L, 2) == .STRING else ""
	blend := f32(lua.tonumber(L, 3)) if lua.type(L, 3) == .NUMBER else 0
	AnimationPlayerNode_Play(apn, name, blend)
	return 0
}

@(private="file")
lua_node_animation_stop :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AnimationPlayerNode do return 0
	apn := cast(^AnimationPlayerNode)node
	AnimationPlayerNode_Stop(apn)
	return 0
}

@(private="file")
lua_node_animation_pause :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AnimationPlayerNode do return 0
	apn := cast(^AnimationPlayerNode)node
	AnimationPlayerNode_Pause(apn)
	return 0
}

@(private="file")
lua_node_animation_resume :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AnimationPlayerNode do return 0
	apn := cast(^AnimationPlayerNode)node
	AnimationPlayerNode_Resume(apn)
	return 0
}

@(private="file")
lua_node_animation_reset :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AnimationPlayerNode do return 0
	apn := cast(^AnimationPlayerNode)node
	AnimationPlayerNode_Reset(apn)
	return 0
}

@(private="file")
lua_node_animation_set_fps :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AnimationPlayerNode do return 0
	fps := f32(lua.tonumber(L, 2))
	apn := cast(^AnimationPlayerNode)node
	AnimationPlayerNode_SetFPS(apn, fps)
	return 0
}

@(private="file")
lua_node_animation_get_current :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != AnimationPlayerNode {
		lua.pushstring(L, "")
		return 1
	}
	apn := cast(^AnimationPlayerNode)node
	nameStr := AnimationPlayerNode_GetAnimationName(apn)
	nameC := strings.clone_to_cstring(nameStr, context.temp_allocator)
	lua.pushstring(L, nameC)
	return 1
}

// ----------------------------------------------------------------------------
// TimerNode Methods
// ----------------------------------------------------------------------------

@(private="file")
lua_node_timer_start :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != TimerNode do return 0
	timer := cast(^TimerNode)node
	TimerNode_Start(timer)
	return 0
}

@(private="file")
lua_node_timer_stop :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != TimerNode do return 0
	timer := cast(^TimerNode)node
	timer.running = false
	return 0
}

@(private="file")
lua_node_timer_is_running :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != TimerNode {
		lua.pushboolean(L, false)
		return 1
	}
	timer := cast(^TimerNode)node
	lua.pushboolean(L, b32(timer.running))
	return 1
}

@(private="file")
lua_node_timer_get_elapsed :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != TimerNode {
		lua.pushnumber(L, 0)
		return 1
	}
	timer := cast(^TimerNode)node
	lua.pushnumber(L, lua.Number(time.duration_seconds(timer.elapsed)))
	return 1
}

@(private="file")
lua_node_timer_set_duration :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != TimerNode do return 0
	sec := f32(lua.tonumber(L, 2))
	timer := cast(^TimerNode)node
	if timer.setDuration != nil {
		timer->setDuration(sec)
	}
	return 0
}

@(private="file")
lua_node_timer_set_loop :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != TimerNode do return 0
	loop := lua.toboolean(L, 2)
	timer := cast(^TimerNode)node
	timer.loop = bool(loop)
	return 0
}

// ----------------------------------------------------------------------------
// Sound & Music Node Methods
// ----------------------------------------------------------------------------

@(private="file")
lua_node_sound_play :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != SoundNode do return 0
	soundNode := cast(^SoundNode)node
	SoundNode_Play(soundNode)
	return 0
}

@(private="file")
lua_node_sound_stop :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != SoundNode do return 0
	soundNode := cast(^SoundNode)node
	SoundNode_Stop(soundNode)
	return 0
}

@(private="file")
lua_node_sound_pause :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != SoundNode do return 0
	soundNode := cast(^SoundNode)node
	SoundNode_Pause(soundNode)
	return 0
}

@(private="file")
lua_node_sound_resume :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != SoundNode do return 0
	soundNode := cast(^SoundNode)node
	SoundNode_Resume(soundNode)
	return 0
}

@(private="file")
lua_node_music_play :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != MusicNode do return 0
	musicNode := cast(^MusicNode)node
	MusicNode_Play(musicNode)
	return 0
}

@(private="file")
lua_node_music_stop :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != MusicNode do return 0
	musicNode := cast(^MusicNode)node
	MusicNode_Stop(musicNode)
	return 0
}

@(private="file")
lua_node_music_pause :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != MusicNode do return 0
	musicNode := cast(^MusicNode)node
	MusicNode_Pause(musicNode)
	return 0
}

@(private="file")
lua_node_music_resume :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != MusicNode do return 0
	musicNode := cast(^MusicNode)node
	MusicNode_Resume(musicNode)
	return 0
}

// ----------------------------------------------------------------------------
// LDtk Node Methods
// ----------------------------------------------------------------------------

@(private="file")
lua_node_ldtk_get_level_identifier :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != LdtkLevelNode {
		lua.pushstring(L, "")
		return 1
	}
	ldtkNode := cast(^LdtkLevelNode)node
	idC := strings.clone_to_cstring(ldtkNode.levelIdentifier, context.temp_allocator)
	lua.pushstring(L, idC)
	return 1
}

// ----------------------------------------------------------------------------
// Camera Node Methods (when invoked on CameraNode userdata)
// ----------------------------------------------------------------------------

@(private="file")
lua_node_camera_set_zoom :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CameraNode do return 0
	zoom := f32(lua.tonumber(L, 2))
	CameraNode_SetZoom(cast(^CameraNode)node, zoom)
	return 0
}

@(private="file")
lua_node_camera_get_zoom :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CameraNode {
		lua.pushnumber(L, 1)
		return 1
	}
	cam := cast(^CameraNode)node
	lua.pushnumber(L, lua.Number(cam.targetZoom))
	return 1
}

@(private="file")
lua_node_camera_set_target :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	target, _ := to_node_userdata(L, 2)
	if !ok || node.typeId != CameraNode do return 0
	CameraNode_SetTarget(cast(^CameraNode)node, target)
	return 0
}

// --- camera targets (node methods take the camera at 1; Camera.* use the
// scene's current camera, args shifted by one) ---

// camera_target_opts reads { weight = n | weight_x, weight_y, radius,
// offset_x, offset_y, priority } at idx (absent = defaults).
@(private="file")
camera_target_opts :: proc(L: ^lua.State, node: ^Node, idx: c.int) -> CameraTarget {
	t := CameraTarget{node = node, position = node.globalPosition, influence = {1, 1}, radius = 50, enabled = true, prevPosition = node.globalPosition}
	if lua.type(L, idx) != .TABLE do return t
	num :: proc(L: ^lua.State, idx: c.int, key: cstring, def: f32) -> f32 {
		lua.getfield(L, idx, key)
		defer lua.pop(L, 1)
		return f32(lua.tonumber(L, -1)) if lua.type(L, -1) == .NUMBER else def
	}
	w := num(L, idx, "weight", 1)
	t.influence = {num(L, idx, "weight_x", w), num(L, idx, "weight_y", w)}
	t.radius = num(L, idx, "radius", 50)
	t.offset = {num(L, idx, "offset_x", 0), num(L, idx, "offset_y", 0)}
	t.priority = int(num(L, idx, "priority", 0))
	return t
}

@(private="file")
camera_arg :: proc(L: ^lua.State, isModule: bool) -> (^CameraNode, c.int) {
	if isModule do return get_current_camera(L), 1
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CameraNode do return nil, 2
	return cast(^CameraNode)node, 2
}

@(private="file")
camera_add_target_impl :: proc(L: ^lua.State, isModule: bool) -> c.int {
	cam, a := camera_arg(L, isModule)
	target, ok := to_node_userdata(L, a)
	if cam != nil && ok do CameraNode_AddTarget(cam, camera_target_opts(L, target, a + 1))
	return 0
}

@(private="file")
camera_remove_target_impl :: proc(L: ^lua.State, isModule: bool) -> c.int {
	cam, a := camera_arg(L, isModule)
	target, ok := to_node_userdata(L, a)
	if cam != nil && ok do CameraNode_RemoveTarget(cam, target)
	return 0
}

@(private="file")
camera_clear_targets_impl :: proc(L: ^lua.State, isModule: bool) -> c.int {
	if cam, _ := camera_arg(L, isModule); cam != nil {
		CameraNode_ClearTargets(cam)
		cam.followTarget = ""
	}
	return 0
}

@(private="file")
camera_get_target_impl :: proc(L: ^lua.State, isModule: bool) -> c.int {
	cam, _ := camera_arg(L, isModule)
	push_node_userdata(L, cam.target if cam != nil else nil)
	return 1
}

@(private="file")
camera_get_targets_impl :: proc(L: ^lua.State, isModule: bool) -> c.int {
	cam, _ := camera_arg(L, isModule)
	lua.newtable(L)
	if cam == nil do return 1
	n := 0
	if cam.followMode != .MultiTarget && cam.target != nil {
		push_node_userdata(L, cam.target)
		lua.rawseti(L, -2, 1)
		return 1
	}
	for t in cam.targets {
		if t.node == nil || !Node_IsAlive(t.node) do continue
		n += 1
		push_node_userdata(L, t.node)
		lua.rawseti(L, -2, lua.Integer(n))
	}
	return 1
}

@(private="file")
lua_node_camera_add_target :: proc "c" (L: ^lua.State) -> c.int {context = runtime.default_context(); return camera_add_target_impl(L, false)}
@(private="file")
lua_node_camera_remove_target :: proc "c" (L: ^lua.State) -> c.int {context = runtime.default_context(); return camera_remove_target_impl(L, false)}
@(private="file")
lua_node_camera_clear_targets :: proc "c" (L: ^lua.State) -> c.int {context = runtime.default_context(); return camera_clear_targets_impl(L, false)}
@(private="file")
lua_node_camera_get_target :: proc "c" (L: ^lua.State) -> c.int {context = runtime.default_context(); return camera_get_target_impl(L, false)}
@(private="file")
lua_node_camera_get_targets :: proc "c" (L: ^lua.State) -> c.int {context = runtime.default_context(); return camera_get_targets_impl(L, false)}
@(private="file")
lua_camera_add_target :: proc "c" (L: ^lua.State) -> c.int {context = runtime.default_context(); return camera_add_target_impl(L, true)}
@(private="file")
lua_camera_remove_target :: proc "c" (L: ^lua.State) -> c.int {context = runtime.default_context(); return camera_remove_target_impl(L, true)}
@(private="file")
lua_camera_clear_targets :: proc "c" (L: ^lua.State) -> c.int {context = runtime.default_context(); return camera_clear_targets_impl(L, true)}
@(private="file")
lua_camera_get_target :: proc "c" (L: ^lua.State) -> c.int {context = runtime.default_context(); return camera_get_target_impl(L, true)}
@(private="file")
lua_camera_get_targets :: proc "c" (L: ^lua.State) -> c.int {context = runtime.default_context(); return camera_get_targets_impl(L, true)}

// --- materials ---

// node:set_shader(path | nil): "builtin:flash" or a project .fs file.
@(private="file")
lua_node_set_shader :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	path := string(lua.tostring(L, 2)) if lua.type(L, 2) == .STRING else ""
	Material_SetShader(node, path)
	return 0
}

// node:set_shader_param(name, x [, y, z, w]) / (name, {r, g, b, a}) /
// (name, "textures/noise.png")
@(private="file")
lua_node_set_shader_param :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || lua.type(L, 2) != .STRING do return 0
	name := strings.clone(string(lua.tostring(L, 2)), context.temp_allocator)
	v: [4]f32
	#partial switch lua.type(L, 3) {
	case .STRING:
		Material_SetParam(node, name, {}, string(lua.tostring(L, 3)))
		return 0
	case .TABLE:
		for i in 0 ..< 4 {
			lua.rawgeti(L, 3, lua.Integer(i + 1))
			v[i] = f32(lua.tonumber(L, -1))
			lua.pop(L, 1)
		}
	case:
		for i in 0 ..< 4 do v[i] = f32(lua.tonumber(L, c.int(3 + i)))
	}
	Material_SetParam(node, name, v)
	return 0
}

// node:get_shader_param(name) -> x, y, z, w (or the texture path)
@(private="file")
lua_node_get_shader_param :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || lua.type(L, 2) != .STRING {
		lua.pushnil(L)
		return 1
	}
	v, tex, found := Material_GetParam(node, string(lua.tostring(L, 2)))
	if !found {
		lua.pushnil(L)
		return 1
	}
	if tex != "" {
		lua.pushstring(L, strings.clone_to_cstring(tex, context.temp_allocator))
		return 1
	}
	for i in 0 ..< 4 do lua.pushnumber(L, lua.Number(v[i]))
	return 4
}

// node:set_blend_mode("alpha" | "additive" | "multiply" | "add_colors" |
// "subtract_colors" | "premultiplied")
@(private="file")
lua_node_set_blend_mode :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	Node_EnsureMaterial(node).blend = Material_BlendParse(string(lua.tostring(L, 2)) if lua.type(L, 2) == .STRING else "alpha")
	return 0
}

@(private="file")
lua_node_camera_set_target_position :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CameraNode do return 0
	tx := f32(lua.tonumber(L, 2))
	ty := f32(lua.tonumber(L, 3))
	CameraNode_SetTargetPosition(cast(^CameraNode)node, {tx, ty})
	return 0
}

@(private="file")
lua_node_camera_shake :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CameraNode do return 0
	strength := f32(lua.tonumber(L, 2))
	dur := f32(lua.tonumber(L, 3)) if lua.gettop(L) >= 3 else 0.5
	CameraNode_Shake(cast(^CameraNode)node, strength, dur)
	return 0
}

@(private="file")
lua_node_camera_stop_shake :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CameraNode do return 0
	CameraNode_StopShake(cast(^CameraNode)node)
	return 0
}

@(private="file")
lua_node_camera_is_shaking :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CameraNode {
		lua.pushboolean(L, false)
		return 1
	}
	lua.pushboolean(L, b32(CameraNode_IsShaking(cast(^CameraNode)node)))
	return 1
}

@(private="file")
lua_node_camera_set_limits :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CameraNode do return 0
	l := f32(lua.tonumber(L, 2))
	r := f32(lua.tonumber(L, 3))
	t := f32(lua.tonumber(L, 4))
	b := f32(lua.tonumber(L, 5))
	CameraNode_SetLimits(cast(^CameraNode)node, l, r, t, b)
	return 0
}

@(private="file")
lua_node_camera_clear_limits :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != CameraNode do return 0
	CameraNode_ClearLimits(cast(^CameraNode)node)
	return 0
}

// ----------------------------------------------------------------------------
// Global Camera Table (Engine.Camera)
// ----------------------------------------------------------------------------

@(private="file")
get_current_camera :: proc(L: ^lua.State) -> ^CameraNode {
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || sm.game.sceneManager.currentScene == nil do return nil
	return sm.game.sceneManager.currentScene.camera
}

@(private="file")
lua_camera_get_target_position :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cam := get_current_camera(L)
	if cam == nil {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	lua.pushnumber(L, lua.Number(cam.targetPosition.x))
	lua.pushnumber(L, lua.Number(cam.targetPosition.y))
	return 2
}

@(private="file")
lua_camera_set_target_position :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cam := get_current_camera(L)
	if cam == nil do return 0
	x := f32(lua.tonumber(L, 1))
	y := f32(lua.tonumber(L, 2))
	CameraNode_SetTargetPosition(cam, {x, y})
	return 0
}

@(private="file")
lua_camera_set_target :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cam := get_current_camera(L)
	target, _ := to_node_userdata(L, 1)
	if cam != nil {
		CameraNode_SetTarget(cam, target)
	}
	return 0
}

@(private="file")
lua_camera_get_zoom :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cam := get_current_camera(L)
	if cam == nil {
		lua.pushnumber(L, 1)
		return 1
	}
	lua.pushnumber(L, lua.Number(cam.targetZoom))
	return 1
}

@(private="file")
lua_camera_set_zoom :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cam := get_current_camera(L)
	if cam != nil {
		zoom := f32(lua.tonumber(L, 1))
		CameraNode_SetZoom(cam, zoom)
	}
	return 0
}

@(private="file")
lua_camera_get_offset :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cam := get_current_camera(L)
	if cam == nil {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	lua.pushnumber(L, lua.Number(cam.offset.x))
	lua.pushnumber(L, lua.Number(cam.offset.y))
	return 2
}

@(private="file")
lua_camera_set_offset :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cam := get_current_camera(L)
	if cam != nil {
		ox := f32(lua.tonumber(L, 1))
		oy := f32(lua.tonumber(L, 2))
		CameraNode_SetOffset(cam, {ox, oy})
	}
	return 0
}

@(private="file")
lua_camera_get_rotation :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cam := get_current_camera(L)
	if cam == nil {
		lua.pushnumber(L, 0)
		return 1
	}
	lua.pushnumber(L, lua.Number(cam.rotation))
	return 1
}

@(private="file")
lua_camera_set_rotation :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cam := get_current_camera(L)
	if cam != nil {
		deg := f32(lua.tonumber(L, 1))
		CameraNode_SetRotation(cam, deg)
	}
	return 0
}

@(private="file")
lua_camera_shake :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cam := get_current_camera(L)
	if cam != nil {
		strength := f32(lua.tonumber(L, 1))
		dur := f32(lua.tonumber(L, 2)) if lua.gettop(L) >= 2 else 0.5
		CameraNode_Shake(cam, strength, dur)
	}
	return 0
}

@(private="file")
lua_camera_stop_shake :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cam := get_current_camera(L)
	if cam != nil {
		CameraNode_StopShake(cam)
	}
	return 0
}

@(private="file")
lua_camera_is_shaking :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cam := get_current_camera(L)
	if cam == nil {
		lua.pushboolean(L, false)
		return 1
	}
	lua.pushboolean(L, b32(CameraNode_IsShaking(cam)))
	return 1
}

@(private="file")
lua_camera_set_limits :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cam := get_current_camera(L)
	if cam != nil {
		l := f32(lua.tonumber(L, 1))
		r := f32(lua.tonumber(L, 2))
		t := f32(lua.tonumber(L, 3))
		b := f32(lua.tonumber(L, 4))
		CameraNode_SetLimits(cam, l, r, t, b)
	}
	return 0
}

@(private="file")
lua_camera_clear_limits :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cam := get_current_camera(L)
	if cam != nil {
		CameraNode_ClearLimits(cam)
	}
	return 0
}

@(private="file")
lua_camera_screen_to_world :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cam := get_current_camera(L)
	sx := f32(lua.tonumber(L, 1))
	sy := f32(lua.tonumber(L, 2))
	if cam == nil {
		lua.pushnumber(L, lua.Number(sx))
		lua.pushnumber(L, lua.Number(sy))
		return 2
	}
	wPos := CameraNode_ScreenToWorld(cam, {sx, sy})
	lua.pushnumber(L, lua.Number(wPos.x))
	lua.pushnumber(L, lua.Number(wPos.y))
	return 2
}

@(private="file")
lua_camera_world_to_screen :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cam := get_current_camera(L)
	wx := f32(lua.tonumber(L, 1))
	wy := f32(lua.tonumber(L, 2))
	if cam == nil {
		lua.pushnumber(L, lua.Number(wx))
		lua.pushnumber(L, lua.Number(wy))
		return 2
	}
	sPos := CameraNode_WorldToScreen(cam, {wx, wy})
	lua.pushnumber(L, lua.Number(sPos.x))
	lua.pushnumber(L, lua.Number(sPos.y))
	return 2
}

@(private="file")
lua_camera_get_visible_world_bounds :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	cam := get_current_camera(L)
	if cam == nil {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 1280)
		lua.pushnumber(L, 720)
		return 4
	}
	bounds := CameraNode_GetVisibleWorldBounds(cam)
	lua.pushnumber(L, lua.Number(bounds.x))
	lua.pushnumber(L, lua.Number(bounds.y))
	lua.pushnumber(L, lua.Number(bounds.width))
	lua.pushnumber(L, lua.Number(bounds.height))
	return 4
}

// ----------------------------------------------------------------------------
// Global Physics Table (Engine.Physics)
// ----------------------------------------------------------------------------

WorldRaycastQuery :: struct {
	hit:      bool,
	point:    [2]f32,
	normal:   [2]f32,
	fraction: f32,
	hitNode:  ^Node,
}

@(private="file")
world_raycast_callback :: proc "c" (shapeId: b2.ShapeId, point: b2.Vec2, normal: b2.Vec2, fraction: f32, ctx: rawptr) -> f32 {
	if ctx == nil || !b2.Shape_IsValid(shapeId) do return 1.0
	res := cast(^WorldRaycastQuery)ctx
	if b2.Shape_IsSensor(shapeId) do return -1.0

	bodyId := b2.Shape_GetBody(shapeId)
	hitNode: ^Node = nil
	if b2.Body_IsValid(bodyId) {
		hitNode = cast(^Node)b2.Body_GetUserData(bodyId)
	}

	res.hit = true
	res.point = point
	res.normal = normal
	res.fraction = fraction
	res.hitNode = hitNode
	return fraction
}

@(private="file")
lua_physics_get_gravity :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	lua.pushnumber(L, lua.Number(sm.game.physicsWorld.gravity.x))
	lua.pushnumber(L, lua.Number(sm.game.physicsWorld.gravity.y))
	return 2
}

@(private="file")
lua_physics_set_gravity :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil do return 0
	gx := f32(lua.tonumber(L, 1))
	gy := f32(lua.tonumber(L, 2))
	sm.game.physicsWorld.gravity = {gx, gy}
	PhysicsWorld_SyncSettings(&sm.game.physicsWorld)
	return 0
}

@(private="file")
lua_physics_is_paused :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil {
		lua.pushboolean(L, false)
		return 1
	}
	lua.pushboolean(L, b32(sm.game.physicsWorld.paused))
	return 1
}

@(private="file")
lua_physics_set_paused :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil do return 0
	paused := lua.toboolean(L, 1)
	sm.game.physicsWorld.paused = bool(paused)
	return 0
}

@(private="file")
lua_physics_raycast :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || !b2.World_IsValid(sm.game.physicsWorld.worldId) {
		lua.pushnil(L)
		return 1
	}

	startX := f32(lua.tonumber(L, 1))
	startY := f32(lua.tonumber(L, 2))
	endX := f32(lua.tonumber(L, 3))
	endY := f32(lua.tonumber(L, 4))

	origin := [2]f32{startX, startY}
	translation := [2]f32{endX - startX, endY - startY}

	query := WorldRaycastQuery{hit = false, fraction = 1.0}
	filter := b2.DefaultQueryFilter()
	_ = b2.World_CastRay(sm.game.physicsWorld.worldId, origin, translation, filter, world_raycast_callback, &query)

	if !query.hit {
		lua.pushnil(L)
		return 1
	}

	lua.newtable(L)
	lua.pushboolean(L, true)
	lua.setfield(L, -2, "hit")
	lua.pushnumber(L, lua.Number(query.point.x))
	lua.setfield(L, -2, "point_x")
	lua.pushnumber(L, lua.Number(query.point.y))
	lua.setfield(L, -2, "point_y")
	lua.pushnumber(L, lua.Number(query.normal.x))
	lua.setfield(L, -2, "normal_x")
	lua.pushnumber(L, lua.Number(query.normal.y))
	lua.setfield(L, -2, "normal_y")
	lua.pushnumber(L, lua.Number(query.fraction))
	lua.setfield(L, -2, "fraction")
	if query.hitNode != nil {
		push_node_userdata(L, query.hitNode)
		lua.setfield(L, -2, "node")
	}
	return 1
}

// ----------------------------------------------------------------------------
// Global Engine Table (Engine)
// ----------------------------------------------------------------------------

@(private="file")
lua_engine_get_fps :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	fps := rl.GetFPS() if rl.IsWindowReady() else 60
	lua.pushnumber(L, lua.Number(fps))
	return 1
}

@(private="file")
lua_engine_get_delta_time :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	dt := rl.GetFrameTime() if rl.IsWindowReady() else 0.01667
	lua.pushnumber(L, lua.Number(dt))
	return 1
}

@(private="file")
lua_engine_get_time :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	t := rl.GetTime() if rl.IsWindowReady() else 0
	lua.pushnumber(L, lua.Number(t))
	return 1
}

@(private="file")
lua_engine_get_window_size :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	w := rl.GetScreenWidth() if rl.IsWindowReady() else 1280
	h := rl.GetScreenHeight() if rl.IsWindowReady() else 720
	lua.pushnumber(L, lua.Number(w))
	lua.pushnumber(L, lua.Number(h))
	return 2
}

@(private="file")
lua_engine_get_virtual_size :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	vw: f32 = 1280
	vh: f32 = 720
	if sm != nil && sm.game != nil && sm.game.virtualSize.x > 0 {
		vw = sm.game.virtualSize.x
		vh = sm.game.virtualSize.y
	}
	lua.pushnumber(L, lua.Number(vw))
	lua.pushnumber(L, lua.Number(vh))
	return 2
}

// ----------------------------------------------------------------------------
// Input Bindings (Engine.Input)
// ----------------------------------------------------------------------------

@(private="file")
parse_keyboard_key :: proc(name: string) -> (rl.KeyboardKey, bool) {
	upper := strings.to_upper(name, context.temp_allocator)
	switch upper {
	case "SPACE": return .SPACE, true
	case "ENTER", "RETURN": return .ENTER, true
	case "ESCAPE", "ESC": return .ESCAPE, true
	case "UP": return .UP, true
	case "DOWN": return .DOWN, true
	case "LEFT": return .LEFT, true
	case "RIGHT": return .RIGHT, true
	case "W": return .W, true
	case "A": return .A, true
	case "S": return .S, true
	case "D": return .D, true
	case "E": return .E, true
	case "Q": return .Q, true
	case "R": return .R, true
	case "F": return .F, true
	case "TAB": return .TAB, true
	case "LEFT_SHIFT", "SHIFT": return .LEFT_SHIFT, true
	case "LEFT_CONTROL", "CTRL": return .LEFT_CONTROL, true
	}
	return .KEY_NULL, false
}

@(private="file")
parse_mouse_button :: proc(name: string) -> (rl.MouseButton, bool) {
	upper := strings.to_upper(name, context.temp_allocator)
	switch upper {
	case "LEFT", "0": return .LEFT, true
	case "RIGHT", "1": return .RIGHT, true
	case "MIDDLE", "2": return .MIDDLE, true
	case "SIDE", "3": return .SIDE, true
	case "EXTRA", "4": return .EXTRA, true
	case "FORWARD", "5": return .FORWARD, true
	case "BACK", "6": return .BACK, true
	}
	return .LEFT, false
}

@(private="file")
lua_input_is_action_pressed :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	actStr := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if actStr == nil || sm == nil || sm.game == nil {
		lua.pushboolean(L, false)
		return 1
	}
	st, _ := Input_ActionStateByName(&sm.game.input, string(actStr))
	lua.pushboolean(L, b32(st.pressed))
	return 1
}

@(private="file")
lua_input_is_action_down :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	actStr := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if actStr == nil || sm == nil || sm.game == nil {
		lua.pushboolean(L, false)
		return 1
	}
	st, _ := Input_ActionStateByName(&sm.game.input, string(actStr))
	lua.pushboolean(L, b32(st.down))
	return 1
}

@(private="file")
lua_input_is_action_released :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	actStr := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if actStr == nil || sm == nil || sm.game == nil {
		lua.pushboolean(L, false)
		return 1
	}
	st, _ := Input_ActionStateByName(&sm.game.input, string(actStr))
	lua.pushboolean(L, b32(st.released))
	return 1
}

@(private="file")
lua_input_get_axis :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	negStr := lua.tostring(L, 1)
	posStr := lua.tostring(L, 2)
	sm := get_script_manager(L)
	if negStr == nil || posStr == nil || sm == nil || sm.game == nil {
		lua.pushnumber(L, 0)
		return 1
	}
	neg, _ := Input_ActionStateByName(&sm.game.input, string(negStr))
	pos, _ := Input_ActionStateByName(&sm.game.input, string(posStr))
	lua.pushnumber(L, lua.Number(pos.value - neg.value))
	return 1
}

@(private="file")
lua_input_get_vector :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil {
		lua.pushnumber(L, 0)
		lua.pushnumber(L, 0)
		return 2
	}
	lStr := lua.tostring(L, 1)
	rStr := lua.tostring(L, 2)
	uStr := lua.tostring(L, 3)
	dStr := lua.tostring(L, 4)

	inp := &sm.game.input
	l, _ := Input_ActionStateByName(inp, string(lStr) if lStr != nil else "move_left")
	r, _ := Input_ActionStateByName(inp, string(rStr) if rStr != nil else "move_right")
	u, _ := Input_ActionStateByName(inp, string(uStr) if uStr != nil else "move_up")
	d, _ := Input_ActionStateByName(inp, string(dStr) if dStr != nil else "move_down")
	vec := [2]f32{r.value - l.value, d.value - u.value}
	if l2 := vec.x * vec.x + vec.y * vec.y; l2 > 1 {
		inv := 1 / math.sqrt(l2)
		vec *= inv
	}
	lua.pushnumber(L, lua.Number(vec.x))
	lua.pushnumber(L, lua.Number(vec.y))
	return 2
}

@(private="file")
lua_input_is_key_down :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	keyStr := lua.tostring(L, 1)
	if keyStr == nil {
		lua.pushboolean(L, false)
		return 1
	}
	key, ok := parse_keyboard_key(string(keyStr))
	if !ok {
		lua.pushboolean(L, false)
		return 1
	}
	sm := get_script_manager(L)
	if sm != nil && sm.game != nil && sm.game.input.useSimulatedInput {
		isDown := sm.game.input.simulatedKeysDown[key]
		lua.pushboolean(L, b32(isDown))
		return 1
	}
	isDown := rl.IsWindowReady() && rl.IsKeyDown(key)
	lua.pushboolean(L, b32(isDown))
	return 1
}

@(private="file")
lua_input_is_key_pressed :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	keyStr := lua.tostring(L, 1)
	if keyStr == nil {
		lua.pushboolean(L, false)
		return 1
	}
	key, ok := parse_keyboard_key(string(keyStr))
	if !ok {
		lua.pushboolean(L, false)
		return 1
	}
	isPressed := rl.IsWindowReady() && rl.IsKeyPressed(key)
	lua.pushboolean(L, b32(isPressed))
	return 1
}

@(private="file")
lua_input_is_key_released :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	keyStr := lua.tostring(L, 1)
	if keyStr == nil {
		lua.pushboolean(L, false)
		return 1
	}
	key, ok := parse_keyboard_key(string(keyStr))
	if !ok {
		lua.pushboolean(L, false)
		return 1
	}
	isRel := rl.IsWindowReady() && rl.IsKeyReleased(key)
	lua.pushboolean(L, b32(isRel))
	return 1
}

@(private="file")
lua_input_is_mouse_button_pressed :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	btnStr := lua.tostring(L, 1)
	btn, ok := parse_mouse_button(string(btnStr) if btnStr != nil else "LEFT")
	if !ok {
		lua.pushboolean(L, false)
		return 1
	}
	isPressed := rl.IsWindowReady() && rl.IsMouseButtonPressed(btn)
	lua.pushboolean(L, b32(isPressed))
	return 1
}

@(private="file")
lua_input_is_mouse_button_down :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	btnStr := lua.tostring(L, 1)
	btn, ok := parse_mouse_button(string(btnStr) if btnStr != nil else "LEFT")
	if !ok {
		lua.pushboolean(L, false)
		return 1
	}
	isDown := rl.IsWindowReady() && rl.IsMouseButtonDown(btn)
	lua.pushboolean(L, b32(isDown))
	return 1
}

@(private="file")
lua_input_is_mouse_button_released :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	btnStr := lua.tostring(L, 1)
	btn, ok := parse_mouse_button(string(btnStr) if btnStr != nil else "LEFT")
	if !ok {
		lua.pushboolean(L, false)
		return 1
	}
	isRel := rl.IsWindowReady() && rl.IsMouseButtonReleased(btn)
	lua.pushboolean(L, b32(isRel))
	return 1
}

@(private="file")
lua_input_get_mouse_position :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	if rl.IsWindowReady() {
		mPos := rl.GetMousePosition()
		lua.pushnumber(L, lua.Number(mPos.x))
		lua.pushnumber(L, lua.Number(mPos.y))
		return 2
	}
	lua.pushnumber(L, 0)
	lua.pushnumber(L, 0)
	return 2
}

@(private="file")
lua_input_get_mouse_wheel_move :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	move := rl.GetMouseWheelMove() if rl.IsWindowReady() else 0
	lua.pushnumber(L, lua.Number(move))
	return 1
}

// ----------------------------------------------------------------------------
// Audio Bindings (Engine.Audio)
// ----------------------------------------------------------------------------

@(private="file")
lua_audio_play_sound :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	pathC := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if pathC == nil || sm == nil || sm.game == nil do return 0

	path := string(pathC)
	if rl.IsAudioDeviceReady() {
		sound, ok := sm.game.resourceManager->loadAudioSound(path)
		if ok && sound != nil {
			// Audio.play_sound(path [, volume [, pitch]]): one-shots overlap (4 voices).
			vol := f32(lua.tonumber(L, 2)) if lua.gettop(L) >= 2 else 1
			pitch := f32(lua.tonumber(L, 3)) if lua.gettop(L) >= 3 else 1
			Audio_PlayVoice(sound, 4, vol * sm.game.sfxVolume, pitch)
		}
	}
	return 0
}

// Audio.play_sound_at(path, x, y [, volume]): a one-shot heard from where it
// happens (distance and pan from the listener).
@(private="file")
lua_audio_play_sound_at :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	pathC := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if pathC == nil || sm == nil || sm.game == nil || !rl.IsAudioDeviceReady() do return 0
	sound, ok := sm.game.resourceManager->loadAudioSound(string(pathC))
	if !ok || sound == nil do return 0
	pos := [2]f32{f32(lua.tonumber(L, 2)), f32(lua.tonumber(L, 3))}
	vol := f32(lua.tonumber(L, 4)) if lua.gettop(L) >= 4 else 1
	pan: f32 = 0.5
	if listener, has := Audio_ListenerPosition(&sm.game.gameContext); has {
		v, p := Audio_Spatialize(pos, listener, 100, 900, 450)
		vol *= v
		pan = p
	}
	Audio_PlayVoice(sound, 4, vol * sm.game.sfxVolume, 1, pan)
	return 0
}

@(private="file")
bus_arg :: proc(L: ^lua.State, idx: c.int) -> (Audio_Bus, bool) {
	s := lua.tostring(L, idx)
	if s == nil do return .Master, false
	switch string(s) {
	case "master": return .Master, true
	case "music":  return .Music, true
	case "sfx":    return .Sfx, true
	}
	return .Master, false
}

// Audio.set_bus_volume("master"|"music"|"sfx", v)
@(private="file")
lua_audio_set_bus_volume :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	bus, ok := bus_arg(L, 1)
	if ok && sm != nil && sm.game != nil do Game_SetBusVolume(sm.game, bus, f32(lua.tonumber(L, 2)))
	return 0
}

@(private="file")
lua_audio_get_bus_volume :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	bus, ok := bus_arg(L, 1)
	v: f32 = 1
	if ok && sm != nil && sm.game != nil {
		switch bus {
		case .Master: v = sm.game.masterVolume
		case .Music:  v = sm.game.musicVolume
		case .Sfx:    v = sm.game.sfxVolume
		}
	}
	lua.pushnumber(L, lua.Number(v))
	return 1
}

// Audio.set_lowpass(hz): a low-pass on the whole mix (0 = off).
@(private="file")
lua_audio_set_lowpass :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	Audio_SetLowpass(f32(lua.tonumber(L, 1)))
	return 0
}

// Audio.set_reverb(mix [, size]): reverb on the whole mix (mix 0 = off).
@(private="file")
lua_audio_set_reverb :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	Audio_SetReverb(f32(lua.tonumber(L, 1)), f32(lua.tonumber(L, 2)) if lua.gettop(L) >= 2 else 0.5)
	return 0
}

// Audio.set_listener(node | nil): where positional sounds are heard from.
@(private="file")
lua_audio_set_listener :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	Audio_SetListener(node if ok else nil)
	return 0
}

// Audio.crossfade(fromMusicNode, toMusicNode, seconds)
@(private="file")
lua_audio_crossfade :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	from, fok := to_node_userdata(L, 1)
	to, tok := to_node_userdata(L, 2)
	a := cast(^MusicNode)from if fok && from.typeId == MusicNode else nil
	b := cast(^MusicNode)to if tok && to.typeId == MusicNode else nil
	MusicNode_Crossfade(a, b, f32(lua.tonumber(L, 3)))
	return 0
}

// node:music_fade(volume, seconds [, stop_at_end])
@(private="file")
lua_node_music_fade :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != MusicNode do return 0
	MusicNode_FadeTo(cast(^MusicNode)node, f32(lua.tonumber(L, 2)), f32(lua.tonumber(L, 3)), bool(lua.toboolean(L, 4)))
	return 0
}

@(private="file")
lua_audio_play_music :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	pathC := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if pathC == nil || sm == nil || sm.game == nil do return 0

	path := string(pathC)
	if rl.IsWindowReady() {
		music, ok := sm.game.resourceManager->loadAudioMusic(path)
		if ok && music != nil {
			rl.PlayMusicStream(music.music)
		}
	}
	return 0
}

@(private="file")
lua_audio_stop_music :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	pathC := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if pathC == nil || sm == nil || sm.game == nil do return 0
	path := string(pathC)
	if rl.IsWindowReady() {
		music, ok := sm.game.resourceManager->loadAudioMusic(path)
		if ok && music != nil {
			rl.StopMusicStream(music.music)
		}
	}
	return 0
}

@(private="file")
lua_audio_pause_music :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	pathC := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if pathC == nil || sm == nil || sm.game == nil do return 0
	path := string(pathC)
	if rl.IsWindowReady() {
		music, ok := sm.game.resourceManager->loadAudioMusic(path)
		if ok && music != nil {
			rl.PauseMusicStream(music.music)
		}
	}
	return 0
}

@(private="file")
lua_audio_resume_music :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	pathC := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if pathC == nil || sm == nil || sm.game == nil do return 0
	path := string(pathC)
	if rl.IsWindowReady() {
		music, ok := sm.game.resourceManager->loadAudioMusic(path)
		if ok && music != nil {
			rl.ResumeMusicStream(music.music)
		}
	}
	return 0
}

@(private="file")
lua_audio_is_music_playing :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	pathC := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if pathC == nil || sm == nil || sm.game == nil {
		lua.pushboolean(L, false)
		return 1
	}
	path := string(pathC)
	if rl.IsWindowReady() {
		music, ok := sm.game.resourceManager->loadAudioMusic(path)
		if ok && music != nil {
			isPlaying := rl.IsMusicStreamPlaying(music.music)
			lua.pushboolean(L, b32(isPlaying))
			return 1
		}
	}
	lua.pushboolean(L, false)
	return 1
}

@(private="file")
lua_audio_set_music_volume :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	pathC := lua.tostring(L, 1)
	vol := f32(lua.tonumber(L, 2))
	sm := get_script_manager(L)
	if pathC == nil || sm == nil || sm.game == nil do return 0
	path := string(pathC)
	if rl.IsWindowReady() {
		music, ok := sm.game.resourceManager->loadAudioMusic(path)
		if ok && music != nil {
			rl.SetMusicVolume(music.music, vol * sm.game.musicVolume)
		}
	}
	return 0
}

@(private="file")
lua_audio_set_master_volume :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	vol := f32(lua.tonumber(L, 1))
	if rl.IsWindowReady() {
		rl.SetMasterVolume(vol)
	}
	return 0
}

// ----------------------------------------------------------------------------
// Scene Bindings (Engine.Scene)
// ----------------------------------------------------------------------------

// Scene.set_ambient(r, g, b [, a]) (0..1): the light map's base colour.
@(private="file")
lua_scene_set_ambient :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || sm.game.sceneManager.currentScene == nil do return 0
	a := f32(lua.tonumber(L, 4)) if lua.type(L, 4) == .NUMBER else 1
	ch :: proc(v: f32) -> u8 {return u8(clamp(v, 0, 1) * 255 + 0.5)}
	sm.game.sceneManager.currentScene.ambient = {ch(f32(lua.tonumber(L, 1))), ch(f32(lua.tonumber(L, 2))), ch(f32(lua.tonumber(L, 3))), ch(a)}
	return 0
}

@(private="file")
lua_scene_get_ambient :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	c := rl.Color{255, 255, 255, 255}
	if sm != nil && sm.game != nil && sm.game.sceneManager.currentScene != nil && sm.game.sceneManager.currentScene.ambient != {} {
		c = sm.game.sceneManager.currentScene.ambient
	}
	for v in ([4]u8{c.r, c.g, c.b, c.a}) do lua.pushnumber(L, lua.Number(f32(v) / 255))
	return 4
}

@(private="file")
light_arg :: proc(L: ^lua.State) -> ^LightNode {
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != LightNode do return nil
	return cast(^LightNode)node
}

// light:light_set_color(r, g, b) (0..1)
@(private="file")
lua_light_set_color :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	if l := light_arg(L); l != nil {
		ch :: proc(v: f32) -> u8 {return u8(clamp(v, 0, 1) * 255 + 0.5)}
		l.color = {ch(f32(lua.tonumber(L, 2))), ch(f32(lua.tonumber(L, 3))), ch(f32(lua.tonumber(L, 4))), 255}
	}
	return 0
}

@(private="file")
lua_light_set_energy :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	if l := light_arg(L); l != nil do l.energy = max(f32(lua.tonumber(L, 2)), 0)
	return 0
}

@(private="file")
lua_light_set_radius :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	if l := light_arg(L); l != nil do l.radius = max(f32(lua.tonumber(L, 2)), 0)
	return 0
}

@(private="file")
lua_light_get_energy :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	l := light_arg(L)
	lua.pushnumber(L, lua.Number(l.energy if l != nil else 0))
	return 1
}

// --- StateMachineNode: sm_set / sm_get / sm_trigger / sm_travel / sm_state / sm_previous / sm_time / sm_start / sm_stop

@(private="file")
sm_arg :: proc(L: ^lua.State) -> ^StateMachineNode {
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != StateMachineNode do return nil
	return cast(^StateMachineNode)node
}

@(private="file")
sm_ctx :: proc(L: ^lua.State) -> ^GameContext {
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil do return nil
	return &sm.game.gameContext
}

// machine:sm_set(param, value) (number or boolean)
@(private="file")
lua_sm_set :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := sm_arg(L)
	name := lua.tostring(L, 2)
	if sm == nil || name == nil do return 0
	v: f32
	if lua.type(L, 3) == .BOOLEAN do v = 1 if lua.toboolean(L, 3) else 0
	else do v = f32(lua.tonumber(L, 3))
	StateMachine_SetParam(sm, string(name), v)
	return 0
}

// machine:sm_get(param) -> number
@(private="file")
lua_sm_get :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := sm_arg(L)
	name := lua.tostring(L, 2)
	lua.pushnumber(L, lua.Number(StateMachine_GetParam(sm, string(name)) if sm != nil && name != nil else 0))
	return 1
}

// machine:sm_trigger(name): sets a trigger, consumed by the transition it fires
@(private="file")
lua_sm_trigger :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := sm_arg(L)
	name := lua.tostring(L, 2)
	if sm != nil && name != nil do StateMachine_SetParam(sm, string(name), 1)
	return 0
}

// machine:sm_travel(state [, blend]) -> bool: switch now, no conditions
@(private="file")
lua_sm_travel :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := sm_arg(L)
	name := lua.tostring(L, 2)
	ok := false
	if sm != nil && name != nil do ok = StateMachine_Travel(sm, string(name), f32(lua.tonumber(L, 3)) if lua.gettop(L) >= 3 else 0, sm_ctx(L))
	lua.pushboolean(L, b32(ok))
	return 1
}

@(private="file")
lua_sm_state :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := sm_arg(L)
	lua.pushstring(L, strings.clone_to_cstring(StateMachine_CurrentName(sm) if sm != nil else "", context.temp_allocator))
	return 1
}

@(private="file")
lua_sm_previous :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := sm_arg(L)
	lua.pushstring(L, strings.clone_to_cstring(StateMachine_PreviousName(sm) if sm != nil else "", context.temp_allocator))
	return 1
}

@(private="file")
lua_sm_time :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := sm_arg(L)
	lua.pushnumber(L, lua.Number(sm.timeInState if sm != nil else 0))
	return 1
}

// machine:sm_start([state])
@(private="file")
lua_sm_start :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := sm_arg(L)
	if sm == nil do return 0
	name := lua.tostring(L, 2) if lua.gettop(L) >= 2 else nil
	StateMachine_Start(sm, string(name) if name != nil else "", sm_ctx(L))
	return 0
}

@(private="file")
lua_sm_stop :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	if sm := sm_arg(L); sm != nil do StateMachine_Stop(sm)
	return 0
}

// --- node:set_property / get_property: any Inspector property by path -------

// node:set_property(path, value...): numbers, booleans, {x, y} / x, y,
// {r, g, b[, a]} colours (0..1), enum names, strings.
@(private="file")
lua_node_set_property :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	name := lua.tostring(L, 2)
	if !ok || name == nil do return 0
	p, found := Node_FindProperty(node, string(name))
	if !found {
		lua.L_error(L, "set_property: %s has no property '%s'", strings.clone_to_cstring(node.name, context.temp_allocator), name)
		return 0
	}
	num :: proc(L: ^lua.State, i: c.int) -> f32 {return f32(lua.tonumber(L, i))}
	tbl :: proc(L: ^lua.State, k: lua.Integer) -> f32 {
		lua.rawgeti(L, 3, k)
		defer lua.pop(L, 1)
		return f32(lua.tonumber(L, -1))
	}
	switch p.kind {
	case .Float: Property_SetFloat(p, num(L, 3))
	case .Int:   Property_SetInt(p, i64(lua.tointeger(L, 3)))
	case .Bool:  (^bool)(p.ptr)^ = bool(lua.toboolean(L, 3))
	case .Vec2:
		v: [2]f32
		if lua.type(L, 3) == .TABLE do v = {tbl(L, 1), tbl(L, 2)}
		else do v = {num(L, 3), num(L, 4)}
		(^[2]f32)(p.ptr)^ = v
	case .Color:
		ch :: proc(v: f32) -> u8 {return u8(clamp(v, 0, 1) * 255 + 0.5)}
		if lua.type(L, 3) == .TABLE {
			a: f32 = 1
			lua.rawgeti(L, 3, 4)
			if lua.type(L, -1) == .NUMBER do a = f32(lua.tonumber(L, -1))
			lua.pop(L, 1)
			(^rl.Color)(p.ptr)^ = {ch(tbl(L, 1)), ch(tbl(L, 2)), ch(tbl(L, 3)), ch(a)}
		}
	case .Enum:
		if s := lua.tostring(L, 3); s != nil {
			for n, i in Property_EnumNames(p) do if strings.equal_fold(n, string(s)) do Property_SetEnumIndex(p, i)
		}
	case .Bit_Set:
	case .String:
		if s := lua.tostring(L, 3); s != nil do Property_SetString(node, p, string(s))
	}
	return 0
}

// node:get_property(path) -> value (vectors and colours as tables)
@(private="file")
lua_node_get_property :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	name := lua.tostring(L, 2)
	if !ok || name == nil {lua.pushnil(L); return 1}
	p, found := Node_FindProperty(node, string(name))
	if !found {lua.pushnil(L); return 1}
	switch p.kind {
	case .Float: lua.pushnumber(L, lua.Number(Property_GetFloat(p)))
	case .Int:   lua.pushinteger(L, lua.Integer(Property_GetInt(p)))
	case .Bool:  lua.pushboolean(L, b32((^bool)(p.ptr)^))
	case .Vec2:
		v := (^[2]f32)(p.ptr)^
		lua.createtable(L, 2, 0)
		lua.pushnumber(L, lua.Number(v.x)); lua.rawseti(L, -2, 1)
		lua.pushnumber(L, lua.Number(v.y)); lua.rawseti(L, -2, 2)
	case .Color:
		col := (^rl.Color)(p.ptr)^
		lua.createtable(L, 4, 0)
		for v, i in ([4]u8{col.r, col.g, col.b, col.a}) {
			lua.pushnumber(L, lua.Number(f32(v) / 255))
			lua.rawseti(L, -2, lua.Integer(i + 1))
		}
	case .Enum:
		names := Property_EnumNames(p)
		i := Property_GetEnumIndex(p)
		lua.pushstring(L, strings.clone_to_cstring(names[i] if i < len(names) else "", context.temp_allocator))
	case .Bit_Set: lua.pushnil(L)
	case .String: lua.pushstring(L, strings.clone_to_cstring((^string)(p.ptr)^, context.temp_allocator))
	}
	return 1
}

// --- collision layers by name -------------------------------------------------

@(private="file")
layers_arg :: proc(L: ^lua.State, from: c.int) -> (set: CollisionLayerSet, ok: bool) {
	ok = true
	add :: proc(L: ^lua.State, i: c.int, set: ^CollisionLayerSet) -> bool {
		if lua.type(L, i) == .NUMBER {
			n := int(lua.tointeger(L, i))
			if n < 1 || n > 16 do return false
			set^ += {CollisionLayer(n - 1)}
			return true
		}
		s := lua.tostring(L, i)
		if s == nil do return false
		l, found := CollisionLayer_Parse(string(s))
		if found do set^ += {l}
		return found
	}
	for i in from ..= lua.gettop(L) {
		if lua.type(L, i) == .TABLE {
			n := c.int(lua.rawlen(L, i))
			for k in 1 ..= n {
				lua.rawgeti(L, i, lua.Integer(k))
				if !add(L, lua.gettop(L), &set) do ok = false
				lua.pop(L, 1)
			}
		} else if !add(L, i, &set) {
			ok = false
		}
	}
	return
}

@(private="file")
set_layers :: proc(L: ^lua.State, mask: bool) -> c.int {
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	set, valid := layers_arg(L, 2)
	if !valid do lua.L_error(L, "unknown collision layer (names from Project Settings > Physics, or 1-16)")
	for &s in Physics_BodyShapes(node) {
		if mask do s.maskLayers = set
		else do s.categoryLayers = set
	}
	return 0
}

// body:set_collision_layer("Player"[, ...]): the layers its shapes are on.
@(private="file")
lua_node_set_collision_layer :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	return set_layers(L, false)
}

// body:set_collision_mask("World", "Enemies"[, ...]): the layers it collides with.
@(private="file")
lua_node_set_collision_mask :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	return set_layers(L, true)
}

// Physics.layer_name(n) -> the project's name for layer n (1-16), or "".
@(private="file")
lua_physics_layer_name :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	n := int(lua.tointeger(L, 1))
	lua.pushstring(L, strings.clone_to_cstring(collisionLayerNames[n - 1] if n >= 1 && n <= 16 else "", context.temp_allocator))
	return 1
}

// --- Navigation -------------------------------------------------------------------

@(private="file")
nav_opts :: proc(L: ^lua.State, idx: c.int) -> Nav_Options {
	o := Nav_DefaultOptions()
	if lua.type(L, idx) != .TABLE do return o
	lua.getfield(L, idx, "diagonal")
	if lua.type(L, -1) == .BOOLEAN do o.diagonal = bool(lua.toboolean(L, -1))
	lua.pop(L, 1)
	lua.getfield(L, idx, "smooth")
	if lua.type(L, -1) == .BOOLEAN do o.smooth = bool(lua.toboolean(L, -1))
	lua.pop(L, 1)
	lua.getfield(L, idx, "walkable_painted")
	if lua.type(L, -1) == .BOOLEAN do o.walkablePainted = bool(lua.toboolean(L, -1))
	lua.pop(L, 1)
	return o
}

// find_path(map, x1, y1, x2, y2 [, opts]) at stack index `mapIdx`.
@(private="file")
nav_find :: proc(L: ^lua.State, mapIdx: c.int) -> c.int {
	node, ok := to_node_userdata(L, mapIdx)
	if !ok {lua.pushnil(L); return 1}
	opts := nav_opts(L, mapIdx + 5)
	g := Nav_GridFor(node, opts)
	from := [2]f32{f32(lua.tonumber(L, mapIdx + 1)), f32(lua.tonumber(L, mapIdx + 2))}
	to := [2]f32{f32(lua.tonumber(L, mapIdx + 3)), f32(lua.tonumber(L, mapIdx + 4))}
	path := Nav_FindPath(g, from, to, opts)
	if path == nil {lua.pushnil(L); return 1}
	lua.createtable(L, c.int(len(path)), 0)
	for p, i in path {
		lua.createtable(L, 2, 0)
		lua.pushnumber(L, lua.Number(p.x)); lua.rawseti(L, -2, 1)
		lua.pushnumber(L, lua.Number(p.y)); lua.rawseti(L, -2, 2)
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

// map:nav_find_path(x1, y1, x2, y2 [, {diagonal, smooth, walkable_painted}])
// -> { {x, y}, ... } or nil (TileMap / LDtk level nodes)
@(private="file")
lua_node_nav_find_path :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	return nav_find(L, 1)
}

// Navigation.find_path(map, x1, y1, x2, y2 [, opts])
@(private="file")
lua_navigation_find_path :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	return nav_find(L, 1)
}

// map:nav_is_walkable(x, y) -> bool
@(private="file")
lua_node_nav_is_walkable :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	walk := false
	if ok {
		if g := Nav_GridFor(node, nav_opts(L, 4)); g != nil {
			walk = Nav_Walkable(g, Nav_CellAt(g, {f32(lua.tonumber(L, 2)), f32(lua.tonumber(L, 3))}))
		}
	}
	lua.pushboolean(L, b32(walk))
	return 1
}

// --- Text, dialogue, localization ------------------------------------------------

// node:set_text(text): a TextNode (restarts its typewriter), UI label or button.
@(private="file")
lua_node_set_text :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	s := lua.tostring(L, 2)
	if !ok || s == nil do return 0
	switch node.typeId {
	case TextNode:     TextNode_SetText(cast(^TextNode)node, string(s))
	case UILabelNode:  (cast(^UILabelNode)node).text = strings.clone(string(s), node.allocator)
	case UIButtonNode: (cast(^UIButtonNode)node).text = strings.clone(string(s), node.allocator)
	}
	return 0
}

@(private="file")
lua_node_get_text :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	text := ""
	if ok {
		switch node.typeId {
		case TextNode:     text = (cast(^TextNode)node).text
		case UILabelNode:  text = (cast(^UILabelNode)node).text
		case UIButtonNode: text = (cast(^UIButtonNode)node).text
		}
	}
	lua.pushstring(L, strings.clone_to_cstring(text, context.temp_allocator))
	return 1
}

// text:text_restart(): types the text out again.
@(private="file")
lua_node_text_restart :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if ok && node.typeId == TextNode {
		t := cast(^TextNode)node
		t.revealed = 0
		t.revealDone = false
	}
	return 0
}

@(private="file")
dialogue_arg :: proc(L: ^lua.State) -> ^DialogueNode {
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != DialogueNode do return nil
	return cast(^DialogueNode)node
}

// box:dialogue_show({ {speaker = "Ada", text = "..."}, "plain line", ... })
// or box:dialogue_show(text [, speaker])
@(private="file")
lua_node_dialogue_show :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	d := dialogue_arg(L)
	if d == nil do return 0
	lines := make([dynamic]Dialogue_Line, context.temp_allocator)
	str :: proc(L: ^lua.State, idx: c.int) -> string {
		s := lua.tostring(L, idx)
		return strings.clone(string(s), context.temp_allocator) if s != nil else ""
	}
	if lua.type(L, 2) == .TABLE {
		n := c.int(lua.rawlen(L, 2))
		for i in 1 ..= n {
			lua.rawgeti(L, 2, lua.Integer(i))
			if lua.type(L, -1) == .TABLE {
				lua.getfield(L, -1, "speaker")
				speaker := str(L, -1)
				lua.pop(L, 1)
				lua.getfield(L, -1, "text")
				text := str(L, -1)
				lua.pop(L, 1)
				append(&lines, Dialogue_Line{speaker, text})
			} else {
				append(&lines, Dialogue_Line{"", str(L, -1)})
			}
			lua.pop(L, 1)
		}
	} else {
		append(&lines, Dialogue_Line{str(L, 3) if lua.gettop(L) >= 3 else "", str(L, 2)})
	}
	DialogueNode_Show(d, lines[:])
	return 0
}

@(private="file")
lua_node_dialogue_next :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	if d := dialogue_arg(L); d != nil do DialogueNode_Advance(d, sm_game_ctx(L))
	return 0
}

@(private="file")
lua_node_dialogue_close :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	if d := dialogue_arg(L); d != nil do DialogueNode_Close(d, sm_game_ctx(L))
	return 0
}

@(private="file")
lua_node_dialogue_is_open :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	d := dialogue_arg(L)
	lua.pushboolean(L, b32(d != nil && DialogueNode_IsOpen(d)))
	return 1
}

@(private="file")
sm_game_ctx :: proc(L: ^lua.State) -> ^GameContext {
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil do return nil
	return &sm.game.gameContext
}

// tr(key [, {name = value, ...}]) -> the text in the current language.
@(private="file")
lua_tr :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	key := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if key == nil {lua.pushstring(L, ""); return 1}
	args := make(map[string]string, context.temp_allocator)
	if lua.type(L, 2) == .TABLE {
		lua.pushnil(L)
		for lua.next(L, 2) != 0 {
			if lua.type(L, -2) == .STRING {
				k := strings.clone(string(lua.tostring(L, -2)), context.temp_allocator)
				// tostring() without converting the key in place.
				lua.pushvalue(L, -1)
				v := lua.L_tostring(L, -1) // pushes the string
				args[k] = strings.clone(string(v), context.temp_allocator)
				lua.pop(L, 2)
			}
			lua.pop(L, 1)
		}
	}
	game := sm.game if sm != nil else nil
	lua.pushstring(L, strings.clone_to_cstring(Locale_Get(game, string(key), args), context.temp_allocator))
	return 1
}

@(private="file")
lua_locale_set :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	if s := lua.tostring(L, 1); s != nil do Locale_SetLanguage(string(s))
	return 0
}

@(private="file")
lua_locale_get :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	if sm != nil && sm.game != nil do Locale_Languages(sm.game) // loads the tables
	lua.pushstring(L, strings.clone_to_cstring(Locale_Language(), context.temp_allocator))
	return 1
}

@(private="file")
lua_locale_languages :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	langs: []string
	if sm != nil && sm.game != nil do langs = Locale_Languages(sm.game)
	lua.createtable(L, c.int(len(langs)), 0)
	for l, i in langs {
		lua.pushstring(L, strings.clone_to_cstring(l, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

// --- Line and trail -----------------------------------------------------------------

// line:line_set_points({ {x, y}, ... }) (local to the node)
@(private="file")
lua_node_line_set_points :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok || node.typeId != LineNode || lua.type(L, 2) != .TABLE do return 0
	ln := cast(^LineNode)node
	clear(&ln.points)
	n := c.int(lua.rawlen(L, 2))
	for i in 1 ..= n {
		lua.rawgeti(L, 2, lua.Integer(i))
		lua.rawgeti(L, -1, 1)
		x := f32(lua.tonumber(L, -1))
		lua.rawgeti(L, -2, 2)
		y := f32(lua.tonumber(L, -1))
		lua.pop(L, 3)
		append(&ln.points, [2]f32{x, y})
	}
	return 0
}

// line:line_add_point(x, y)
@(private="file")
lua_node_line_add_point :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if ok && node.typeId == LineNode do append(&(cast(^LineNode)node).points, [2]f32{f32(lua.tonumber(L, 2)), f32(lua.tonumber(L, 3))})
	return 0
}

// line:line_clear() / trail:trail_clear()
@(private="file")
lua_node_line_clear :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if !ok do return 0
	if node.typeId == LineNode do clear(&(cast(^LineNode)node).points)
	if node.typeId == TrailNode do TrailNode_Clear(cast(^TrailNode)node)
	return 0
}

@(private="file")
lua_scene_find_node :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	nameC := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if nameC == nil || sm == nil || sm.game == nil || sm.game.sceneManager.currentScene == nil {
		lua.pushnil(L)
		return 1
	}
	targetNode := Scene_FindNodeByName(sm.game.sceneManager.currentScene, string(nameC))
	push_node_userdata(L, targetNode)
	return 1
}

@(private="file")
lua_scene_get_name :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || sm.game.sceneManager.currentScene == nil {
		lua.pushstring(L, "")
		return 1
	}
	nameC := strings.clone_to_cstring(sm.game.sceneManager.currentScene.name, context.temp_allocator)
	lua.pushstring(L, nameC)
	return 1
}

@(private="file")
lua_scene_change_scene :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	nameC := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if nameC == nil || sm == nil || sm.game == nil do return 0
	// Scene.change_scene(name [, {transition = "fade"|"wipe_left"|..|"circle", duration = 0.4, color = {r, g, b}}])
	if lua.type(L, 2) == .TABLE {
		scene, ok := sm.game.sceneManager.scenes[string(nameC)]
		if !ok {
			log.errorf("Scene: %s, not found", nameC)
			return 0
		}
		lua.getfield(L, 2, "transition")
		kind := Transition_KindParse(string(lua.tostring(L, -1)) if lua.type(L, -1) == .STRING else "fade")
		lua.pop(L, 1)
		lua.getfield(L, 2, "duration")
		duration := f32(lua.tonumber(L, -1)) if lua.type(L, -1) == .NUMBER else 0.4
		lua.pop(L, 1)
		color := rl.BLACK
		lua.getfield(L, 2, "color")
		if lua.type(L, -1) == .TABLE {
			ch :: proc(L: ^lua.State, k: lua.Integer) -> u8 {
				lua.rawgeti(L, -1, k)
				defer lua.pop(L, 1)
				return u8(clamp(f32(lua.tonumber(L, -1)), 0, 1) * 255)
			}
			color = {ch(L, 1), ch(L, 2), ch(L, 3), 255}
		}
		lua.pop(L, 1)
		Game_ChangeSceneWith(sm.game, scene, kind, duration, color)
		return 0
	}
	ChangeScene_ByName(&sm.game.sceneManager, string(nameC))
	return 0
}

// Scene.preload(name): load its assets in the background (a little each frame).
@(private="file")
lua_scene_preload :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	nameC := lua.tostring(L, 1)
	if nameC == nil || sm == nil || sm.game == nil do return 0
	if scene, ok := sm.game.sceneManager.scenes[string(nameC)]; ok do Scene_PreloadBegin(sm.game, scene)
	return 0
}

// Scene.preload_progress(name) -> 0..1
@(private="file")
lua_scene_preload_progress :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	nameC := lua.tostring(L, 1)
	v: f32
	if nameC != nil && sm != nil && sm.game != nil {
		if scene, ok := sm.game.sceneManager.scenes[string(nameC)]; ok do v = Scene_PreloadProgress(sm.game, scene)
	}
	lua.pushnumber(L, lua.Number(v))
	return 1
}

@(private="file")
lua_scene_is_transitioning :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	lua.pushboolean(L, b32(sm != nil && sm.game != nil && sm.game.transition.active))
	return 1
}

// Engine.set_paused(bool): pausable nodes and physics stop; "always" nodes run.
@(private="file")
lua_engine_set_paused :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	if sm != nil && sm.game != nil do Game_SetPaused(sm.game, bool(lua.toboolean(L, 1)))
	return 0
}

@(private="file")
lua_engine_is_paused :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	lua.pushboolean(L, b32(sm != nil && sm.game != nil && sm.game.treePaused))
	return 1
}

// node:set_paused(bool): pauses this node and its children (unless "always").
@(private="file")
lua_node_set_paused :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	if node, ok := to_node_userdata(L, 1); ok do node.paused = bool(lua.toboolean(L, 2))
	return 0
}

// node:is_paused() -> paused this frame (by itself, a parent or the game)
@(private="file")
lua_node_is_paused :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	lua.pushboolean(L, b32(ok && (node.paused || node.pausedNow)))
	return 1
}

// node:set_pause_mode("inherit" | "pausable" | "always")
@(private="file")
lua_node_set_pause_mode :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	node, ok := to_node_userdata(L, 1)
	if s := lua.tostring(L, 2); ok && s != nil do node.pauseMode = Pause_ModeParse(string(s))
	return 0
}

@(private="file")
lua_scene_reload :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	if sm != nil && sm.game != nil && sm.game.sceneManager.currentScene != nil {
		ChangeScene_ByName(&sm.game.sceneManager, sm.game.sceneManager.currentScene.name)
	}
	return 0
}

@(private="file")
lua_scene_get_nodes :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || sm.game.sceneManager.currentScene == nil || sm.game.sceneManager.currentScene.manager == nil {
		lua.newtable(L)
		return 1
	}
	mgr := sm.game.sceneManager.currentScene.manager
	lua.createtable(L, c.int(len(mgr.nodes)), 0)
	idx := 1
	for node in mgr.nodes {
		if node != nil {
			push_node_userdata(L, node)
			lua.rawseti(L, -2, lua.Integer(idx))
			idx += 1
		}
	}
	return 1
}

@(private="file")
lua_scene_create_node :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || sm.game.sceneManager.currentScene == nil {
		lua.pushnil(L)
		return 1
	}
	scene := sm.game.sceneManager.currentScene
	typeStrC := lua.tostring(L, 1)
	nameC := lua.tostring(L, 2)
	parent, pOk := to_node_userdata(L, 3)
	log.infof("[lua_scene_create_node] type=%s, name=%s, parent=%v, pOk=%v, top=%d", typeStrC, nameC, parent, pOk, lua.gettop(L))

	typeStr := string(typeStrC) if typeStrC != nil else "Node"
	nodeName := string(nameC) if nameC != nil else ""

	createdNode: ^Node = nil
	switch strings.to_lower(typeStr, context.temp_allocator) {
	case "texturenode", "texture", "sprite":
		tn := CreateNode(scene.manager, TextureNode)
		TextureNode_Init(tn)
		if nodeName != "" do tn.name = strings.clone(nodeName, tn.allocator)
		createdNode = tn
	case "scriptnode", "script":
		sn := CreateNode(scene.manager, ScriptNode)
		ScriptNode_Init(sn)
		if nodeName != "" do sn.name = strings.clone(nodeName, sn.allocator)
		createdNode = sn
	case "cameranode", "camera":
		cn := CreateNode(scene.manager, CameraNode)
		CameraNode_Init(cn)
		if nodeName != "" do cn.name = strings.clone(nodeName, cn.allocator)
		createdNode = cn
	case "particleemitternode", "particle", "particles":
		pn := CreateNode(scene.manager, ParticleEmitterNode)
		ParticleEmitterNode_Init(pn)
		if nodeName != "" do pn.name = strings.clone(nodeName, pn.allocator)
		createdNode = pn
	case "timernode", "timer":
		tm := CreateNode(scene.manager, TimerNode)
		TimerNode_Init(tm)
		if nodeName != "" do tm.name = strings.clone(nodeName, tm.allocator)
		createdNode = tm
	case "dynamicbodynode", "dynamicbody", "dynamic_body":
		db := DynamicBodyNode_Create(scene, nodeName, parent)
		createdNode = db
	case "staticbodynode", "staticbody", "static_body":
		sb := StaticBodyNode_Create(scene, nodeName, parent)
		createdNode = sb
	case "charactermovernode", "charactermover", "character_mover":
		cm := CharacterMoverNode_Create(scene, nodeName, parent)
		createdNode = cm
	case "areanode", "area":
		ar := AreaNode_Create(scene, nodeName, parent)
		createdNode = ar
	case "raycastnode", "raycast":
		rc := RaycastNode_Create(scene, nodeName, parent)
		createdNode = rc
	case:
		nd := CreateNode(scene.manager, Node)
		if nodeName != "" do nd.name = strings.clone(nodeName, nd.allocator)
		createdNode = nd
	}

	if createdNode != nil {
		SceneAddNode(scene, createdNode, parent)
		push_node_userdata(L, createdNode)
		return 1
	}

	lua.pushnil(L)
	return 1
}

@(private="file")
lua_scene_get_draw_bounds :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || sm.game.sceneManager.currentScene == nil {
		lua.pushboolean(L, false)
		return 1
	}
	lua.pushboolean(L, b32(sm.game.sceneManager.currentScene.drawBounds))
	return 1
}

@(private="file")
lua_scene_set_draw_bounds :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	if sm != nil && sm.game != nil && sm.game.sceneManager.currentScene != nil {
		draw := lua.toboolean(L, 1)
		sm.game.sceneManager.currentScene.drawBounds = bool(draw)
	}
	return 0
}

// ----------------------------------------------------------------------------
// Log Bindings (Engine.Log & print)
// ----------------------------------------------------------------------------

@(private="file")
lua_log_info :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	nargs := lua.gettop(L)
	sb: strings.Builder
	strings.builder_init(&sb, context.temp_allocator)

	for i in 1..=nargs {
		strC := lua.tostring(L, i)
		if strC != nil {
			strings.write_string(&sb, string(strC))
		} else {
			strings.write_string(&sb, "[non-string]")
		}
		if i < nargs do strings.write_string(&sb, "\t")
	}
	log.infof("[Lua] %s", strings.to_string(sb))
	return 0
}

@(private="file")
lua_log_warn :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	nargs := lua.gettop(L)
	sb: strings.Builder
	strings.builder_init(&sb, context.temp_allocator)

	for i in 1..=nargs {
		strC := lua.tostring(L, i)
		if strC != nil {
			strings.write_string(&sb, string(strC))
		}
		if i < nargs do strings.write_string(&sb, "\t")
	}
	log.warnf("[Lua WARN] %s", strings.to_string(sb))
	return 0
}

@(private="file")
lua_log_error :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	nargs := lua.gettop(L)
	sb: strings.Builder
	strings.builder_init(&sb, context.temp_allocator)

	for i in 1..=nargs {
		strC := lua.tostring(L, i)
		if strC != nil {
			strings.write_string(&sb, string(strC))
		}
		if i < nargs do strings.write_string(&sb, "\t")
	}
	log.errorf("[Lua ERROR] %s", strings.to_string(sb))
	return 0
}

// ----------------------------------------------------------------------------

// ----------------------------------------------------------------------------
// Global Project Table (Engine.Project)
// ----------------------------------------------------------------------------

@(private="file")
lua_project_load :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	pathC := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if pathC == nil || sm == nil || sm.game == nil {
		lua.pushboolean(L, false)
		return 1
	}
	ok := sm.game->loadProject(string(pathC))
	lua.pushboolean(L, b32(ok))
	return 1
}

@(private="file")
lua_project_export_ore :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	dirC := lua.tostring(L, 1)
	outC := lua.tostring(L, 2)
	sm := get_script_manager(L)
	if dirC == nil || outC == nil || sm == nil || sm.game == nil {
		lua.pushboolean(L, false)
		return 1
	}
	ok := sm.game.exportOre(string(dirC), string(outC))
	lua.pushboolean(L, b32(ok))
	return 1
}

@(private="file")
lua_project_serialize_scene :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || sm.game.sceneManager.currentScene == nil {
		lua.pushstring(L, "{}")
		return 1
	}
	jsonStr := Scene_SerializeToJSON(sm.game.sceneManager.currentScene, context.temp_allocator)
	jsonC := strings.clone_to_cstring(jsonStr, context.temp_allocator)
	lua.pushstring(L, jsonC)
	return 1
}

@(private="file")
lua_project_read_file :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	pathC := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if pathC == nil || sm == nil || sm.game == nil {
		lua.pushnil(L)
		return 1
	}
	txt, ok := AssetManager_ReadFileString(&sm.game.assetManager, string(pathC), context.temp_allocator)
	if !ok {
		lua.pushnil(L)
		return 1
	}
	txtC := strings.clone_to_cstring(txt, context.temp_allocator)
	lua.pushstring(L, txtC)
	return 1
}

@(private="file")
lua_project_has_file :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	pathC := lua.tostring(L, 1)
	sm := get_script_manager(L)
	if pathC == nil || sm == nil || sm.game == nil {
		lua.pushboolean(L, false)
		return 1
	}
	if sm.game.assetManager.package_ != nil {
		lua.pushboolean(L, b32(OrePackage_HasFile(sm.game.assetManager.package_, string(pathC))))
		return 1
	}
	resolved := AssetManager_ResolveDiskPath(&sm.game.assetManager, string(pathC), context.temp_allocator)
	lua.pushboolean(L, b32(os.exists(resolved) || os.exists(string(pathC))))
	return 1
}

// Registration of all Metatables and Global Tables
// ----------------------------------------------------------------------------

RegisterEngineLuaBindings :: proc(L: ^lua.State, sm: ^ScriptManager) {
	// Store ScriptManager in Lua registry for thread-safe access
	lua.pushlightuserdata(L, sm)
	lua.setfield(L, lua.REGISTRYINDEX, "__Engine_ScriptManager")

	// 1. "Engine.Node" Metatable
	if lua.L_newmetatable(L, "Engine.Node") != 0 {
		// Type & Identity
		lua.pushcfunction(L, lua_node_get_type)
		lua.setfield(L, -2, "get_type")
		lua.pushcfunction(L, lua_node_get_name)
		lua.setfield(L, -2, "get_name")
		lua.pushcfunction(L, lua_node_set_name)
		lua.setfield(L, -2, "set_name")

		// Transforms
		lua.pushcfunction(L, lua_node_get_position)
		lua.setfield(L, -2, "get_position")
		lua.pushcfunction(L, lua_node_set_position)
		lua.setfield(L, -2, "set_position")
		lua.pushcfunction(L, lua_node_translate)
		lua.setfield(L, -2, "translate")

		lua.pushcfunction(L, lua_node_get_rotation)
		lua.setfield(L, -2, "get_rotation")
		lua.pushcfunction(L, lua_node_set_rotation)
		lua.setfield(L, -2, "set_rotation")
		lua.pushcfunction(L, lua_node_rotate)
		lua.setfield(L, -2, "rotate")

		lua.pushcfunction(L, lua_node_get_scale)
		lua.setfield(L, -2, "get_scale")
		lua.pushcfunction(L, lua_node_set_scale)
		lua.setfield(L, -2, "set_scale")
		lua.pushcfunction(L, lua_node_set_texture)
		lua.setfield(L, -2, "set_texture")
		lua.pushcfunction(L, lua_node_get_node)
		lua.setfield(L, -2, "get_node")

		lua.pushcfunction(L, lua_node_get_global_position)
		lua.setfield(L, -2, "get_global_position")
		lua.pushcfunction(L, lua_node_get_global_rotation)
		lua.setfield(L, -2, "get_global_rotation")

		// Lifecycle & Visibility
		lua.pushcfunction(L, lua_node_is_enabled)
		lua.setfield(L, -2, "is_enabled")
		lua.pushcfunction(L, lua_node_set_enabled)
		lua.setfield(L, -2, "set_enabled")
		lua.pushcfunction(L, lua_node_is_visible)
		lua.setfield(L, -2, "is_visible")
		lua.pushcfunction(L, lua_node_set_visible)
		lua.setfield(L, -2, "set_visible")

		// Tags (node_tags.odin)
		lua.pushcfunction(L, lua_node_add_tag)
		lua.setfield(L, -2, "add_tag")
		lua.pushcfunction(L, lua_node_remove_tag)
		lua.setfield(L, -2, "remove_tag")
		lua.pushcfunction(L, lua_node_has_tag)
		lua.setfield(L, -2, "has_tag")
		lua.pushcfunction(L, lua_node_get_tags)
		lua.setfield(L, -2, "get_tags")

		// Hierarchy
		lua.pushcfunction(L, lua_node_get_parent)
		lua.setfield(L, -2, "get_parent")
		lua.pushcfunction(L, lua_node_get_children)
		lua.setfield(L, -2, "get_children")
		lua.pushcfunction(L, lua_node_get_child)
		lua.setfield(L, -2, "get_child")
		lua.pushcfunction(L, lua_node_add_child)
		lua.setfield(L, -2, "add_child")
		lua.pushcfunction(L, lua_node_remove_child)
		lua.setfield(L, -2, "remove_child")
		lua.pushcfunction(L, lua_node_destroy)
		lua.setfield(L, -2, "destroy")
		lua.pushcfunction(L, lua_node_set_shader)
		lua.setfield(L, -2, "set_shader")
		lua.pushcfunction(L, lua_node_set_shader_param)
		lua.setfield(L, -2, "set_shader_param")
		lua.pushcfunction(L, lua_node_get_shader_param)
		lua.setfield(L, -2, "get_shader_param")
		lua.pushcfunction(L, lua_node_set_blend_mode)
		lua.setfield(L, -2, "set_blend_mode")
		lua.pushcfunction(L, lua_light_set_color)
		lua.setfield(L, -2, "light_set_color")
		lua.pushcfunction(L, lua_light_set_energy)
		lua.setfield(L, -2, "light_set_energy")
		lua.pushcfunction(L, lua_light_get_energy)
		lua.setfield(L, -2, "light_get_energy")
		lua.pushcfunction(L, lua_light_set_radius)
		lua.setfield(L, -2, "light_set_radius")
		lua.pushcfunction(L, lua_node_set_property)
		lua.setfield(L, -2, "set_property")
		lua.pushcfunction(L, lua_node_line_set_points)
		lua.setfield(L, -2, "line_set_points")
		lua.pushcfunction(L, lua_node_line_add_point)
		lua.setfield(L, -2, "line_add_point")
		lua.pushcfunction(L, lua_node_line_clear)
		lua.setfield(L, -2, "line_clear")
		lua.pushcfunction(L, lua_node_line_clear)
		lua.setfield(L, -2, "trail_clear")
		lua.pushcfunction(L, lua_node_set_paused)
		lua.setfield(L, -2, "set_paused")
		lua.pushcfunction(L, lua_node_is_paused)
		lua.setfield(L, -2, "is_paused")
		lua.pushcfunction(L, lua_node_set_pause_mode)
		lua.setfield(L, -2, "set_pause_mode")
		lua.pushcfunction(L, lua_node_set_text)
		lua.setfield(L, -2, "set_text")
		lua.pushcfunction(L, lua_node_get_text)
		lua.setfield(L, -2, "get_text")
		lua.pushcfunction(L, lua_node_text_restart)
		lua.setfield(L, -2, "text_restart")
		lua.pushcfunction(L, lua_node_dialogue_show)
		lua.setfield(L, -2, "dialogue_show")
		lua.pushcfunction(L, lua_node_dialogue_next)
		lua.setfield(L, -2, "dialogue_next")
		lua.pushcfunction(L, lua_node_dialogue_close)
		lua.setfield(L, -2, "dialogue_close")
		lua.pushcfunction(L, lua_node_dialogue_is_open)
		lua.setfield(L, -2, "dialogue_is_open")
		lua.pushcfunction(L, lua_node_nav_find_path)
		lua.setfield(L, -2, "nav_find_path")
		lua.pushcfunction(L, lua_node_nav_is_walkable)
		lua.setfield(L, -2, "nav_is_walkable")
		lua.pushcfunction(L, lua_node_get_property)
		lua.setfield(L, -2, "get_property")
		lua.pushcfunction(L, lua_node_set_collision_layer)
		lua.setfield(L, -2, "set_collision_layer")
		lua.pushcfunction(L, lua_node_set_collision_mask)
		lua.setfield(L, -2, "set_collision_mask")
		lua.pushcfunction(L, lua_sm_set)
		lua.setfield(L, -2, "sm_set")
		lua.pushcfunction(L, lua_sm_get)
		lua.setfield(L, -2, "sm_get")
		lua.pushcfunction(L, lua_sm_trigger)
		lua.setfield(L, -2, "sm_trigger")
		lua.pushcfunction(L, lua_sm_travel)
		lua.setfield(L, -2, "sm_travel")
		lua.pushcfunction(L, lua_sm_state)
		lua.setfield(L, -2, "sm_state")
		lua.pushcfunction(L, lua_sm_previous)
		lua.setfield(L, -2, "sm_previous")
		lua.pushcfunction(L, lua_sm_time)
		lua.setfield(L, -2, "sm_time")
		lua.pushcfunction(L, lua_sm_start)
		lua.setfield(L, -2, "sm_start")
		lua.pushcfunction(L, lua_sm_stop)
		lua.setfield(L, -2, "sm_stop")
		Script_RegisterEventBindings(L) // connect / disconnect / emit
		Script_RegisterLdtkBindings(L)

		// DynamicBodyNode Physics
		lua.pushcfunction(L, lua_node_apply_force)
		lua.setfield(L, -2, "apply_force")
		lua.pushcfunction(L, lua_node_apply_impulse)
		lua.setfield(L, -2, "apply_impulse")
		lua.pushcfunction(L, lua_node_get_linear_velocity)
		lua.setfield(L, -2, "get_linear_velocity")
		lua.pushcfunction(L, lua_node_set_linear_velocity)
		lua.setfield(L, -2, "set_linear_velocity")
		lua.pushcfunction(L, lua_node_get_angular_velocity)
		lua.setfield(L, -2, "get_angular_velocity")
		lua.pushcfunction(L, lua_node_set_angular_velocity)
		lua.setfield(L, -2, "set_angular_velocity")
		lua.pushcfunction(L, lua_node_get_gravity_scale)
		lua.setfield(L, -2, "get_gravity_scale")
		lua.pushcfunction(L, lua_node_set_gravity_scale)
		lua.setfield(L, -2, "set_gravity_scale")
		lua.pushcfunction(L, lua_node_is_fixed_rotation)
		lua.setfield(L, -2, "is_fixed_rotation")
		lua.pushcfunction(L, lua_node_set_fixed_rotation)
		lua.setfield(L, -2, "set_fixed_rotation")
		lua.pushcfunction(L, lua_node_set_linear_damping)
		lua.setfield(L, -2, "set_linear_damping")
		lua.pushcfunction(L, lua_node_set_angular_damping)
		lua.setfield(L, -2, "set_angular_damping")
		lua.pushcfunction(L, lua_node_is_awake)
		lua.setfield(L, -2, "is_awake")
		lua.pushcfunction(L, lua_node_set_awake)
		lua.setfield(L, -2, "set_awake")

		// CharacterMoverNode
		lua.pushcfunction(L, lua_node_character_move)
		lua.setfield(L, -2, "character_move")
		lua.pushcfunction(L, lua_node_character_is_grounded)
		lua.setfield(L, -2, "character_is_grounded")
		lua.pushcfunction(L, lua_node_character_get_velocity)
		lua.setfield(L, -2, "character_get_velocity")
		lua.pushcfunction(L, lua_node_character_set_velocity)
		lua.setfield(L, -2, "character_set_velocity")
		lua.pushcfunction(L, lua_node_character_set_speed)
		lua.setfield(L, -2, "character_set_speed")
		lua.pushcfunction(L, lua_node_character_set_jump_speed)
		lua.setfield(L, -2, "character_set_jump_speed")
		lua.pushcfunction(L, lua_node_character_move_and_slide)
		lua.setfield(L, -2, "character_move_and_slide")
		lua.pushcfunction(L, lua_node_character_is_on_floor)
		lua.setfield(L, -2, "character_is_on_floor")
		lua.pushcfunction(L, lua_node_character_is_on_wall)
		lua.setfield(L, -2, "character_is_on_wall")
		lua.pushcfunction(L, lua_node_character_is_on_ceiling)
		lua.setfield(L, -2, "character_is_on_ceiling")
		lua.pushcfunction(L, lua_node_character_get_floor_normal)
		lua.setfield(L, -2, "character_get_floor_normal")
		lua.pushcfunction(L, lua_node_character_get_wall_normal)
		lua.setfield(L, -2, "character_get_wall_normal")
		lua.pushcfunction(L, lua_node_character_get_last_motion)
		lua.setfield(L, -2, "character_get_last_motion")
		lua.pushcfunction(L, lua_node_character_get_gravity)
		lua.setfield(L, -2, "character_get_gravity")
		lua.pushcfunction(L, lua_node_character_set_gravity_scale)
		lua.setfield(L, -2, "character_set_gravity_scale")
		lua.pushcfunction(L, lua_node_character_set_control_mode)
		lua.setfield(L, -2, "character_set_control_mode")

		// AreaNode
		lua.pushcfunction(L, lua_node_area_is_overlapping)
		lua.setfield(L, -2, "area_is_overlapping")
		lua.pushcfunction(L, lua_node_area_get_overlap_count)
		lua.setfield(L, -2, "area_get_overlap_count")
		lua.pushcfunction(L, lua_node_area_get_overlapping_nodes)
		lua.setfield(L, -2, "area_get_overlapping_nodes")

		// RaycastNode
		lua.pushcfunction(L, lua_node_raycast_cast)
		lua.setfield(L, -2, "raycast_cast")
		lua.pushcfunction(L, lua_node_raycast_is_colliding)
		lua.setfield(L, -2, "raycast_is_colliding")
		lua.pushcfunction(L, lua_node_raycast_get_hit_point)
		lua.setfield(L, -2, "raycast_get_hit_point")
		lua.pushcfunction(L, lua_node_raycast_get_hit_normal)
		lua.setfield(L, -2, "raycast_get_hit_normal")
		lua.pushcfunction(L, lua_node_raycast_get_hit_fraction)
		lua.setfield(L, -2, "raycast_get_hit_fraction")
		lua.pushcfunction(L, lua_node_raycast_get_hit_node)
		lua.setfield(L, -2, "raycast_get_hit_node")
		lua.pushcfunction(L, lua_node_raycast_set_direction)
		lua.setfield(L, -2, "raycast_set_direction")
		lua.pushcfunction(L, lua_node_raycast_set_length)
		lua.setfield(L, -2, "raycast_set_length")

		// ParticleEmitterNode
		lua.pushcfunction(L, lua_node_particle_start)
		lua.setfield(L, -2, "particle_start")
		lua.pushcfunction(L, lua_node_particle_stop)
		lua.setfield(L, -2, "particle_stop")
		lua.pushcfunction(L, lua_node_particle_is_emitting)
		lua.setfield(L, -2, "particle_is_emitting")
		lua.pushcfunction(L, lua_node_particle_set_amount)
		lua.setfield(L, -2, "particle_set_amount")
		lua.pushcfunction(L, lua_node_particle_set_lifetime)
		lua.setfield(L, -2, "particle_set_lifetime")

		// TextureNode
		lua.pushcfunction(L, lua_node_texture_get_size)
		lua.setfield(L, -2, "texture_get_size")
		lua.pushcfunction(L, lua_node_texture_set_origin)
		lua.setfield(L, -2, "texture_set_origin")
		lua.pushcfunction(L, lua_node_texture_get_path)
		lua.setfield(L, -2, "texture_get_path")

		// AnimationPlayerNode
		lua.pushcfunction(L, lua_node_animation_play)
		lua.setfield(L, -2, "animation_play")
		lua.pushcfunction(L, lua_node_animation_stop)
		lua.setfield(L, -2, "animation_stop")
		lua.pushcfunction(L, lua_node_animation_pause)
		lua.setfield(L, -2, "animation_pause")
		lua.pushcfunction(L, lua_node_animation_resume)
		lua.setfield(L, -2, "animation_resume")
		lua.pushcfunction(L, lua_node_animation_reset)
		lua.setfield(L, -2, "animation_reset")
		lua.pushcfunction(L, lua_node_animation_set_fps)
		lua.setfield(L, -2, "animation_set_fps")
		lua.pushcfunction(L, lua_node_animation_get_current)
		lua.setfield(L, -2, "animation_get_current")

		// TimerNode
		lua.pushcfunction(L, lua_node_timer_start)
		lua.setfield(L, -2, "timer_start")
		lua.pushcfunction(L, lua_node_timer_stop)
		lua.setfield(L, -2, "timer_stop")
		lua.pushcfunction(L, lua_node_timer_is_running)
		lua.setfield(L, -2, "timer_is_running")
		lua.pushcfunction(L, lua_node_timer_get_elapsed)
		lua.setfield(L, -2, "timer_get_elapsed")
		lua.pushcfunction(L, lua_node_timer_set_duration)
		lua.setfield(L, -2, "timer_set_duration")
		lua.pushcfunction(L, lua_node_timer_set_loop)
		lua.setfield(L, -2, "timer_set_loop")

		// Sound & Music Node
		lua.pushcfunction(L, lua_node_sound_play)
		lua.setfield(L, -2, "sound_play")
		lua.pushcfunction(L, lua_node_sound_stop)
		lua.setfield(L, -2, "sound_stop")
		lua.pushcfunction(L, lua_node_sound_pause)
		lua.setfield(L, -2, "sound_pause")
		lua.pushcfunction(L, lua_node_sound_resume)
		lua.setfield(L, -2, "sound_resume")

		lua.pushcfunction(L, lua_node_music_play)
		lua.setfield(L, -2, "music_play")
		lua.pushcfunction(L, lua_node_music_stop)
		lua.setfield(L, -2, "music_stop")
		lua.pushcfunction(L, lua_node_music_pause)
		lua.setfield(L, -2, "music_pause")
		lua.pushcfunction(L, lua_node_music_resume)
		lua.setfield(L, -2, "music_resume")
		lua.pushcfunction(L, lua_node_music_fade)
		lua.setfield(L, -2, "music_fade")

		// CameraNode (Invoked on node)
		lua.pushcfunction(L, lua_node_camera_set_zoom)
		lua.setfield(L, -2, "camera_set_zoom")
		lua.pushcfunction(L, lua_node_camera_get_zoom)
		lua.setfield(L, -2, "camera_get_zoom")
		lua.pushcfunction(L, lua_node_camera_set_target)
		lua.setfield(L, -2, "camera_set_target")
		lua.pushcfunction(L, lua_node_camera_add_target)
		lua.setfield(L, -2, "camera_add_target")
		lua.pushcfunction(L, lua_node_camera_remove_target)
		lua.setfield(L, -2, "camera_remove_target")
		lua.pushcfunction(L, lua_node_camera_clear_targets)
		lua.setfield(L, -2, "camera_clear_targets")
		lua.pushcfunction(L, lua_node_camera_get_target)
		lua.setfield(L, -2, "camera_get_target")
		lua.pushcfunction(L, lua_node_camera_get_targets)
		lua.setfield(L, -2, "camera_get_targets")
		lua.pushcfunction(L, lua_node_camera_set_target_position)
		lua.setfield(L, -2, "camera_set_target_position")
		lua.pushcfunction(L, lua_node_camera_shake)
		lua.setfield(L, -2, "camera_shake")
		lua.pushcfunction(L, lua_node_camera_stop_shake)
		lua.setfield(L, -2, "camera_stop_shake")
		lua.pushcfunction(L, lua_node_camera_is_shaking)
		lua.setfield(L, -2, "camera_is_shaking")
		lua.pushcfunction(L, lua_node_camera_set_limits)
		lua.setfield(L, -2, "camera_set_limits")
		lua.pushcfunction(L, lua_node_camera_clear_limits)
		lua.setfield(L, -2, "camera_clear_limits")

		// LDtk Node
		lua.pushcfunction(L, lua_node_ldtk_get_level_identifier)
		lua.setfield(L, -2, "ldtk_get_level_identifier")

		// __index points to itself
		lua.pushvalue(L, -1)
		lua.setfield(L, -2, "__index")
	}
	lua.pop(L, 1)

	// 2. Global "Engine" table
	lua.newtable(L)
	lua.pushcfunction(L, lua_engine_get_fps)
	lua.setfield(L, -2, "get_fps")
	lua.pushcfunction(L, lua_engine_get_delta_time)
	lua.setfield(L, -2, "get_delta_time")
	lua.pushcfunction(L, lua_engine_get_time)
	lua.setfield(L, -2, "get_time")
	lua.pushcfunction(L, lua_engine_get_window_size)
	lua.setfield(L, -2, "get_window_size")
	lua.pushcfunction(L, lua_engine_get_virtual_size)
	lua.setfield(L, -2, "get_virtual_size")
	lua.pushcfunction(L, lua_engine_set_paused)
	lua.setfield(L, -2, "set_paused")
	lua.pushcfunction(L, lua_engine_is_paused)
	lua.setfield(L, -2, "is_paused")
	lua.setglobal(L, "Engine")

	// 3. Global "Input" table
	lua.newtable(L)
	lua.pushcfunction(L, lua_input_is_action_pressed)
	lua.setfield(L, -2, "is_action_pressed")
	lua.pushcfunction(L, lua_input_is_action_down)
	lua.setfield(L, -2, "is_action_down")
	lua.pushcfunction(L, lua_input_is_action_released)
	lua.setfield(L, -2, "is_action_released")
	lua.pushcfunction(L, lua_input_get_axis)
	lua.setfield(L, -2, "get_axis")
	lua.pushcfunction(L, lua_input_get_vector)
	lua.setfield(L, -2, "get_vector")
	lua.pushcfunction(L, lua_input_is_key_pressed)
	lua.setfield(L, -2, "is_key_pressed")
	lua.pushcfunction(L, lua_input_is_key_down)
	lua.setfield(L, -2, "is_key_down")
	lua.pushcfunction(L, lua_input_is_key_released)
	lua.setfield(L, -2, "is_key_released")
	lua.pushcfunction(L, lua_input_is_mouse_button_pressed)
	lua.setfield(L, -2, "is_mouse_button_pressed")
	lua.pushcfunction(L, lua_input_is_mouse_button_down)
	lua.setfield(L, -2, "is_mouse_button_down")
	lua.pushcfunction(L, lua_input_is_mouse_button_released)
	lua.setfield(L, -2, "is_mouse_button_released")
	lua.pushcfunction(L, lua_input_get_mouse_position)
	lua.setfield(L, -2, "get_mouse_position")
	lua.pushcfunction(L, lua_input_get_mouse_wheel_move)
	lua.setfield(L, -2, "get_mouse_wheel_move")
	lua.setglobal(L, "Input")

	// 4. Global "Audio" table
	lua.newtable(L)
	lua.pushcfunction(L, lua_audio_play_sound)
	lua.setfield(L, -2, "play_sound")
	lua.pushcfunction(L, lua_audio_play_music)
	lua.setfield(L, -2, "play_music")
	lua.pushcfunction(L, lua_audio_stop_music)
	lua.setfield(L, -2, "stop_music")
	lua.pushcfunction(L, lua_audio_pause_music)
	lua.setfield(L, -2, "pause_music")
	lua.pushcfunction(L, lua_audio_resume_music)
	lua.setfield(L, -2, "resume_music")
	lua.pushcfunction(L, lua_audio_is_music_playing)
	lua.setfield(L, -2, "is_music_playing")
	lua.pushcfunction(L, lua_audio_play_sound_at)
	lua.setfield(L, -2, "play_sound_at")
	lua.pushcfunction(L, lua_audio_set_bus_volume)
	lua.setfield(L, -2, "set_bus_volume")
	lua.pushcfunction(L, lua_audio_get_bus_volume)
	lua.setfield(L, -2, "get_bus_volume")
	lua.pushcfunction(L, lua_audio_set_lowpass)
	lua.setfield(L, -2, "set_lowpass")
	lua.pushcfunction(L, lua_audio_set_reverb)
	lua.setfield(L, -2, "set_reverb")
	lua.pushcfunction(L, lua_audio_set_listener)
	lua.setfield(L, -2, "set_listener")
	lua.pushcfunction(L, lua_audio_crossfade)
	lua.setfield(L, -2, "crossfade")
	lua.pushcfunction(L, lua_audio_set_music_volume)
	lua.setfield(L, -2, "set_music_volume")
	lua.pushcfunction(L, lua_audio_set_master_volume)
	lua.setfield(L, -2, "set_master_volume")
	lua.setglobal(L, "Audio")

	// 5. Global "Camera" table
	lua.newtable(L)
	lua.pushcfunction(L, lua_camera_get_target_position)
	lua.setfield(L, -2, "get_target_position")
	lua.pushcfunction(L, lua_camera_set_target_position)
	lua.setfield(L, -2, "set_target_position")
	lua.pushcfunction(L, lua_camera_set_target)
	lua.setfield(L, -2, "set_target")
	lua.pushcfunction(L, lua_camera_add_target)
	lua.setfield(L, -2, "add_target")
	lua.pushcfunction(L, lua_camera_remove_target)
	lua.setfield(L, -2, "remove_target")
	lua.pushcfunction(L, lua_camera_clear_targets)
	lua.setfield(L, -2, "clear_targets")
	lua.pushcfunction(L, lua_camera_get_target)
	lua.setfield(L, -2, "get_target")
	lua.pushcfunction(L, lua_camera_get_targets)
	lua.setfield(L, -2, "get_targets")
	lua.pushcfunction(L, lua_camera_get_zoom)
	lua.setfield(L, -2, "get_zoom")
	lua.pushcfunction(L, lua_camera_set_zoom)
	lua.setfield(L, -2, "set_zoom")
	lua.pushcfunction(L, lua_camera_get_offset)
	lua.setfield(L, -2, "get_offset")
	lua.pushcfunction(L, lua_camera_set_offset)
	lua.setfield(L, -2, "set_offset")
	lua.pushcfunction(L, lua_camera_get_rotation)
	lua.setfield(L, -2, "get_rotation")
	lua.pushcfunction(L, lua_camera_set_rotation)
	lua.setfield(L, -2, "set_rotation")
	lua.pushcfunction(L, lua_camera_shake)
	lua.setfield(L, -2, "shake")
	lua.pushcfunction(L, lua_camera_stop_shake)
	lua.setfield(L, -2, "stop_shake")
	lua.pushcfunction(L, lua_camera_is_shaking)
	lua.setfield(L, -2, "is_shaking")
	lua.pushcfunction(L, lua_camera_set_limits)
	lua.setfield(L, -2, "set_limits")
	lua.pushcfunction(L, lua_camera_clear_limits)
	lua.setfield(L, -2, "clear_limits")
	lua.pushcfunction(L, lua_camera_screen_to_world)
	lua.setfield(L, -2, "screen_to_world")
	lua.pushcfunction(L, lua_camera_world_to_screen)
	lua.setfield(L, -2, "world_to_screen")
	lua.pushcfunction(L, lua_camera_get_visible_world_bounds)
	lua.setfield(L, -2, "get_visible_world_bounds")
	lua.setglobal(L, "Camera")

	// 6. Global "Physics" table
	lua.newtable(L)
	lua.pushcfunction(L, lua_physics_get_gravity)
	lua.setfield(L, -2, "get_gravity")
	lua.pushcfunction(L, lua_physics_set_gravity)
	lua.setfield(L, -2, "set_gravity")
	lua.pushcfunction(L, lua_physics_is_paused)
	lua.setfield(L, -2, "is_paused")
	lua.pushcfunction(L, lua_physics_set_paused)
	lua.setfield(L, -2, "set_paused")
	lua.pushcfunction(L, lua_physics_raycast)
	lua.setfield(L, -2, "raycast")
	lua.pushcfunction(L, lua_physics_layer_name)
	lua.setfield(L, -2, "layer_name")
	lua.setglobal(L, "Physics")

	// 7. Global "Scene" table
	lua.newtable(L)
	lua.pushcfunction(L, lua_scene_find_node)
	lua.setfield(L, -2, "find_node")
	lua.pushcfunction(L, lua_scene_find_by_tag)
	lua.setfield(L, -2, "find_by_tag")
	lua.pushcfunction(L, lua_scene_set_ambient)
	lua.setfield(L, -2, "set_ambient")
	lua.pushcfunction(L, lua_scene_get_ambient)
	lua.setfield(L, -2, "get_ambient")
	lua.pushcfunction(L, lua_scene_get_name)
	lua.setfield(L, -2, "get_name")
	lua.pushcfunction(L, lua_scene_change_scene)
	lua.setfield(L, -2, "change_scene")
	lua.pushcfunction(L, lua_scene_preload)
	lua.setfield(L, -2, "preload")
	lua.pushcfunction(L, lua_scene_preload_progress)
	lua.setfield(L, -2, "preload_progress")
	lua.pushcfunction(L, lua_scene_is_transitioning)
	lua.setfield(L, -2, "is_transitioning")
	lua.pushcfunction(L, lua_scene_reload)
	lua.setfield(L, -2, "reload")
	lua.pushcfunction(L, lua_scene_get_nodes)
	lua.setfield(L, -2, "get_nodes")
	lua.pushcfunction(L, lua_scene_create_node)
	lua.setfield(L, -2, "create_node")
	lua.pushcfunction(L, lua_scene_get_draw_bounds)
	lua.setfield(L, -2, "get_draw_bounds")
	lua.pushcfunction(L, lua_scene_set_draw_bounds)
	lua.setfield(L, -2, "set_draw_bounds")
	lua.setglobal(L, "Scene")
	Script_RegisterTweenModule(L)
	Script_RegisterSaveModule(L)
	lua.newtable(L)
	lua.pushcfunction(L, lua_navigation_find_path)
	lua.setfield(L, -2, "find_path")
	lua.setglobal(L, "Navigation")
	lua.pushcfunction(L, lua_tr)
	lua.setglobal(L, "tr")
	lua.newtable(L)
	lua.pushcfunction(L, lua_locale_set)
	lua.setfield(L, -2, "set")
	lua.pushcfunction(L, lua_locale_get)
	lua.setfield(L, -2, "get")
	lua.pushcfunction(L, lua_locale_languages)
	lua.setfield(L, -2, "languages")
	lua.setglobal(L, "Locale")

	// 8. Global "Log" table
	lua.newtable(L)
	lua.pushcfunction(L, lua_log_info)
	lua.setfield(L, -2, "info")
	lua.pushcfunction(L, lua_log_warn)
	lua.setfield(L, -2, "warn")
	lua.pushcfunction(L, lua_log_error)
	lua.setfield(L, -2, "error")
	lua.setglobal(L, "Log")

	// 9. Global "Project" table
	lua.newtable(L)
	lua.pushcfunction(L, lua_project_load)
	lua.setfield(L, -2, "load")
	lua.pushcfunction(L, lua_project_export_ore)
	lua.setfield(L, -2, "export_ore")
	lua.pushcfunction(L, lua_project_serialize_scene)
	lua.setfield(L, -2, "serialize_scene")
	lua.pushcfunction(L, lua_project_read_file)
	lua.setfield(L, -2, "read_file")
	lua.pushcfunction(L, lua_project_has_file)
	lua.setfield(L, -2, "has_file")
	lua.setglobal(L, "Project")

	// 10. Override standard Lua "print" to use Log.info
	lua.pushcfunction(L, lua_log_info)
	lua.setglobal(L, "print")
}
