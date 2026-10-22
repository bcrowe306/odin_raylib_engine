package engine

import "core:math/rand"

import "base:runtime"

import "core:log"
import "core:mem"
import "core:crypto"
import "core:encoding/uuid"
import vmem "core:mem/virtual"

Node :: struct {
	id: uuid.Identifier,
	typeId: typeid, // Concrete runtime type of the node (e.g. Node, TextureNode, DynamicBodyNode)
	arena: vmem.Arena,
	allocator: mem.Allocator,
	resource: rawptr, // Pointer to the resource associated with this node. Used to give data to the node. Resoruce is stored on node's arena, and dealloc'd when node terminates.
	scriptInstance: rawptr, // Pointer to ScriptInstance attached to this node
	name: string, // Name of the node
	// Linked prefab instance: project-relative component file this node was
	// instantiated from ("" = not an instance). Its subtree comes from that
	// file; the scene stores only the instance's name and transform.
	componentPath: string,
	// The (normalized) component JSON the instance was built from; overrides
	// are what differs from it (component_overrides.odin).
	componentBase: string,
	// Saved signal connections from this node's events to script methods
	// (signals.odin).
	signalConnections: [dynamic]Signal_Connection,
	// Runtime-only node (built by another node, e.g. LDtk colliders and
	// spawned entities): never saved with the scene.
	transient: bool,
	// Shader / blend mode / shader parameters applied around render (nil =
	// plain drawing; material.odin).
	material: ^Material,
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
	isReady: bool,
	isUI: bool,
	ready: proc(node: ^Node, gameContext: ^GameContext),
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
	genNode.typeId = T
	node = cast(^T)genNode
	return node
}

// Node creation cost: every node owns a virtual-memory arena and a UUID.
// Arenas of destroyed nodes are recycled (reserving virtual memory is the
// expensive part), and UUIDs come from a fast generator seeded once from
// the OS (they only need to be unique, not unpredictable).
@(private = "file")
arenaPool: [dynamic]vmem.Arena
@(private = "file")
ARENA_POOL_MAX :: 16384
// First block of a node arena; most nodes need a few hundred bytes, the
// arena grows when one needs more.
NODE_ARENA_BLOCK :: 64 * mem.Kilobyte
@(private = "file")
idState: runtime.Default_Random_State
@(private = "file")
idSeeded: bool

@(private = "file")
node_new_id :: proc() -> uuid.Identifier {
	if !idSeeded {
		seed: [16]u8
		crypto.rand_bytes(seed[:])
		idState = rand.create(seed[:])
		idSeeded = true
	}
	context.random_generator = runtime.default_random_generator(&idState)
	return uuid.generate_v4()
}

// Node_ReleaseArenaPool frees the recycled arenas (engine shutdown).
Node_ReleaseArenaPool :: proc() {
	for &a in arenaPool do vmem.arena_destroy(&a)
	delete(arenaPool)
	arenaPool = nil
}

InitializeNode :: proc(node: ^Node) {
	if node.arena.total_reserved == 0 {
		if len(arenaPool) > 0 {
			node.arena = pop(&arenaPool)
		} else if err := vmem.arena_init_growing(&node.arena, NODE_ARENA_BLOCK); err != nil {
			log.panic("Error allocating node's arena", err)
		}
	}
	node.allocator = vmem.arena_allocator(&node.arena)
	// Typed *_Init procs call InitializeNode again after CreateNode: keep
	// one registry entry per node.
	if Node_IsAlive(node) do Node_Unregister(node)
	node.id = node_new_id()
	Node_Register(node)
	if node.typeId == nil {
		node.typeId = Node
	}
	node.position = {0, 0}
	node.scale = {1, 1}
	node.rotation = 0
	node.enabled = true
	node.renderable = true
	node.layer = RenderLayer.Layer1
	InitializeSubject(&node.onEnter, "entered_tree", node)
	InitializeSubject(&node.onExit, "exited_tree", node)
	InitializeSubject(&node.onChildAdded, "child_added", node)
	InitializeSubject(&node.onChildRemoved, "child_removed", node)
	InitializeSubject(&node.onParentAdded, "parent_added", node)
	InitializeSubject(&node.onParentRemoved, "parent_removed", node)
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
	if node == nil do return

	if node.onDestroy != nil {
		destroyProc := node.onDestroy
		node.onDestroy = nil
		destroyProc(node, node.gameContext)
	}

	// Destroy script instance if attached
	if node.scriptInstance != nil {
		inst := cast(^ScriptInstance)node.scriptInstance
		inst.node = nil
		node.scriptInstance = nil
		ScriptInstance_Destroy(inst)
	}

	DestroySubject(&node.onEnter)
	DestroySubject(&node.onExit)
	DestroySubject(&node.onChildAdded)
	DestroySubject(&node.onChildRemoved)
	DestroySubject(&node.onParentAdded)
	DestroySubject(&node.onParentRemoved)
	// Lua: drop connections to/from this node; references become nil.
	Script_ForgetNode(node)
	Node_Unregister(node)
	// Recycle the arena (keeps its first block reserved).
	if len(arenaPool) < ARENA_POOL_MAX && node.arena.kind == .Growing && node.arena.curr_block != nil {
		vmem.arena_free_all(&node.arena)
		if arenaPool == nil do arenaPool = make([dynamic]vmem.Arena, 0, 256, runtime.heap_allocator())
		append(&arenaPool, node.arena)
	} else {
		vmem.arena_destroy(&node.arena)
	}
	node.arena = {}
}
