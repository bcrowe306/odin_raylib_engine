package engine

import vmem "core:mem/virtual"
import "core:log"
import rl "vendor:raylib"

SceneSetupProc :: proc(scene: ^Scene, gameContext: ^GameContext)
SceneUpdateProc :: proc(scene: ^Scene, gameContext: ^GameContext, deltaTime: f32)
SceneLifecycleProc :: proc(scene: ^Scene, gameContext: ^GameContext)

Scene :: struct {
	manager: ^NodeManager,
	name: string,
	drawBounds: bool,
	rootNode: ^Node,
	camera: ^CameraNode,
	setup: SceneSetupProc,
	update: SceneUpdateProc,
	onEnter: SceneLifecycleProc,
	onExit: SceneLifecycleProc,
	addNode: proc(scene: ^Scene, node: ^Node, parent: ^Node = nil),
	removeNode: proc(scene: ^Scene, node: ^Node),
	addChild: proc(scene: ^Scene, parent, child: ^Node),
	removeChild: proc(scene: ^Scene, parent, child: ^Node),
	isLoaded: bool,
}

CreateNodeScene :: proc(scene: ^Scene, $T: typeid, addToScene: bool = false) -> (node: ^T) {
	allocator := vmem.arena_allocator(&scene.manager.arena)
	node = new(T, allocator)
	InitializeNode(cast(^Node)node)
	if addToScene do SceneAddNode(scene, node)
	return node
}

SceneAddNode :: proc(scene: ^Scene, node: ^Node, parent: ^Node = nil) {
	_, err := append(&scene.manager.addition, node)
	if err != nil {
		log.error("Error queueing node for addition. ", err)
		return
	}
	if parent == nil && scene.rootNode != node {
		AddChild(scene.manager, scene.rootNode, node)
	} else if parent != nil {
		AddChild(scene.manager, parent, node)
	}
}

SceneRemoveNode :: proc(scene: ^Scene, node: ^Node) {
	RemoveNode(scene.manager, node)
}

SceneAddChild :: proc(scene: ^Scene, parent, child: ^Node) {
	AddChild(scene.manager, parent, child)
}

SceneRemoveChild :: proc(scene: ^Scene, parent, child: ^Node) {
	RemoveChild(scene.manager, parent, child)
}

CreateScene :: proc(manager: ^SceneManager, name: string, next_scene: bool, setup: SceneSetupProc = nil) -> ^Scene {
	if existing, exists := &manager.scenes[name]; exists {
		TerminateScene(existing)
	}

	manager.scenes[name] = Scene{
		name = name,
		setup = setup,
	}

	newScene := &manager.scenes[name]
	InitializeScene(newScene)
	if next_scene do manager.nextScene = newScene
	return &manager.scenes[name]
}

InitializeScene :: proc(scene: ^Scene) {
	scene.manager = new(NodeManager)
	NodeManager_Init(scene.manager)
	scene.rootNode = CreateNode(scene.manager, Node)
	scene.rootNode.name = "root"
	scene.rootNode.isReady = true
	scene.camera = nil
	SceneAddNode(scene, scene.rootNode)
	scene.isLoaded = false

	// Methods
	scene.addNode = SceneAddNode
	scene.removeNode = SceneRemoveNode
	scene.addChild = SceneAddChild
	scene.removeChild = SceneRemoveChild
}

// Unload all nodes in the scene, calling onDestroy on each, reclaiming node memory,
// and resetting state so the scene can be reloaded fresh.
Scene_Unload :: proc(scene: ^Scene, gameContext: ^GameContext = nil) {
	if scene == nil || scene.manager == nil do return

	if gameContext != nil {
		for node in scene.manager.nodes {
			if node != nil {
				node.gameContext = gameContext
				node.onExit->notify(node, false, gameContext)
			}
		}
	}

	scene.camera = nil

	NodeManager_Terminate(scene.manager)
	NodeManager_Init(scene.manager)

	scene.rootNode = CreateNode(scene.manager, Node)
	scene.rootNode.name = "root"
	scene.rootNode.isReady = true
	SceneAddNode(scene, scene.rootNode)
	ProcessNodeQueues(scene.manager, gameContext)

	scene.isLoaded = false
}

// Loads the scene: calls setup to create all initial nodes, registers them into
// the node manager, computes global positions, and then calls ready on all initial nodes.
Scene_Load :: proc(scene: ^Scene, gameContext: ^GameContext) {
	if scene == nil do return
	if gameContext != nil {
		gameContext.scene = scene
	}
	if scene.manager == nil {
		InitializeScene(scene)
	} else if scene.isLoaded {
		Scene_Unload(scene, gameContext)
	}

	// 1. Run setup callback to construct all initial scene nodes
	if scene.setup != nil {
		scene->setup(gameContext)
	}

	// 2. Process node queues so all initial nodes are present in manager.nodes
	ProcessNodeQueues(scene.manager, gameContext)

	// 3. Propagate initial global positions
	Node_SetGlobalPositions(scene.manager, scene.rootNode)

	// 4. Now that ALL other initial scene nodes are present, call ready on all nodes!
	Scene_CallReady(scene, scene.rootNode, gameContext)

	scene.isLoaded = true
}

// Recursively calls ready on all unready nodes in the hierarchy.
// Each node has ready called exactly once.
Scene_CallReady :: proc(scene: ^Scene, node: ^Node, gameContext: ^GameContext) {
	if node == nil || !node.enabled do return

	if !node.isReady {
		node.isReady = true
		if node.ready != nil {
			node->ready(gameContext)
		}
	}

	children := GetChildren(scene.manager, node)
	defer delete(children)
	for child in children {
		Scene_CallReady(scene, child, gameContext)
	}
}

TerminateScene :: proc(scene: ^Scene) {
	if scene == nil do return
	if scene.manager != nil {
		NodeManager_Terminate(scene.manager)
		free(scene.manager)
		scene.manager = nil
	}
	scene.rootNode = nil
	scene.camera = nil
	scene.isLoaded = false
}

RunScene :: proc(scene: ^Scene, gameContext: ^GameContext, deltaTime: f32) {
	if scene == nil || scene.manager == nil {
		return
	}

	if !scene.isLoaded {
		Scene_Load(scene, gameContext)
	}

	if gameContext != nil {
		gameContext.camera = scene.camera
	}

	nodeManager := scene.manager

	// Process Node Queues (any spawned or removed nodes)
	ProcessNodeQueues(nodeManager, gameContext)

	// Ensure any newly added nodes have their ready proc called before update
	Scene_CallReady(scene, scene.rootNode, gameContext)

	if scene.update != nil {
		scene->update(gameContext, deltaTime)
	}

	if scene.rootNode == nil {
		return
	}

	// Propagate initial global positions before hierarchy update
	Node_SetGlobalPositions(nodeManager, scene.rootNode)

	// Update active dropdown popup first so it can capture clicks before underlying widgets
	UI_UpdateActiveDropdownOverlay(gameContext)

	// Update UI keyboard navigation and focus state
	UI_UpdateFocusNavigation(scene, gameContext)

	// Update hierarchy (calls update on each node)
	Scene_UpdateNodeHirearchy(scene, scene.rootNode, gameContext, deltaTime)

	// Update global positions after node updates & container layout
	Node_SetGlobalPositions(nodeManager, scene.rootNode)

	for layer in RenderLayer {
		isWorldLayer := scene.camera != nil && scene.camera.enabled && scene.camera.isCurrent && (layer in scene.camera.targetLayers)
		if isWorldLayer && rl.IsWindowReady() {
			vw: f32 = 1280
			vh: f32 = 720
			if gameContext != nil && gameContext.game != nil && gameContext.game.virtualSize.x > 0 {
				vw = gameContext.game.virtualSize.x
				vh = gameContext.game.virtualSize.y
			}
			CameraNode_Begin(scene.camera, vw, vh)
		}

		Scene_RenderNodeHirearchy(scene, scene.rootNode, gameContext, deltaTime, layer)

		if isWorldLayer && rl.IsWindowReady() {
			CameraNode_End()
		}
	}

	// Render any active UI popups/dropdowns on top of all layers
	UI_RenderActiveDropdownOverlay(gameContext)
}

Scene_UpdateNodeHirearchy :: proc(scene: ^Scene, node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if node == nil || !node.enabled do return

	if !node.isReady {
		node.isReady = true
		if node.ready != nil do node->ready(gameContext)
	}

	children := GetChildren(scene.manager, node)
	defer delete(children)

	if node.update != nil do node->update(gameContext, deltaTime)

	for child in children {
		Scene_UpdateNodeHirearchy(scene, child, gameContext, deltaTime)
	}
}

Scene_RenderNodeHirearchy :: proc(scene: ^Scene, node: ^Node, gameContext: ^GameContext, deltaTime: f32, layer: RenderLayer) {
	if node == nil || !node.enabled do return
	children := GetChildren(scene.manager, node)

	defer delete(children)
	if node.renderable && node.layer == layer {
		if node.render != nil do node->render(gameContext, deltaTime)

		if scene.drawBounds && node.drawBounds != nil do node->drawBounds(gameContext, deltaTime)
	}

	for child in children {
		Scene_RenderNodeHirearchy(scene, child, gameContext, deltaTime, layer)
	}
}
