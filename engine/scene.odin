package engine

import "core:fmt"
import vmem "core:mem/virtual"
import "core:log"

Scene :: struct {
	manager: ^NodeManager,
	name: string,
	drawBounds: bool,
	rootNode: ^Node,
	update: proc(scene: ^Scene, gameContext: ^GameContext, deltaTime: f32),
	addNode: proc(scene: ^Scene, node: ^Node, parent: ^Node = nil),
	removeNode: proc(scene: ^Scene, node: ^Node),
	addChild: proc(scene: ^Scene, parent, child: ^Node),
	removeChild: proc(scene: ^Scene, parent, child: ^Node),
}

CreateNodeScene :: proc(scene: ^Scene, $T: typeid) -> (node: ^T) {
	allocator := vmem.arena_allocator(&scene.manager.arena)
	node = new(T, allocator)
	return node
}

SceneAddNode :: proc(scene: ^Scene, node: ^Node, parent: ^Node = nil) {
	_, err :=	append(&scene.manager.addition, node)
	if err != nil {
		log.error("Error queueing node for addition. ", err )
		return
	}
	if parent == nil && scene.rootNode != node {
		AddChild(scene.manager, scene.rootNode, node)
	}
	else {
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


CreateScene :: proc(manager: ^SceneManager, name: string, next_scene: bool) -> ^Scene {
	manager.scenes[name] = Scene{
		name = name
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
	SceneAddNode(scene, scene.rootNode)

	// Methods
	scene.addNode = SceneAddNode
	scene.removeNode = SceneRemoveNode
	scene.addChild = SceneAddChild
	scene.removeChild = SceneRemoveChild
}

RunScene :: proc(scene: ^Scene, gameContext: ^GameContext, deltaTime: f32) {
	if scene == nil {
		return
	}
	nodeManager := scene.manager

	// Process Node Queues
	ProcessNodeQueues(nodeManager, gameContext)

	if scene.update != nil {
		scene->update(gameContext, deltaTime)
	}

	// Update
	Scene_UpdateNodeHirearchy(scene, scene.rootNode, gameContext, deltaTime)


	// Update global positions
	Node_SetGlobalPositions(nodeManager, scene.rootNode)


	for layer in RenderLayer {
		Scene_RenderNodeHirearchy(scene, scene.rootNode, gameContext, deltaTime, layer)
	}
}


Scene_UpdateNodeHirearchy :: proc(scene: ^Scene, node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	children := GetChildren(scene.manager, node)
	defer delete(children)
	if node.update != nil do node->update(gameContext, deltaTime)
	for child in children {
		Scene_UpdateNodeHirearchy(scene, child, gameContext, deltaTime)
	}
}

Scene_RenderNodeHirearchy :: proc(scene: ^Scene, node: ^Node, gameContext: ^GameContext, deltaTime: f32, layer: RenderLayer) {
	children := GetChildren(scene.manager, node)

	defer delete(children)
	if node.renderable {
		if node.render != nil do node->render(gameContext, deltaTime)

		if scene.drawBounds && node.drawBounds != nil do node->drawBounds(gameContext, deltaTime)
	}

	for child in children {
		Scene_RenderNodeHirearchy(scene, child, gameContext, deltaTime, layer)
	}
}
