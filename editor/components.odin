package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"

// ============================================================================
// Components (prefabs). A component file holds a node subtree; scenes keep
// *linked* instances of it (the scene stores only the instance's link, name
// and transform). "Edit Component" opens the file as its own document;
// saving it refreshes every instance in the open scenes.
// Built-in templates are snippets that are copied, not linked.
// ============================================================================

Component_Instantiate :: proc(state: ^EditorState, comp: ^ComponentDef, targetPos: [2]f32) -> ^e.Node {
	if state == nil || comp == nil do return nil
	return Editor_InstantiateComponentJSON(state, transmute([]u8)comp.jsonSnippet, targetPos, comp.name)
}

Component_InstantiateFromFile :: proc(state: ^EditorState, filePath: string, targetPos: [2]f32) -> ^e.Node {
	if state == nil do return nil
	return Editor_InstantiateComponentFile(state, asset_rel_editor(state, filePath), targetPos)
}

Component_SaveNodeToFile :: proc(state: ^EditorState, node: ^e.Node, outPath: string = "") -> bool {
	_, ok := Editor_SaveComponent(state, node)
	return ok
}

Editor_IsComponentDoc :: proc(state: ^EditorState, scene: ^e.Scene) -> bool {
	return scene != nil && state.componentDocs[scene]
}

// Editor_OpenComponent opens a component file for editing, as a document
// whose root holds the component's node.
Editor_OpenComponent :: proc(state: ^EditorState, rel: string) -> bool {
	for scene, _ in state.componentDocs {
		if scene.filePath == rel {
			Editor_SwitchView(state, scene)
			state.activeScene = scene
			state.game.sceneManager.currentScene = scene
			state.game.gameContext.scene = scene
			delete(state.activeScenePath)
			state.activeScenePath = strings.clone(rel)
			state.selectedNode = nil
			return true
		}
	}
	data, ok := e.Component_ReadFile(&state.game.gameContext, rel)
	if !ok {
		Editor_Log(state, .Error, "Component file not found: %s", rel)
		return false
	}
	// A document closed before keeps its (unloaded) scene: reuse it.
	scene := state.game.sceneManager.scenes[fmt.tprintf("component:%s", rel)]
	if scene == nil do scene = state.game->createScene(fmt.tprintf("component:%s", rel), false)
	scene.filePath = strings.clone(rel, state.game.sceneManager.allocator)
	scene.rootNode.gameContext = &state.game.gameContext
	node := e.Scene_InstantiateNodeFromJSON(scene, data, scene.rootNode, &state.game.gameContext)
	if node != nil do node.position = {0, 0}
	e.ProcessNodeQueues(scene.manager, &state.game.gameContext)
	e.Node_SetGlobalPositions(scene.manager, scene.rootNode)
	scene.isLoaded = true
	state.componentDocs[scene] = true
	Editor_SetSceneBaseline(state, scene)
	Editor_SwitchView(state, scene)
	state.sceneViews[scene] = {0, 0, 1}
	state.activeScene = scene
	state.game.sceneManager.currentScene = scene
	state.game.gameContext.scene = scene
	delete(state.activeScenePath)
	state.activeScenePath = strings.clone(rel)
	state.selectedNode = node
	state.cameraPos = {0, 0}
	state.cameraZoom = 1
	Editor_Log(state, .Info, "Editing component %s - save to update its instances", rel)
	return true
}

// Editor_SaveComponentDoc writes a component document back to its file and
// refreshes the instances in every open scene.
Editor_SaveComponentDoc :: proc(state: ^EditorState, scene: ^e.Scene) -> bool {
	children := e.GetChildrenView(scene.manager, scene.rootNode)
	if len(children) == 0 {
		Editor_Log(state, .Error, "Component document is empty")
		return false
	}
	json := e.Node_SerializeToJSON(children[0], scene.manager, context.temp_allocator)
	disk, _ := filepath.join({state.projectPath, scene.filePath}, context.temp_allocator)
	// Undo puts the file (and so the instances) back (#76).
	Editor_RecordFileUndo(state, scene.filePath, fmt.tprintf("Save %s", scene.filePath))
	Editor_InvalidateProjectFiles() // the asset lists rescan
	if os.write_entire_file(disk, transmute([]u8)json) != nil {
		Editor_Log(state, .Error, "Failed to write %s", disk)
		return false
	}
	Editor_SetSceneBaseline(state, scene)
	sel := Editor_SaveSelection(state) // (Save All: the active scene may have instances)
	refreshed := Editor_RefreshComponentInstances(state, scene.filePath)
	Editor_RestoreSelection(state, sel)
	Editor_Log(state, .Info, "Saved component %s (%d instance(s) updated)", scene.filePath, refreshed)
	return true
}

// Editor_RefreshComponentInstances rebuilds the instances of a component
// file in every open scene (not component documents, nor `skip`). Returns
// how many were rebuilt. When the active scene is refreshed, the caller
// keeps the selection (Editor_SaveSelection before any rebuild, #74).
Editor_RefreshComponentInstances :: proc(state: ^EditorState, rel: string, skip: ^e.Scene = nil) -> int {
	n := 0
	for _, s in state.game.sceneManager.scenes {
		if s == nil || s == skip || !s.isLoaded || Editor_IsComponentDoc(state, s) do continue
		n += e.Scene_RefreshComponentInstances(s, rel, &state.game.gameContext)
	}
	return n
}
