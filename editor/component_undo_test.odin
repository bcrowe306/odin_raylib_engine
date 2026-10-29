package editor

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import e "../engine"

// #76: writing a component file (Apply to Component, saving a component
// document) is part of the undo step: Undo writes the file back and the
// instances follow it; Redo writes it again.
@(test)
test_component_file_undo :: proc(t: ^testing.T) {
	dir :: "test_component_undo"
	rel :: "components/crate.component.json"
	CRATE :: `{"type": "Node", "name": "Crate", "children": [{"type": "Node", "name": "Lid", "position": [0, -10]}]}`
	comps, _ := filepath.join({dir, "components"}, context.temp_allocator)
	_ = os.make_directory_all(comps)
	defer os.remove_all(dir)
	full, _ := filepath.join({dir, rel}, context.temp_allocator)
	_ = os.write_entire_file(full, transmute([]u8)string(CRATE))
	read :: proc(path: string) -> string {
		data, _ := os.read_entire_file(path, context.temp_allocator)
		return string(data)
	}
	lid_y :: proc(scene: ^e.Scene, inst: string) -> f32 {
		root := e.Scene_FindNodeByName(scene, inst)
		if root == nil do return 999
		for c in e.GetChildrenView(scene.manager, root) do if c.name == "Lid" do return c.position.y
		return 999
	}

	game := new(e.Game)
	e.InitializeGame(game)
	game.gameContext.isEditor = true
	e.AssetManager_SetProjectDir(&game.assetManager, dir)
	state: EditorState
	state.game = game
	state.projectPath = dir
	defer {
		for stack in ([]^[dynamic]Undo_Entry{&state.undoStack, &state.redoStack}) {
			for &u in stack do Undo_EntryDestroy(&u)
			delete(stack^)
		}
		for l in state.logs {
			delete(l.time)
			delete(l.message)
		}
		delete(state.logs)
		delete(state.selection)
		delete(state.sceneVersion)
		delete(state.savedVersion)
		for _, b in state.sceneBaselines do delete(b)
		delete(state.sceneBaselines)
		delete(state.componentDocs)
		Undo_ClearStore()
		game->terminate()
		e.Component_ClearCaches()
	}
	ctx := &game.gameContext

	scene := game->createScene("main", true)
	scene.isLoaded = true
	state.activeScene = scene
	a := e.Scene_InstantiateComponent(scene, rel, nil, ctx)
	b := e.Scene_InstantiateComponent(scene, rel, nil, ctx)
	if a == nil || b == nil do testing.fail_now(t, "instances")
	a.name = strings.clone("CrateA", a.allocator)
	b.name = strings.clone("CrateB", b.allocator)
	e.ProcessNodeQueues(scene.manager, ctx)
	for c in e.GetChildrenView(scene.manager, a) do if c.name == "Lid" do c.position = {0, -42} // an override

	// Apply, then Undo: the file and the other instance are back.
	testing.expect(t, Editor_ApplyInstanceToComponent(&state, Editor_NodeAtPath(&state, "0")), "apply")
	testing.expect(t, strings.contains(read(full), "-42"), "applied to the file")
	testing.expect_value(t, lid_y(scene, "CrateB"), -42)
	testing.expect(t, Editor_Undo(&state), "undo")
	testing.expect_value(t, read(full), CRATE)
	testing.expect_value(t, lid_y(scene, "CrateB"), -10)
	testing.expect_value(t, lid_y(scene, "CrateA"), -42) // its override, as before Apply
	testing.expect(t, Editor_Redo(&state), "redo")
	testing.expect(t, strings.contains(read(full), "-42"), "redo writes the file again")
	testing.expect_value(t, lid_y(scene, "CrateB"), -42)
	testing.expect(t, Editor_Undo(&state), "undo again")
	testing.expect_value(t, read(full), CRATE)

	// Saving a component document, then Undo (in the scene): the file and
	// the instances are back, and the document is unsaved again.
	doc := game->createScene("doc", false)
	doc.isLoaded = true
	doc.filePath = rel
	state.componentDocs[doc] = true
	e.Scene_InstantiateNodeFromJSON(doc, transmute([]u8)string(CRATE), doc.rootNode, ctx)
	e.ProcessNodeQueues(doc.manager, ctx)
	Editor_SetSceneBaseline(&state, doc)
	e.Scene_FindNodeByName(doc, "Lid").position = {0, -77}
	testing.expect(t, Editor_SaveComponentDoc(&state, doc), "save the document")
	testing.expect(t, strings.contains(read(full), "-77"), "saved")
	testing.expect_value(t, lid_y(scene, "CrateB"), -77)
	testing.expect(t, !Editor_SceneIsModified(&state, doc), "saved document")
	testing.expect(t, Editor_Undo(&state), "undo the save")
	testing.expect_value(t, read(full), CRATE)
	testing.expect_value(t, lid_y(scene, "CrateB"), -10)
	testing.expect(t, Editor_SceneIsModified(&state, doc), "the document differs from its file again")
	testing.expect(t, Editor_Redo(&state), "redo the save")
	testing.expect(t, strings.contains(read(full), "-77"), "saved again")
	testing.expect_value(t, lid_y(scene, "CrateB"), -77)
	testing.expect(t, !Editor_SceneIsModified(&state, doc), "the document matches its file")
}

// #79: saving a component updates its instances inside other open component
// documents too, without marking them unsaved.
@(test)
test_component_save_refreshes_documents :: proc(t: ^testing.T) {
	dir :: "test_component_doc_refresh"
	comps, _ := filepath.join({dir, "components"}, context.temp_allocator)
	_ = os.make_directory_all(comps)
	defer os.remove_all(dir)
	CRATE :: `{"type": "Node", "name": "Crate", "uid": "cr000000", "children": [{"type": "Node", "name": "Lid", "uid": "1id00000", "position": [0, -10]}]}`
	SHELF :: `{"type": "Node", "name": "Shelf", "uid": "sh000000", "children": [{"type": "Node", "name": "Crate", "uid": "cris0000", "component": "components/crate.component.json"}]}`
	crateFull, _ := filepath.join({comps, "crate.component.json"}, context.temp_allocator)
	shelfFull, _ := filepath.join({comps, "shelf.component.json"}, context.temp_allocator)
	_ = os.write_entire_file(crateFull, transmute([]u8)string(CRATE))
	_ = os.write_entire_file(shelfFull, transmute([]u8)string(SHELF))

	game := new(e.Game)
	e.InitializeGame(game)
	game.gameContext.isEditor = true
	e.AssetManager_SetProjectDir(&game.assetManager, dir)
	state: EditorState
	state.game = game
	state.projectPath = dir
	defer {
		for stack in ([]^[dynamic]Undo_Entry{&state.undoStack, &state.redoStack}) {
			for &u in stack do Undo_EntryDestroy(&u)
			delete(stack^)
		}
		for l in state.logs {
			delete(l.time)
			delete(l.message)
		}
		delete(state.logs)
		delete(state.selection)
		delete(state.sceneVersion)
		delete(state.savedVersion)
		for _, b in state.sceneBaselines do delete(b)
		delete(state.sceneBaselines)
		delete(state.componentDocs)
		Undo_ClearStore()
		game->terminate()
		e.Component_ClearCaches()
	}
	open_doc :: proc(state: ^EditorState, game: ^e.Game, name, rel, text: string) -> ^e.Scene {
		doc := game->createScene(name, false)
		doc.isLoaded = true
		doc.filePath = rel
		state.componentDocs[doc] = true
		e.Scene_InstantiateNodeFromJSON(doc, transmute([]u8)text, doc.rootNode, &game.gameContext)
		e.ProcessNodeQueues(doc.manager, &game.gameContext)
		Editor_SetSceneBaseline(state, doc)
		return doc
	}
	shelf := open_doc(&state, game, "shelf_doc", "components/shelf.component.json", SHELF)
	crate := open_doc(&state, game, "crate_doc", "components/crate.component.json", CRATE)
	state.activeScene = crate
	testing.expect_value(t, e.Scene_FindNodeByName(shelf, "Lid").position.y, -10)

	e.Scene_FindNodeByName(crate, "Lid").position = {0, -55}
	testing.expect(t, Editor_SaveComponentDoc(&state, crate), "save the crate")
	lid := e.Scene_FindNodeByName(shelf, "Lid")
	testing.expect(t, lid != nil && lid.position.y == -55, "the shelf document's crate follows")
	testing.expect(t, !Editor_SceneIsModified(&state, shelf), "the shelf document isn't unsaved")
}
