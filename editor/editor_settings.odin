package editor

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import imgui "lib/imgui"

// ============================================================================
// Editor settings (per user, not per project): ~/.config/ore_editor/
// settings.json. Edited in Settings > General / Code Editor. Test drives use
// a file inside the drive's project copy so they never touch the user's.
// ============================================================================

Editor_Settings :: struct {
	// General > Basic
	uiScale:          f32,  // ImGui font scale
	autosaveMinutes:  int,  // 0 = off
	gridSize:         f32,
	snapToGrid:       bool,
	showGrid:         bool,
	confirmQuit:      bool,
	// Code Editor
	codeFontSize:     f32,
	tabWidth:         int,
	insertSpaces:     bool, // for files without an indentation style yet
	autoClosePairs:   bool,
	formatOnSave:     bool,
	lspEnabled:       bool,
	luaServerPath:    string, // "" = lua-language-server/ in the engine checkout
	// General > Keymap: action id -> chords (replaces the defaults)
	keymap:           map[string][3]Chord,
	// File > Open Recent (absolute project paths, most recent first)
	recentProjects:   [dynamic]string,
}

DEFAULT_EDITOR_SETTINGS :: Editor_Settings{
	uiScale         = 1,
	autosaveMinutes = 0,
	gridSize        = 32,
	snapToGrid      = true,
	showGrid        = true,
	confirmQuit     = true,
	codeFontSize    = CODE_FONT_SIZE,
	tabWidth        = 4,
	insertSpaces    = true,
	autoClosePairs  = true,
	formatOnSave    = false,
	lspEnabled      = true,
}

Editor_DefaultSettings :: proc() -> Editor_Settings {
	return DEFAULT_EDITOR_SETTINGS
}

GlobalSettings := DEFAULT_EDITOR_SETTINGS
settingsPath: string

Editor_Settings_Clone :: proc(s: ^Editor_Settings) -> Editor_Settings {
	c := s^
	c.luaServerPath = strings.clone(s.luaServerPath)
	c.keymap = make(map[string][3]Chord)
	for k, v in s.keymap do c.keymap[strings.clone(k)] = v
	c.recentProjects = make([dynamic]string)
	for r in s.recentProjects do append(&c.recentProjects, strings.clone(r))
	return c
}

Editor_Settings_Destroy :: proc(s: ^Editor_Settings) {
	delete(s.luaServerPath)
	for k in s.keymap do delete(k)
	delete(s.keymap)
	s.keymap = nil
	for r in s.recentProjects do delete(r)
	delete(s.recentProjects)
	s.recentProjects = nil
	s.luaServerPath = ""
}

// Editor_SettingsPath: where settings live (drives: inside the project copy).
Editor_SettingsFilePath :: proc(state: ^EditorState) -> string {
	if GlobalDrive.enabled {
		p, _ := filepath.join({state.projectPath, ".editor_settings.json"}, context.allocator)
		return p
	}
	home, err := os.user_home_dir(context.temp_allocator)
	if err != nil do return strings.clone(".editor_settings.json")
	p, _ := filepath.join({home, ".config", "ore_editor", "settings.json"}, context.allocator)
	return p
}

// --- chords as text ----------------------------------------------------------------

// Chord_Parse reads Chord_Text's format ("Cmd+Shift+P", "Ctrl+G", "F5").
Chord_Parse :: proc(text: string) -> (c: Chord, ok: bool) {
	parts := strings.split(text, "+", context.temp_allocator)
	if len(parts) == 0 do return
	for p, i in parts {
		if i < len(parts) - 1 {
			switch strings.to_lower(p, context.temp_allocator) {
			case "cmd", "primary": c.mods += {.Primary}
			case "ctrl":
				when ODIN_OS == .Darwin do c.mods += {.Ctrl}
				else do c.mods += {.Primary}
			case "shift": c.mods += {.Shift}
			case "alt", "opt": c.mods += {.Alt}
			case: return {}, false
			}
			continue
		}
		key := p
		if key == "" && strings.has_suffix(text, "++") do key = "+"
		for k in imgui.Key.Tab ..= imgui.Key.F12 {
			if strings.equal_fold(Chord_Text({k, {}}), key) {
				c.key = k
				return c, true
			}
		}
	}
	return {}, false
}

// --- load / save -------------------------------------------------------------------

Editor_LoadSettings :: proc(state: ^EditorState) {
	if settingsPath != "" do delete(settingsPath)
	settingsPath = Editor_SettingsFilePath(state)
	GlobalSettings = Editor_DefaultSettings()
	data, err := os.read_entire_file(settingsPath, context.temp_allocator)
	if err == nil {
		val, perr := json.parse(data, allocator = context.temp_allocator)
		if obj, ok := val.(json.Object); perr == .None && ok {
			s := &GlobalSettings
			s.uiScale = jf(obj, "ui_scale", s.uiScale)
			s.autosaveMinutes = int(jf(obj, "autosave_minutes", f32(s.autosaveMinutes)))
			s.gridSize = jf(obj, "grid_size", s.gridSize)
			s.snapToGrid = jb(obj, "snap_to_grid", s.snapToGrid)
			s.showGrid = jb(obj, "show_grid", s.showGrid)
			s.confirmQuit = jb(obj, "confirm_quit", s.confirmQuit)
			s.codeFontSize = jf(obj, "code_font_size", s.codeFontSize)
			s.tabWidth = int(jf(obj, "tab_width", f32(s.tabWidth)))
			s.insertSpaces = jb(obj, "insert_spaces", s.insertSpaces)
			s.autoClosePairs = jb(obj, "auto_close_pairs", s.autoClosePairs)
			s.formatOnSave = jb(obj, "format_on_save", s.formatOnSave)
			s.lspEnabled = jb(obj, "lsp_enabled", s.lspEnabled)
			if p, has := obj["lua_server_path"].(json.String); has do s.luaServerPath = strings.clone(string(p))
			if rp, has := obj["recent_projects"].(json.Array); has {
				for v in rp do if p, isStr := v.(json.String); isStr do append(&s.recentProjects, strings.clone(string(p)))
			}
			if km, has := obj["keymap"].(json.Object); has {
				s.keymap = make(map[string][3]Chord)
				for id, v in km {
					arr, isArr := v.(json.Array)
					if !isArr do continue
					chords: [3]Chord
					n := 0
					for cv in arr {
						if cs, isStr := cv.(json.String); isStr && n < 3 {
							if c, cok := Chord_Parse(string(cs)); cok {
								chords[n] = c
								n += 1
							}
						}
					}
					s.keymap[strings.clone(id)] = chords
				}
			}
		}
	}
	Editor_ApplySettings(state)
	Editor_AddRecentProject(state.projectPath)
	_ = Editor_SaveSettings()
}

// Editor_AddRecentProject moves a project to the top of File > Open Recent.
Editor_AddRecentProject :: proc(path: string) {
	abs := path
	if !filepath.is_abs(path) {
		if cwd, err := os.get_working_directory(context.temp_allocator); err == nil do abs, _ = filepath.join({cwd, path}, context.temp_allocator)
	}
	abs, _ = filepath.clean(abs, context.temp_allocator)
	r := &GlobalSettings.recentProjects
	for p, i in r {
		if p == abs {
			delete(p)
			ordered_remove(r, i)
			break
		}
	}
	inject_at(r, 0, strings.clone(abs))
	for len(r) > 10 do delete(pop(r))
}

@(private = "file")
jf :: proc(obj: json.Object, k: string, d: f32) -> f32 {
	#partial switch v in obj[k] {
	case json.Float: return f32(v)
	case json.Integer: return f32(v)
	}
	return d
}

@(private = "file")
jb :: proc(obj: json.Object, k: string, d: bool) -> bool {
	if v, ok := obj[k].(json.Boolean); ok do return bool(v)
	return d
}

Editor_SaveSettings :: proc() -> bool {
	s := &GlobalSettings
	sb := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&sb, "{{\n  \"ui_scale\": %.2f,\n  \"autosave_minutes\": %d,\n  \"grid_size\": %.0f,\n", s.uiScale, s.autosaveMinutes, s.gridSize)
	fmt.sbprintf(&sb, "  \"snap_to_grid\": %t,\n  \"show_grid\": %t,\n  \"confirm_quit\": %t,\n", s.snapToGrid, s.showGrid, s.confirmQuit)
	fmt.sbprintf(&sb, "  \"code_font_size\": %.0f,\n  \"tab_width\": %d,\n  \"insert_spaces\": %t,\n", s.codeFontSize, s.tabWidth, s.insertSpaces)
	fmt.sbprintf(&sb, "  \"auto_close_pairs\": %t,\n  \"format_on_save\": %t,\n  \"lsp_enabled\": %t,\n", s.autoClosePairs, s.formatOnSave, s.lspEnabled)
	fmt.sbprintf(&sb, "  \"lua_server_path\": %q,\n  \"recent_projects\": [", s.luaServerPath)
	for r, i in s.recentProjects {
		if i > 0 do strings.write_string(&sb, ", ")
		fmt.sbprintf(&sb, "%q", r)
	}
	strings.write_string(&sb, "],\n  \"keymap\": {")
	n := 0
	for id, chords in s.keymap {
		if n > 0 do strings.write_string(&sb, ",")
		fmt.sbprintf(&sb, "\n    %q: [", id)
		m := 0
		for c in chords {
			if c.key == .None do continue
			if m > 0 do strings.write_string(&sb, ", ")
			fmt.sbprintf(&sb, "%q", Chord_Text(c))
			m += 1
		}
		strings.write_string(&sb, "]")
		n += 1
	}
	strings.write_string(&sb, "\n  }\n}\n")
	_ = os.make_directory_all(filepath.dir(settingsPath, context.temp_allocator))
	return os.write_entire_file(settingsPath, transmute([]u8)strings.to_string(sb)) == nil
}

// Editor_ApplySettings pushes settings into the editor (font scale, grid,
// code editor, keymap).
Editor_ApplySettings :: proc(state: ^EditorState) {
	s := &GlobalSettings
	io := imgui.GetIO()
	io.FontGlobalScale = clamp(s.uiScale, 0.75, 2)
	state.gridSize = max(s.gridSize, 1)
	state.snapGrid = s.snapToGrid
	state.showGrid = s.showGrid
	GlobalCode.fontSize = s.codeFontSize if s.codeFontSize != CODE_FONT_SIZE else 0
	Actions_ApplyKeymap(s.keymap)
}
