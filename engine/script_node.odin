package engine

import "core:strings"

// ============================================================================
// ScriptNode: Specialized Engine Node Hosting a Lua Script
// ============================================================================

ScriptNode :: struct {
	using node: Node,
	scriptPath: string,
}

ScriptNode_Init :: proc(snode: ^ScriptNode) {
	InitializeNode(snode)
	snode.typeId = ScriptNode
}

ScriptNode_Create :: proc(
	scene: ^Scene,
	scriptPath: string,
	name: string = "",
	overrides: map[string]ScriptValue = nil,
	parent: ^Node = nil,
	sm: ^ScriptManager = nil,
) -> ^ScriptNode {
	if scene == nil || scene.manager == nil do return nil

	snode := CreateNode(scene.manager, ScriptNode)
	ScriptNode_Init(snode)

	snode.name = name if name != "" else scriptPath
	snode.scriptPath = strings.clone(scriptPath, snode.allocator)
	snode.gameContext = scene.rootNode.gameContext if scene.rootNode != nil else nil

	// Attach Lua script logic
	mgr := sm
	if mgr == nil && snode.gameContext != nil {
		mgr = snode.gameContext.scriptManager
	}
	Script_AttachToNode(snode, scriptPath, overrides, mgr)

	if parent != nil {
		SceneAddChild(scene, parent, snode)
	} else {
		SceneAddNode(scene, snode)
	}

	return snode
}
