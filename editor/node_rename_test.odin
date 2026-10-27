package editor

import "core:testing"
import "core:strings"
import e "../engine"

@test
test_inline_node_rename_begin :: proc(t: ^testing.T) {
	scene := new(e.Scene)
	e.InitializeScene(scene)
	defer {
		e.TerminateScene(scene)
		free(scene)
	}

	state: EditorState
	state.activeScene = scene

	root := scene.rootNode
	testing.expect(t, root != nil)

	// 1. Root node cannot be renamed inline
	Editor_BeginInlineRename(&state, root)
	testing.expect(t, inlineRenameNode == nil, "Root node should not be inline renamable")

	// 2. Add a child node
	child := e.CreateNode(scene.manager, e.Node)
	child.name = strings.clone("TestChild", child.allocator)
	e.AddChild(scene.manager, root, child)

	// 3. Child node can begin inline rename
	Editor_BeginInlineRename(&state, child)
	testing.expect(t, inlineRenameNode == child, "inlineRenameNode should be child")
	testing.expect(t, inlineRenameFocus, "inlineRenameFocus should be true")
	testing.expect_value(t, string(cstring(raw_data(inlineRenameBuf[:]))), "TestChild")

	// 4. Locked node cannot begin inline rename
	child.editorLocked = true
	inlineRenameNode = nil
	Editor_BeginInlineRename(&state, child)
	testing.expect(t, inlineRenameNode == nil, "Locked node should not be inline renamable")

	inlineRenameNode = nil
}

@test
test_inline_node_rename_commit :: proc(t: ^testing.T) {
	scene := new(e.Scene)
	e.InitializeScene(scene)
	defer {
		e.TerminateScene(scene)
		free(scene)
	}

	state: EditorState
	state.activeScene = scene

	root := scene.rootNode
	child1 := e.CreateNode(scene.manager, e.Node)
	child1.name = strings.clone("Player", child1.allocator)
	e.AddChild(scene.manager, root, child1)

	child2 := e.CreateNode(scene.manager, e.Node)
	child2.name = strings.clone("Enemy", child2.allocator)
	e.AddChild(scene.manager, root, child2)

	// Rename child2 to "Player" -> should generate unique child name "Player2"
	Editor_BeginInlineRename(&state, child2)
	testing.expect(t, inlineRenameNode == child2)

	copy(inlineRenameBuf[:], "Player\x00")
	name := strings.trim_space(string(cstring(raw_data(inlineRenameBuf[:]))))
	if name != "" && name != child2.name && e.Node_IsAlive(child2) {
		parent := e.GetParent(state.activeScene.manager, child2)
		child2.name = strings.clone(Editor_UniqueChildName(&state, parent, name, child2), child2.allocator)
	}
	inlineRenameNode = nil

	testing.expect_value(t, child2.name, "Player2")

	// Rename child1 to "Spaceship"
	Editor_BeginInlineRename(&state, child1)
	copy(inlineRenameBuf[:], "Spaceship\x00")
	name2 := strings.trim_space(string(cstring(raw_data(inlineRenameBuf[:]))))
	if name2 != "" && name2 != child1.name && e.Node_IsAlive(child1) {
		parent := e.GetParent(state.activeScene.manager, child1)
		child1.name = strings.clone(Editor_UniqueChildName(&state, parent, name2, child1), child1.allocator)
	}
	inlineRenameNode = nil

	testing.expect_value(t, child1.name, "Spaceship")
}

@test
test_node_rename_scene_references :: proc(t: ^testing.T) {
	state: EditorState
	scene := new(e.Scene)
	e.InitializeScene(scene)
	state.activeScene = scene
	defer {
		for &u in state.undoStack {
			Undo_Release(u.json)
			delete(u.label)
			delete(u.selected)
		}
		delete(state.undoStack)
		delete(state.sceneVersion)
		Undo_ClearStore()
		NodeRefs_Clear()
		e.TerminateScene(scene)
		free(scene)
	}
	root := scene.rootNode

	// Create target node to be renamed
	target := cast(^e.Node)e.Node_CreateByTypeName(scene, "Node", root)
	target.name = strings.clone("HeroShip", target.allocator)

	// 1. Camera node following target
	cam := cast(^e.CameraNode)e.Node_CreateByTypeName(scene, "CameraNode", root)
	cam.name = strings.clone("MainCam", cam.allocator)
	cam.followTarget = strings.clone("../HeroShip", cam.allocator)

	// 2. Animation player with track targeting target
	apn := cast(^e.AnimationPlayerNode)e.Node_CreateByTypeName(scene, "AnimationPlayerNode", root)
	apn.name = strings.clone("AnimPlayer", apn.allocator)
	anim := e.AnimationPlayerNode_AddFrameAnimation(apn, nil, "Fly", nil)
	tr := e.Animation_AddTrack(apn, anim, "../HeroShip", "position")
	testing.expect(t, tr != nil)

	// 3. Button node with signal connection to target
	btn := cast(^e.Node)e.Node_CreateByTypeName(scene, "Node", root)
	btn.name = strings.clone("FireButton", btn.allocator)
	e.Node_AddConnection(btn, "pressed", "../HeroShip", "on_fire")

	e.ProcessNodeQueues(scene.manager, nil)

	// Verify all 3 point to target before rename
	testing.expect_value(t, e.Node_ResolvePath(scene.manager, cam, cam.followTarget), target)
	testing.expect_value(t, e.Node_ResolvePath(scene.manager, apn, tr.target), target)
	testing.expect_value(t, e.Node_ResolvePath(scene.manager, btn, btn.signalConnections[0].target), target)

	// Capture snapshot before rename
	snap := NodeRefs_Capture(&state)
	testing.expect(t, len(snap.sceneItems) >= 3, "should capture camera, anim track, and signal")

	// Rename target to "PlayerOne"
	target.name = strings.clone("PlayerOne", target.allocator)

	// Recompute references after rename
	NodeRefs_AfterChange(&state, snap)

	testing.expect(t, NodeRefs_IsOpen(), "refs dialog should open")
	edits := NodeRefs_SceneEdits()
	testing.expect_value(t, len(edits), 3)
	testing.expect_value(t, edits[0].newPath, "../PlayerOne")
	testing.expect_value(t, edits[1].newPath, "../PlayerOne")
	testing.expect_value(t, edits[2].newPath, "../PlayerOne")

	// Apply scene edits
	nScene, _ := NodeRefs_Apply(&state)
	testing.expect_value(t, nScene, 3)

	// Verify scene node paths are updated to PlayerOne
	testing.expect_value(t, cam.followTarget, "../PlayerOne")
	testing.expect_value(t, tr.target, "../PlayerOne")
	testing.expect_value(t, btn.signalConnections[0].target, "../PlayerOne")

	NodeRefs_Clear()
}
