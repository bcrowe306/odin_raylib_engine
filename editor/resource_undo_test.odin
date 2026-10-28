package editor

import "core:os"
import "core:path/filepath"
import "core:testing"

// Resource edits share the undo stack: undo writes the file back as it was
// before the edit, redo as it was after; scene entries of other scenes are
// skipped, resource entries are not; a renamed file's entries follow it.
@(test)
test_resource_undo_redo :: proc(t: ^testing.T) {
	dir, _ := filepath.abs("test_resource_undo", context.temp_allocator)
	resDir, _ := filepath.join({dir, "resources"}, context.temp_allocator)
	_ = os.make_directory_all(resDir)
	defer os.remove_all(dir)
	rel :: "resources/boss.resource.json"
	full, _ := filepath.join({dir, rel}, context.temp_allocator)
	BEFORE :: `{"type": "resource", "script": "scripts/health.lua", "properties": {}}`
	AFTER :: `{"type": "resource", "script": "scripts/health.lua", "properties": {"max": 250}}`
	read :: proc(path: string) -> string {
		data, _ := os.read_entire_file(path, context.temp_allocator)
		return string(data)
	}

	state: EditorState
	state.projectPath = dir
	defer {
		for stack in ([]^[dynamic]Undo_Entry{&state.undoStack, &state.redoStack}) {
			for &u in stack {
				Undo_Release(u.json)
				delete(u.label)
				delete(u.selected)
				delete(u.resource)
			}
			delete(stack^)
		}
		for l in state.logs {
			delete(l.time)
			delete(l.message)
		}
		delete(state.logs)
		Undo_ClearStore()
	}

	_ = os.write_entire_file(full, transmute([]u8)string(BEFORE))
	Editor_RecordResourceUndo(&state, rel, "Edit max")
	Editor_RecordResourceUndo(&state, rel, "Edit max") // unchanged: still one step
	testing.expect_value(t, len(state.undoStack), 1)
	_ = os.write_entire_file(full, transmute([]u8)string(AFTER))

	testing.expect(t, Editor_Undo(&state), "undo applies (no active scene needed)")
	testing.expect_value(t, read(full), BEFORE)
	testing.expect_value(t, len(state.redoStack), 1)
	testing.expect(t, Editor_Redo(&state), "redo")
	testing.expect_value(t, read(full), AFTER)

	// Renaming the file: its entries follow it.
	Undo_ResourceMoved(&state, rel, "resources/big_boss.resource.json", false)
	testing.expect_value(t, state.undoStack[0].resource, "resources/big_boss.resource.json")
	Undo_ResourceMoved(&state, "resources", "data", true)
	testing.expect_value(t, state.undoStack[0].resource, "data/big_boss.resource.json")
}
