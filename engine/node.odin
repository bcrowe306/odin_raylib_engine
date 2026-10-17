package engine

import "core:log"
import "core:mem"
import "core:crypto"
import "core:encoding/uuid"
import vmem "core:mem/virtual"
import rl "vendor:raylib"

Node :: struct {
	id: uuid.Identifier,
	arena: vmem.Arena,
	allocator: mem.Allocator,
	resource: rawptr, // Pointer to the resource associated with this node. Used to give data to the node. Resoruce is stored on node's arena, and dealloc'd when node terminates.
	name: string, // Name of the node
	position: [2]f32 `gui:"true" min:"0" max:"1280"`,
	scale: [2]f32 `gui:"true" min:"0.01" max:"10"`,
	rotation: f32 `gui:"true" min:"0" max:"360"`,
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
	renderable: bool `gui:"true"`,
	enabled: bool `gui:"true"`,
	update: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32),
	render: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32),
	onDestroy: proc(node: ^Node, gameContext: ^GameContext),
	drawBounds: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32),
}

CreateNode :: proc(manager: ^NodeManager, $T: typeid) -> (node: ^T) {

	// Create allocator from the arena used to allocate the node
	allocator := vmem.arena_allocator(&manager.arena)
	node = new(T, allocator)
	genNode := cast(^Node)node
	InitializeNode(genNode)
	node = cast(^T)genNode
	return node
}

InitializeNode :: proc(node: ^Node) {
	if err := vmem.arena_init_growing(&node.arena); err != nil {
		log.panic("Error allocating node's arena", err)
	}
	node.allocator = vmem.arena_allocator(&node.arena)
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

Node_AddResource :: proc(node: ^Node, $T: typeid) -> ^T {
	resource, err := new(T, node.allocator)
	if err != nil {
		log.panic("Error allocating resource for node", err)
	}
	node.resource = cast(rawptr)resource
	return resource
}


Node_Terminate :: proc(node: ^Node) {
	if node.onDestroy != nil {
		node.onDestroy(node, node.gameContext)
	}
	// Terminate the arena used to allocate any resources on the node.
	vmem.arena_free_all(&node.arena)
}
