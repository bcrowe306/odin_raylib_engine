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

	// Rename child2 to "Player" -> should generate unique child name "Player_1" or similar
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
