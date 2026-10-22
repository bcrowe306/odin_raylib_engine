package engine

import vmem "core:mem/virtual"
import "core:log"
import "core:strings"
import rl "vendor:raylib"

SceneSetupProc :: proc(scene: ^Scene, gameContext: ^GameContext)
SceneUpdateProc :: proc(scene: ^Scene, gameContext: ^GameContext, deltaTime: f32)
SceneLifecycleProc :: proc(scene: ^Scene, gameContext: ^GameContext)

Scene :: struct {
	manager: ^NodeManager,
	name: string,
	filePath: string,   // project-relative scene file ("scenes/main.scene.json"), "" for code scenes
	sourceJson: string, // scene file contents; rebuilt from on every (re)load
	drawBounds: bool,
	// Clear colour while this scene runs (alpha 0 = the game's default).
	backgroundColor: rl.Color,
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
	(cast(^Node)node).typeId = T
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

// CreateScene registers a new scene under `name` (cloned). A scene with the
// same name is replaced: it is terminated and any current/next pointer to it
// is cleared, so nothing keeps pointing at the destroyed scene.
CreateScene :: proc(manager: ^SceneManager, name: string, next_scene: bool, setup: SceneSetupProc = nil) -> ^Scene {
	allocator := manager.allocator if manager.allocator.procedure != nil else context.allocator
	if existing, exists := manager.scenes[name]; exists && existing != nil {
		if manager.currentScene == existing do manager.currentScene = nil
		if manager.nextScene == existing do manager.nextScene = nil
		TerminateScene(existing)
	}

	newScene := new(Scene, allocator)
	ownedName := strings.clone(name, allocator)
	newScene.name = ownedName
	newScene.setup = setup
	manager.scenes[ownedName] = newScene

	InitializeScene(newScene)
	if next_scene do manager.nextScene = newScene
	return newScene
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
				node.onExit->notify(node, nil, gameContext)
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

	if gameContext != nil {
		node.gameContext = gameContext
	}

	if !node.isReady {
		node.isReady = true
		if node.ready != nil {
			node->ready(gameContext)
		}
		if node.scriptInstance != nil {
			sm := gameContext.scriptManager if gameContext != nil else nil
			ScriptInstance_CallReady(cast(^ScriptInstance)node.scriptInstance, sm)
		}
	}

	for child in GetChildrenTemp(scene.manager, node) {
		Scene_CallReady(scene, child, gameContext)
	}
}

// Scene_JsonSetup is the setup proc of data-driven scenes: it rebuilds the
// scene from its stored JSON each time the scene is loaded, so leaving and
// re-entering a scene restores it instead of leaving it empty.
Scene_JsonSetup :: proc(scene: ^Scene, gameContext: ^GameContext) {
	if scene.sourceJson == "" do return
	Scene_InstantiateFromJSON(scene, transmute([]u8)scene.sourceJson, gameContext)
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

	// One traversal buckets renderable nodes by layer (hierarchy order is
	// kept within a layer) instead of walking the whole tree per layer.
	buckets := Scene_CollectRenderables(scene)
	renderStats = {}
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
			Render_SetView(Camera2D_ViewRect(CameraNode_GetCamera2D(scene.camera, vw, vh), vw, vh))
		}

		render_bucket(scene, buckets[layer][:], gameContext, deltaTime)

		if isWorldLayer && rl.IsWindowReady() {
			Render_ClearView()
			CameraNode_End()
		}
	}

	// Render any active UI popups/dropdowns on top of all layers
	UI_RenderActiveDropdownOverlay(gameContext)
}

Scene_UpdateNodeHirearchy :: proc(scene: ^Scene, node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if node == nil || !node.enabled do return

	if gameContext != nil {
		node.gameContext = gameContext
	}

	if !node.isReady {
		node.isReady = true
		if node.ready != nil do node->ready(gameContext)
		if node.scriptInstance != nil {
			sm := gameContext.scriptManager if gameContext != nil else nil
			ScriptInstance_CallReady(cast(^ScriptInstance)node.scriptInstance, sm)
		}
	}

	// Copy: updates may add or remove children while we iterate.
	children := GetChildrenTemp(scene.manager, node)

	if node.update != nil do node->update(gameContext, deltaTime)
	if node.scriptInstance != nil {
		sm := gameContext.scriptManager if gameContext != nil else nil
		ScriptInstance_CallUpdate(cast(^ScriptInstance)node.scriptInstance, deltaTime, sm)
	}

	for child in children {
		Scene_UpdateNodeHirearchy(scene, child, gameContext, deltaTime)
	}
}

Scene_RenderNodeHirearchy :: proc(scene: ^Scene, node: ^Node, gameContext: ^GameContext, deltaTime: f32, layer: RenderLayer) {
	if node == nil || !node.enabled do return
	children := GetChildrenView(scene.manager, node)
	if node.renderable && node.layer == layer {
		if node.render != nil do node->render(gameContext, deltaTime)

		if scene.drawBounds && node.drawBounds != nil do node->drawBounds(gameContext, deltaTime)
	}

	for child in children {
		Scene_RenderNodeHirearchy(scene, child, gameContext, deltaTime, layer)
	}
}

Scene_FindNodeByName :: proc(scene: ^Scene, name: string) -> ^Node {
	if scene == nil || scene.manager == nil do return nil
	for node in scene.manager.nodes {
		if node != nil && node.name == name do return node
	}
	for node in scene.manager.addition {
		if node != nil && node.name == name do return node
	}
	return nil
}

// Scene_FindNodeByType returns the first node of the given concrete type.
Scene_FindNodeByType :: proc(scene: ^Scene, t: typeid) -> ^Node {
	if scene == nil || scene.manager == nil do return nil
	for node in scene.manager.nodes {
		if node != nil && node.typeId == t do return node
	}
	for node in scene.manager.addition {
		if node != nil && node.typeId == t do return node
	}
	return nil
}

// Scene_RenderAllLayers draws every layer in order from one traversal, with
// whatever 2D camera is active (the editor viewport's), culled to `view`
// when given. The game uses RunScene, which also switches to the scene
// camera per world layer.
Scene_RenderAllLayers :: proc(scene: ^Scene, gameContext: ^GameContext, deltaTime: f32, view: Maybe(rl.Rectangle) = nil) {
	buckets := Scene_CollectRenderables(scene)
	renderStats = {}
	if v, ok := view.?; ok do Render_SetView(v)
	defer Render_ClearView()
	for layer in RenderLayer do render_bucket(scene, buckets[layer][:], gameContext, deltaTime)
}

// render_bucket draws one layer's nodes, skipping those outside the view.
@(private = "file")
render_bucket :: proc(scene: ^Scene, nodes: []^Node, gameContext: ^GameContext, deltaTime: f32) {
	for node in nodes {
		if renderView.active {
			if r, ok := Node_RenderBounds(node); ok && !Render_IsVisible(r) {
				renderStats.culled += 1
				continue
			}
		}
		renderStats.drawn += 1
		withMaterial := node.material != nil && Material_Begin(node, gameContext)
		if node.render != nil do node->render(gameContext, deltaTime)
		if withMaterial do Material_End(node)
		if scene.drawBounds && node.drawBounds != nil do node->drawBounds(gameContext, deltaTime)
	}
}

// Scene_CollectRenderables walks the enabled hierarchy once and returns the
// renderable nodes of each layer in draw order (temp-allocated).
Scene_CollectRenderables :: proc(scene: ^Scene) -> (buckets: [RenderLayer][dynamic]^Node) {
	for &b in buckets do b = make([dynamic]^Node, context.temp_allocator)
	walk :: proc(m: ^NodeManager, node: ^Node, buckets: ^[RenderLayer][dynamic]^Node) {
		if node == nil || !node.enabled do return
		if node.renderable && (node.render != nil || node.drawBounds != nil) {
			append(&buckets[node.layer], node)
		}
		for child in GetChildrenView(m, node) do walk(m, child, buckets)
	}
	if scene != nil && scene.manager != nil do walk(scene.manager, scene.rootNode, &buckets)
	return
}
