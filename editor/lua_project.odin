package editor

import "core:os"
import "core:path/filepath"
import "core:strings"

// ============================================================================
// Lua tooling files in the project.
//
// The engine's API definitions are compiled into the editor and written to
// <project>/.rayzr/definitions/ (rewritten when the editor's copy changes),
// and <project>/.luarc.json points lua-language-server at them - so the
// built-in code editor, and VS Code or any LuaLS editor opening the project
// folder, get the same completion and hover. Hidden files and folders
// (.rayzr/, .luarc.json, ...) are not packaged into games.
// ============================================================================

ENGINE_API_LUA :: #load("../engine/definitions/engine_api.lua", string)
EDITOR_API_LUA :: #load("definitions/editor_api.lua", string) // (plugins: editor/docs/plugins.md)

LUA_DEFINITIONS_DIR :: ".rayzr/definitions"
LUA_HISTORY_DIR     :: ".rayzr/history" // (code_history.odin: saved copies of scripts)

// write_if_changed writes a file unless it already has exactly this content.
@(private = "file")
write_if_changed :: proc(path, text: string) -> bool {
	if old, err := os.read_entire_file(path, context.temp_allocator); err == nil && string(old) == text do return true
	_ = os.make_directory_all(filepath.dir(path, context.temp_allocator))
	return os.write_entire_file(path, transmute([]u8)text) == nil
}

// luarc_text: the .luarc.json the editor writes into projects.
luarc_text :: proc() -> string {
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "{\n")
	strings.write_string(&sb, "  \"$schema\": \"https://raw.githubusercontent.com/LuaLS/vscode-lua/master/setting/schema.json\",\n")
	strings.write_string(&sb, "  \"runtime.version\": \"Lua 5.4\",\n")
	strings.write_string(&sb, "  \"workspace.library\": [\"" + LUA_DEFINITIONS_DIR + "\"],\n")
	strings.write_string(&sb, "  \"workspace.checkThirdParty\": false,\n")
	// The editor's file history keeps old copies of every script (each one
	// declaring the same ---@class): left in, LuaLS reports the real
	// script's methods as duplicate fields (#264).
	strings.write_string(&sb, "  \"workspace.ignoreDir\": [\"" + LUA_HISTORY_DIR + "\"],\n")
	strings.write_string(&sb, "  \"completion.callSnippet\": \"Replace\",\n")
	strings.write_string(&sb, "  \"diagnostics.globals\": [")
	for g, i in CODE_LUA_GLOBALS {
		if i > 0 do strings.write_string(&sb, ", ")
		strings.write_byte(&sb, '"')
		strings.write_string(&sb, g)
		strings.write_byte(&sb, '"')
	}
	strings.write_string(&sb, "]\n}\n")
	return strings.to_string(sb)
}

// Lua_ProjectSetup writes the definitions and .luarc.json into the project;
// returns the absolute definitions directory ("" without a project).
Lua_ProjectSetup :: proc(state: ^EditorState) -> string {
	if state.projectPath == "" || !os.is_dir(state.projectPath) do return ""
	root := state.projectPath
	if !filepath.is_abs(root) {
		if abs, err := os.get_absolute_path(root, context.temp_allocator); err == nil do root = abs
	}
	defs, _ := filepath.join({root, LUA_DEFINITIONS_DIR}, context.temp_allocator)
	api, _ := filepath.join({defs, "engine_api.lua"}, context.temp_allocator)
	write_if_changed(api, ENGINE_API_LUA)
	// The plugin API (only in projects with plugins: game scripts don't see Editor).
	editorApi, _ := filepath.join({defs, "editor_api.lua"}, context.temp_allocator)
	pluginsDir, _ := filepath.join({root, "plugins"}, context.temp_allocator)
	if os.is_dir(pluginsDir) do write_if_changed(editorApi, EDITOR_API_LUA)
	else if os.is_file(editorApi) do _ = os.remove(editorApi)
	// .luarc.json: created, or refreshed when it's ours (points at our
	// definitions); a hand-written one is left alone.
	luarc, _ := filepath.join({root, ".luarc.json"}, context.temp_allocator)
	existing, err := os.read_entire_file(luarc, context.temp_allocator)
	// (".ore/definitions": ours, from before the rename.)
	if err != nil || strings.contains(string(existing), LUA_DEFINITIONS_DIR) || strings.contains(string(existing), ".ore/definitions") {
		write_if_changed(luarc, luarc_text())
	}
	Lua_WriteProjectTypes(state)
	return strings.clone(defs, context.temp_allocator)
}
