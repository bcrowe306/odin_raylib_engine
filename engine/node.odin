package engine

import "core:crypto"
import "core:encoding/uuid"
import vmem "core:mem/virtual"
import rl "vendor:raylib"

Node :: struct {
	id: uuid.Identifier,
	name: string,
	position: [2]f32,
	scale: [2]f32,
	rotation: f32,
	globalPosition: [2]f32,
	globalScale: [2]f32,
	globalRotation: f32,
	layer: RenderLayer,
	gameContext: ^GameContext, // Node does not own this
	onEnter: EventSubject,
	onExit: EventSubject,
	onChildAdded: EventSubject,
	onChildRemoved: EventSubject,
	onParentAdded: EventSubject,
	onParentRemoved: EventSubject,
	renderable: bool,
	enabled: bool,
	update: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32),
	render: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32),
	onDestroy: proc(node: ^Node, gameContext: ^GameContext),
	drawBounds: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32),
}

CreateNode :: proc(manager: ^NodeManager, $T: typeid) -> (node: ^T) {
	allocator := vmem.arena_allocator(&manager.arena)
	node = new(T, allocator)
	genNode := cast(^Node)node
	InitializeNode(genNode)
	node = cast(^T)genNode
	return node
}

InitializeNode :: proc(node: ^Node) {
	context.random_generator = crypto.random_generator()
	node.id = uuid.generate_v4()
	node.position = {0, 0}
	node.scale = {1, 1}
	node.rotation = 0
	node.enabled = true
	InitializeSubject(&node.onEnter)
	InitializeSubject(&node.onExit)
	InitializeSubject(&node.onChildAdded)
	InitializeSubject(&node.onChildRemoved)
	InitializeSubject(&node.onParentAdded)
	InitializeSubject(&node.onParentRemoved)
	node.renderable = true
}
