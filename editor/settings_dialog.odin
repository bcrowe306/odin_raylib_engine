package editor

import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:reflect"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Settings (Cmd+,): one dialog with top-level tabs
//
//   General      Basic (UI scale, grid, autosave, quit), Keymap (every action)
//   Code Editor  font, tabs, auto-pairs, format on save, language server
//   Project      General (name, startup scene, scenes, physics), Input
//                (named actions -> bindings), Video, Audio, Export
//
// Editor settings and the project's project.json are edited as drafts:
// Save writes and applies both; Cancel discards them.
// ============================================================================

Settings_Tab :: enum {
	General,
	Code,
	Project,
}

@(private = "file")
Settings_State :: struct {
	tab:        Settings_Tab,
	selectTab:  bool,
	generalPage: int, // 0 Basic, 1 Keymap, 2 Theme
	projectPage: int, // 0 General, 1 Input, 2 Video, 3 Audio, 4 Export
	editor:     Editor_Settings,
	project:    e.ProjectConfig,
	open:       bool,
	// Keymap
	keyFilter:  [64]u8,
	recording:  string, // action id waiting for a chord ("" = none)
	// Input
	action:     int,
	newAction:  [64]u8,
	listening:  bool, // capturing a key for the selected action
	pickDevice: e.InputDeviceType,
	pickFilter: [32]u8,
}

@(private = "file")
st: Settings_State

Settings_Open :: proc(state: ^EditorState, tab: Settings_Tab = .General) {
	state.showProjectSettings = true
	if st.open {
		Editor_Settings_Destroy(&st.editor)
		e.ProjectConfig_Destroy(&st.project)
		delete(st.recording)
	}
	st.recording = ""
	st.editor = Editor_Settings_Clone(&GlobalSettings)
	st.project = e.ProjectConfig_Clone(&state.projectConfig)
	// Pick up edits made outside the editor.
	projPath, _ := filepath.join({state.projectPath, "project.json"}, context.temp_allocator)
	if pBytes, err := os.read_entire_file(projPath, context.temp_allocator); err == nil {
		if cfg, parsed := e.Project_ParseConfig(pBytes, context.allocator); parsed {
			e.ProjectConfig_Destroy(&st.project)
			st.project = cfg
		}
	}
	// Show the built-in actions with their default bindings to start from.
	if len(st.project.actions) == 0 {
		e.Input_ActionConfigs_Destroy(&st.project.actions)
		st.project.actions = e.Input_DefaultActionConfigs()
	}
	st.tab = tab
	st.selectTab = true
	st.open = true
	st.action = 0
	st.listening = false
}

// ProjectSettingsDialog_Open opens Settings on the Project tab.
ProjectSettingsDialog_Open :: proc(state: ^EditorState) {
	Settings_Open(state, .Project)
}

@(private = "file")
text_field :: proc(id: string, s: ^string, hint: cstring = "") {
	buf: [256]u8
	copy(buf[:len(buf) - 1], s^)
	imgui.SetNextItemWidth(-1)
	if imgui.InputTextWithHint(fmt.ctprintf("##%s", id), hint, cstring(raw_data(buf[:])), len(buf), {}) {
		delete(s^)
		s^ = strings.clone(string(cstring(raw_data(buf[:]))))
	}
	Drive_Item(id)
}

// folder_field: a folder path with Browse... (a system folder dialog that
// opens in the export folder used last).
@(private = "file")
browseTarget: ^string

@(private = "file")
folder_field :: proc(state: ^EditorState, id: string, s: ^string, hint: string) {
	buf: [512]u8
	copy(buf[:len(buf) - 1], s^)
	imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x - 90)
	if imgui.InputTextWithHint(fmt.ctprintf("##%s", id), strings.clone_to_cstring(hint, context.temp_allocator), cstring(raw_data(buf[:])), len(buf), {}) {
		delete(s^)
		s^ = strings.clone(string(cstring(raw_data(buf[:]))))
	}
	Drive_Item(id)
	imgui.SameLine(0, 4)
	if UI_Button("Browse...", fmt.tprintf("%s.browse", id), {86, 0}) {
		browseTarget = s
		start := Editor_StartDir(.Export, s^ if os.is_dir(s^) else filepath.dir(strings.trim_suffix(state.projectPath, "/"), context.temp_allocator))
		NativeDialog_Open(state, {title = "Output Folder", folders = true, start = start}, proc(state: ^EditorState, paths: []string) {
			if browseTarget == nil do return
			delete(browseTarget^)
			browseTarget^ = strings.clone(paths[0])
			browseTarget = nil
			Editor_RememberDir(.Export, paths[0], true)
		})
	}
}

@(private = "file")
check :: proc(id, label: string, v: ^bool, tip := "") {
	UI_PropLabel(label)
	imgui.Checkbox(fmt.ctprintf("##%s", id), v)
	Drive_Item(id)
	if tip != "" do UI_Tooltip(tip)
}

@(private = "file")
nav :: proc(id: string, items: []string, cur: ^int) {
	for name, i in items {
		if imgui.Selectable(fmt.ctprintf("%s##nav_%s_%d", name, id, i), cur^ == i, {}, {0, 28}) do cur^ = i
		Drive_Item(fmt.tprintf("settings.page:%s", name))
	}
}

ProjectSettingsDialog_Render :: proc(state: ^EditorState) {
	if state.showProjectSettings && !imgui.IsPopupOpen("Settings###SettingsWindow") {
		imgui.OpenPopup("Settings###SettingsWindow")
	}
	io := imgui.GetIO()
	imgui.SetNextWindowSize({940, 640}, .Appearing)
	imgui.SetNextWindowPos({io.DisplaySize.x * 0.5, io.DisplaySize.y * 0.5}, .Appearing, {0.5, 0.5})
	imgui.PushStyleVarImVec2(.WindowPadding, {18, 16})
	defer imgui.PopStyleVar()
	if !imgui.BeginPopupModal("Settings###SettingsWindow", &state.showProjectSettings, {.NoTitleBar}) do return

	UI_PanelTitle(ICON_FA_GEAR, "Settings")
	imgui.SameLine(0, UI_SPACE)
	UI_DimText(state.projectPath)
	imgui.Dummy({0, 4})

	bodyH := imgui.GetContentRegionAvail().y - 46
	if imgui.BeginTabBar("##settings_tabs", {}) {
		tab :: proc(label: cstring, id: string, t: Settings_Tab) -> bool {
			flags: imgui.TabItemFlags = {}
			if st.selectTab && st.tab == t do flags += {.SetSelected}
			open := imgui.BeginTabItem(label, nil, flags)
			Drive_Item(id)
			// While a tab is being selected, the previously open tab still
			// reports open this frame: don't let it overwrite the request.
			if open && !st.selectTab do st.tab = t
			return open
		}
		if tab(fmt.ctprintf("%s  General###st_general", ICON_FA_GEAR), "settings.tab:general", .General) {
			settings_general(state, bodyH - 40)
			imgui.EndTabItem()
		}
		if tab(fmt.ctprintf("%s  Code Editor###st_code", ICON_FA_CODE), "settings.tab:code", .Code) {
			settings_code(state, bodyH - 40)
			imgui.EndTabItem()
		}
		if tab(fmt.ctprintf("%s  Project###st_project", ICON_FA_FOLDER), "settings.tab:project", .Project) {
			settings_project(state, bodyH - 40)
			imgui.EndTabItem()
		}
		st.selectTab = false
		imgui.EndTabBar()
	}

	imgui.SetCursorPosY(imgui.GetWindowHeight() - 16 - 32)
	imgui.SetCursorPosX(imgui.GetWindowWidth() - 18 - 120 - 96 - UI_SPACE)
	if UI_Button("Cancel", "settings.cancel", {96, 32}) || (imgui.IsKeyPressed(.Escape) && st.recording == "" && !st.listening) {
		state.showProjectSettings = false
		Theme_Apply(GlobalSettings.theme) // drop a previewed theme
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine(0, UI_SPACE)
	if UI_PrimaryButton("Save", "settings.save", {120, 32}) do settings_save(state)
	imgui.EndPopup()
}

@(private = "file")
settings_save :: proc(state: ^EditorState) {
	Lua_MarkProjectTypesDirty() // generated Lua types follow the project
	d := &st.project
	if !e.Project_SaveConfigToFile(state.projectPath, d) {
		Editor_Log(state, .Error, "Failed to write %s/project.json", state.projectPath)
		return
	}
	e.ProjectConfig_Destroy(&state.projectConfig)
	state.projectConfig = e.ProjectConfig_Clone(d)
	e.Physics_SetLayerNames(state.projectConfig.collisionLayers[:])
	state.game.physicsWorld.gravity = d.gravity
	if d.virtualWidth > 0 do state.game.virtualSize = {d.virtualWidth, d.virtualHeight}
	state.game.musicVolume = d.musicVolume
	state.game.sfxVolume = d.sfxVolume
	e.Input_ApplyActionConfigs(&state.game.input, d.actions[:])

	Editor_Settings_Destroy(&GlobalSettings)
	GlobalSettings = Editor_Settings_Clone(&st.editor)
	Editor_ApplySettings(state)
	if !Editor_SaveSettings() do Editor_Log(state, .Warn, "Could not write editor settings to %s", settingsPath)

	Editor_Log(state, .Info, "Saved settings (startup scene %s)", d.initialScene)
	state.showProjectSettings = false
	imgui.CloseCurrentPopup()
}

// --- General -----------------------------------------------------------------------

@(private = "file")
settings_general :: proc(state: ^EditorState, h: f32) {
	if imgui.BeginChild("##gen_nav", {170, h}, {}, {}) do nav("general", {"Basic", "Keymap", "Theme"}, &st.generalPage)
	imgui.EndChild()
	imgui.SameLine(0, UI_SPACE * 2)
	if imgui.BeginChild("##gen_body", {0, h}, {}, {}) {
		s := &st.editor
		switch st.generalPage {
		case 0:
			if UI_BeginProps("##basic") {
				UI_PropLabel("UI Scale")
				imgui.SliderFloat("##uiscale", &s.uiScale, 0.75, 2, "%.2fx")
				Drive_Item("settings.ui-scale")
				UI_PropLabel("Grid Size")
				imgui.DragFloat("##grid", &s.gridSize, 1, 1, 512, "%.0f px")
				Drive_Item("settings.grid-size")
				check("settings.snap", "Snap to Grid", &s.snapToGrid)
				check("settings.show-grid", "Show Grid", &s.showGrid)
				UI_PropLabel("Autosave")
				mins := c.int(s.autosaveMinutes)
				if imgui.SliderInt("##autosave", &mins, 0, 30, "%d min" if mins > 0 else "Off") do s.autosaveMinutes = int(mins)
				Drive_Item("settings.autosave")
				UI_Tooltip("Save modified scenes and scripts every N minutes (0 = off)")
				check("settings.confirm-quit", "Ask Before Quitting", &s.confirmQuit, "Ask about unsaved scenes and scripts when quitting")
				check("settings.auto-bottom-panel", "Bottom Panel Follows Selection", &s.autoBottomPanel, "Selecting an AnimationPlayer, particle emitter or LDtk level shows its tab in the bottom panel; selecting something else goes back to the tab you had")
				UI_EndProps()
			}
		case 1:
			settings_keymap(state)
		case 2:
			Theme_Editor(&s.theme) // previews live; Cancel restores the saved theme
		}
	}
	imgui.EndChild()
}

// imgui_key_chord: the chord pressed this frame (any non-modifier key).
@(private = "file")
imgui_key_chord :: proc() -> (Chord, bool) {
	for k in imgui.Key.Tab ..= imgui.Key.F12 {
		#partial switch k {
		case .LeftCtrl, .RightCtrl, .LeftShift, .RightShift, .LeftAlt, .RightAlt, .LeftSuper, .RightSuper: continue
		}
		if !imgui.IsKeyPressed(k, false) do continue
		mods: Mods
		if Keys_Primary() do mods += {.Primary}
		when ODIN_OS == .Darwin {
			if Keys_PhysicalCtrl() do mods += {.Ctrl}
		}
		if imgui.IsKeyDown(.LeftShift) || imgui.IsKeyDown(.RightShift) do mods += {.Shift}
		if imgui.IsKeyDown(.LeftAlt) || imgui.IsKeyDown(.RightAlt) do mods += {.Alt}
		return {k, mods}, true
	}
	return {}, false
}

@(private = "file")
settings_keymap :: proc(state: ^EditorState) {
	s := &st.editor
	imgui.SetNextItemWidth(-1)
	imgui.InputTextWithHint("##km_filter", "Filter commands or keys", cstring(raw_data(st.keyFilter[:])), len(st.keyFilter), {})
	Drive_Item("settings.keymap-filter")
	q := strings.to_lower(string(cstring(raw_data(st.keyFilter[:]))), context.temp_allocator)
	if st.recording != "" {
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextUnformatted("Press the new shortcut (Esc cancels)...")
		imgui.PopStyleColor()
		if imgui.IsKeyPressed(.Escape, false) {
			delete(st.recording)
			st.recording = ""
		} else if chord, ok := imgui_key_chord(); ok {
			chords := s.keymap[st.recording] if st.recording in s.keymap else actionDefaults[st.recording]
			chords[0] = chord
			if s.keymap == nil do s.keymap = make(map[string][3]Chord)
			if st.recording not_in s.keymap do s.keymap[strings.clone(st.recording)] = chords
			else do s.keymap[st.recording] = chords
			delete(st.recording)
			st.recording = ""
		}
	}
	if !imgui.BeginTable("##keymap", 3, imgui.TableFlags_SizingStretchProp | imgui.TableFlags_RowBg | imgui.TableFlags_ScrollY) do return
	imgui.TableSetupColumn("Command", {.WidthStretch}, 0.5)
	imgui.TableSetupColumn("Shortcut", {.WidthStretch}, 0.32)
	imgui.TableSetupColumn("", {.WidthFixed}, 96)
	imgui.TableHeadersRow()
	for &a in GlobalActions {
		chords := s.keymap[a.id] if a.id in s.keymap else actionDefaults[a.id]
		name := fmt.tprintf("%s: %s", a.category, a.label)
		keys := strings.builder_make(context.temp_allocator)
		for ch in chords {
			if ch.key == .None do continue
			if strings.builder_len(keys) > 0 do strings.write_string(&keys, "  /  ")
			strings.write_string(&keys, Chord_Text(ch))
		}
		keyText := strings.to_string(keys)
		if q != "" && !strings.contains(strings.to_lower(name, context.temp_allocator), q) && !strings.contains(strings.to_lower(keyText, context.temp_allocator), q) do continue
		imgui.TableNextRow()
		imgui.TableNextColumn()
		imgui.AlignTextToFramePadding()
		imgui.TextUnformatted(strings.clone_to_cstring(name, context.temp_allocator))
		imgui.TableNextColumn()
		imgui.AlignTextToFramePadding()
		recording := st.recording == a.id
		imgui.PushStyleColorImVec4(.Text, UI_WARNING if recording else UI_ACCENT)
		imgui.TextUnformatted(strings.clone_to_cstring(keyText if !recording else "...", context.temp_allocator))
		imgui.PopStyleColor()
		if conflict := Action_Conflicts(&a, chords[0]); conflict != "" {
			imgui.SameLine()
			imgui.PushStyleColorImVec4(.Text, UI_WARNING)
			imgui.TextUnformatted(ICON_FA_TRIANGLE_EXCLAMATION)
			imgui.PopStyleColor()
			UI_Tooltip(fmt.tprintf("Also bound to %s", conflict))
		}
		imgui.TableNextColumn()
		imgui.PushID(strings.clone_to_cstring(a.id, context.temp_allocator))
		if UI_IconButton(ICON_FA_PEN, fmt.tprintf("settings.key-record:%s", a.id), "Record a new shortcut", recording, 26) {
			delete(st.recording)
			st.recording = strings.clone(a.id)
		}
		imgui.SameLine(0, 2)
		if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("settings.key-clear:%s", a.id), "Remove the shortcuts", size = 26) {
			if a.id not_in s.keymap do s.keymap[strings.clone(a.id)] = {}
			else do s.keymap[a.id] = {}
		}
		imgui.SameLine(0, 2)
		if UI_IconButton(ICON_FA_ROTATE_LEFT, fmt.tprintf("settings.key-reset:%s", a.id), "Reset to default", size = 26) {
			if k, _ := delete_key(&s.keymap, a.id); k != "" do delete(k)
		}
		imgui.PopID()
	}
	imgui.EndTable()
}

// --- Code editor -------------------------------------------------------------------

@(private = "file")
settings_code :: proc(state: ^EditorState, h: f32) {
	if !imgui.BeginChild("##code_body", {0, h}, {}, {}) {
		imgui.EndChild()
		return
	}
	defer imgui.EndChild()
	s := &st.editor
	if !UI_BeginProps("##codeprops") do return
	UI_PropLabel("Font Size")
	imgui.SliderFloat("##codefont", &s.codeFontSize, 9, 32, "%.0f")
	Drive_Item("settings.code-font")
	UI_PropLabel("Tab Width")
	tw := c.int(s.tabWidth)
	if imgui.SliderInt("##tabw", &tw, 1, 8) do s.tabWidth = int(tw)
	Drive_Item("settings.tab-width")
	check("settings.insert-spaces", "Indent With Spaces", &s.insertSpaces, "For files that don't have an indentation style yet")
	check("settings.auto-pairs", "Auto-Close Brackets", &s.autoClosePairs, "Insert closing brackets and quotes, step over them, wrap selections")
	check("settings.format-on-save", "Format On Save", &s.formatOnSave, "Run the language server's formatter before saving")
	check("settings.lsp", "Language Server", &s.lspEnabled, "Completion, diagnostics and navigation from lua-language-server (restart the editor to apply)")
	UI_PropLabel("Server Path")
	text_field("settings.lsp-path", &s.luaServerPath, "lua-language-server/bin/lua-language-server")
	UI_EndProps()
}

// --- Project -----------------------------------------------------------------------

@(private = "file")
settings_project :: proc(state: ^EditorState, h: f32) {
	if imgui.BeginChild("##proj_nav", {170, h}, {}, {}) do nav("project", {"General", "Input", "Video", "Audio", "Export"}, &st.projectPage)
	imgui.EndChild()
	imgui.SameLine(0, UI_SPACE * 2)
	if imgui.BeginChild("##proj_body", {0, h}, {}, {}) {
		switch st.projectPage {
		case 0: project_general(state)
		case 1: project_input(state)
		case 2: project_video(state)
		case 3: project_audio(state)
		case 4: project_export(state)
		}
	}
	imgui.EndChild()
}

@(private = "file")
scene_listed :: proc(d: ^e.ProjectConfig, path: string) -> bool {
	for s in d.scenes do if s == path do return true
	return false
}

@(private = "file")
ensure_scene_listed :: proc(d: ^e.ProjectConfig, path: string) {
	if !scene_listed(d, path) do append(&d.scenes, strings.clone(path))
}

@(private = "file")
project_general :: proc(state: ^EditorState) {
	d := &st.project
	if UI_SectionHeader("Project") && UI_BeginProps("##general") {
		UI_PropLabel("Name")
		text_field("settings.name", &d.name)
		UI_PropLabel("Version")
		text_field("settings.version", &d.version)
		UI_PropLabel("Language")
		text_field("settings.language", &d.language, "the first in locale/*.csv")
		UI_Tooltip("Starting language for texts from the locale/ tables (scripts: Locale.set)")
		UI_PropLabel("Startup Scene")
		avail := imgui.GetContentRegionAvail().x
		imgui.SetNextItemWidth(avail - 110)
		if imgui.BeginCombo("##startup", strings.clone_to_cstring(d.initialScene if d.initialScene != "" else "None", context.temp_allocator)) {
			for sc in d.scenes {
				if imgui.Selectable(strings.clone_to_cstring(sc, context.temp_allocator), sc == d.initialScene) {
					delete(d.initialScene)
					d.initialScene = strings.clone(sc)
				}
				Drive_Item(fmt.tprintf("pick:%s", sc))
			}
			imgui.EndCombo()
		}
		Drive_Item("settings.startup")
		imgui.SameLine(0, 6)
		if UI_Button("Use Current", "settings.use-current", {104, 0}) && state.activeScenePath != "" {
			delete(d.initialScene)
			d.initialScene = strings.clone(state.activeScenePath)
			ensure_scene_listed(d, state.activeScenePath)
		}
		UI_PropLabel("Icon")
		imgui.SetNextItemWidth(-1)
		if path, ok := asset_picker("settings.icon", d.icon, Editor_ListProjectFiles(state, "", {".png"})); ok {
			delete(d.icon)
			d.icon = strings.clone(path)
		}
		UI_Tooltip("PNG used as the game window's icon and the exported app's (512x512 or 1024x1024 works best)")
		UI_EndProps()
	}
	if UI_SectionHeader("Physics") && UI_BeginProps("##physics") {
		UI_PropLabel("Gravity")
		imgui.DragFloat2("##gravity", &d.gravity, 1, -5000, 5000, "%.0f")
		Drive_Item("settings.gravity")
		UI_PropLabel("")
		if UI_Button("Zero-G", "settings.zero-g") do d.gravity = {0, 0}
		imgui.SameLine()
		if UI_Button("Earth (0, 980)", "settings.earth-g") do d.gravity = {0, 980}
		UI_PropLabel("Show Colliders")
		imgui.Checkbox("##debug_draw", &d.debugDraw)
		Drive_Item("settings.debug-draw")
		UI_Tooltip("Draw collision shapes, joints and areas while the game runs (debugging). The editor's viewport shows them either way; scripts: Physics.set_debug_draw(false)")
		UI_EndProps()
	}
	if UI_SectionHeader("Collision Layers", false) && UI_BeginProps("##layers") {
		// Names for the 16 collision layers (shown in body shapes' layer lists;
		// scripts use them: body:set_collision_layer("Player")).
		for i in 0 ..< 16 {
			UI_PropLabel(fmt.tprintf("Layer %d", i + 1))
			text_field(fmt.tprintf("settings.layer:%d", i + 1), &d.collisionLayers[i], "unnamed")
		}
		UI_EndProps()
	}
	if UI_SectionHeader("Scenes") {
		UI_DimText("Scenes included in the game (and in exported packages).")
		remove := -1
		for sc, i in d.scenes {
			imgui.PushIDInt(c.int(i))
			imgui.AlignTextToFramePadding()
			imgui.TextUnformatted(fmt.ctprintf("%s  %s%s", ICON_FA_CLAPPERBOARD, sc, "   (startup)" if sc == d.initialScene else ""))
			imgui.SameLine(imgui.GetWindowContentRegionMax().x - 28)
			if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("settings.remove:%s", sc), "Remove from project", size = 24) do remove = i
			imgui.PopID()
		}
		if remove >= 0 {
			delete(d.scenes[remove])
			ordered_remove(&d.scenes, remove)
		}
		if state.activeScenePath != "" && !scene_listed(d, state.activeScenePath) {
			if UI_Button(fmt.tprintf("%s  Add %s", ICON_FA_PLUS, state.activeScenePath), "settings.add-current") {
				ensure_scene_listed(d, state.activeScenePath)
			}
		}
	}
}

// imgui_to_raylib_key maps the key just pressed in the editor to a raylib
// key (for "Press a key" capture of game bindings).
@(private = "file")
imgui_to_raylib_key :: proc(k: imgui.Key) -> (rl.KeyboardKey, bool) {
	if k >= .A && k <= .Z do return rl.KeyboardKey(int(rl.KeyboardKey.A) + int(k) - int(imgui.Key.A)), true
	if k >= ._0 && k <= ._9 do return rl.KeyboardKey(int(rl.KeyboardKey.ZERO) + int(k) - int(imgui.Key._0)), true
	if k >= .F1 && k <= .F12 do return rl.KeyboardKey(int(rl.KeyboardKey.F1) + int(k) - int(imgui.Key.F1)), true
	#partial switch k {
	case .Space: return .SPACE, true
	case .Enter: return .ENTER, true
	case .Escape: return .ESCAPE, true
	case .Tab: return .TAB, true
	case .Backspace: return .BACKSPACE, true
	case .UpArrow: return .UP, true
	case .DownArrow: return .DOWN, true
	case .LeftArrow: return .LEFT, true
	case .RightArrow: return .RIGHT, true
	case .LeftShift: return .LEFT_SHIFT, true
	case .RightShift: return .RIGHT_SHIFT, true
	case .LeftCtrl: return .LEFT_CONTROL, true
	case .RightCtrl: return .RIGHT_CONTROL, true
	case .LeftAlt: return .LEFT_ALT, true
	case .RightAlt: return .RIGHT_ALT, true
	}
	return .KEY_NULL, false
}

@(private = "file")
enum_combo :: proc($T: typeid, id: string, b: ^e.InputBinding) {
	cur := ""
	switch b.deviceType {
	case .KeyboardKey: cur, _ = reflect.enum_name_from_value(b.key)
	case .MouseButton: cur, _ = reflect.enum_name_from_value(b.mouseButton)
	case .GamepadButton: cur, _ = reflect.enum_name_from_value(b.gamepadButton)
	case .GamepadAxis: cur, _ = reflect.enum_name_from_value(b.gamepadAxis)
	case .None:
	}
	imgui.SetNextItemWidth(170)
	if imgui.BeginCombo(fmt.ctprintf("##%s", id), strings.clone_to_cstring(cur, context.temp_allocator), {.HeightLarge}) {
		for f in reflect.enum_fields_zipped(T) {
			if f.name == "KEY_NULL" do continue
			if imgui.Selectable(strings.clone_to_cstring(f.name, context.temp_allocator), f.name == cur) {
				switch b.deviceType {
				case .KeyboardKey: b.key = rl.KeyboardKey(f.value)
				case .MouseButton: b.mouseButton = rl.MouseButton(f.value)
				case .GamepadButton: b.gamepadButton = rl.GamepadButton(f.value)
				case .GamepadAxis: b.gamepadAxis = rl.GamepadAxis(f.value)
				case .None:
				}
			}
			Drive_Item(fmt.tprintf("pick:%s", f.name))
		}
		imgui.EndCombo()
	}
	Drive_Item(id)
}

@(private = "file")
project_input :: proc(state: ^EditorState) {
	d := &st.project
	UI_DimText("Scripts ask for actions, not keys: Input.is_action_down(\"jump\").")
	imgui.Dummy({0, 4})
	h := imgui.GetContentRegionAvail().y
	// Action list.
	if imgui.BeginChild("##actions", {200, h}, {.Borders}, {}) {
		remove := -1
		for a, i in d.actions {
			if imgui.Selectable(fmt.ctprintf("%s##act%d", a.name, i), st.action == i) {
				st.action = i
				st.listening = false
			}
			Drive_Item(fmt.tprintf("settings.action:%s", a.name))
			if imgui.BeginPopupContextItem(fmt.ctprintf("##actctx%d", i)) {
				if imgui.MenuItem(fmt.ctprintf("%s  Remove action", ICON_FA_TRASH)) do remove = i
				imgui.EndPopup()
			}
		}
		if remove >= 0 {
			delete(d.actions[remove].name)
			delete(d.actions[remove].bindings)
			ordered_remove(&d.actions, remove)
			st.action = clamp(st.action, 0, max(len(d.actions) - 1, 0))
		}
		imgui.Separator()
		imgui.SetNextItemWidth(-28)
		enter := imgui.InputTextWithHint("##newaction", "new_action", cstring(raw_data(st.newAction[:])), len(st.newAction), {.EnterReturnsTrue})
		Drive_Item("settings.new-action")
		imgui.SameLine(0, 2)
		add := UI_IconButton(ICON_FA_PLUS, "settings.add-action", "Add action", size = 24)
		name := strings.trim_space(string(cstring(raw_data(st.newAction[:]))))
		if (enter || add) && name != "" {
			exists := false
			for a in d.actions do if strings.equal_fold(a.name, name) do exists = true
			if !exists {
				append(&d.actions, e.Input_Action_Config{name = strings.clone(name), bindings = make([dynamic]e.InputBinding)})
				st.action = len(d.actions) - 1
			}
			st.newAction = {}
		}
	}
	imgui.EndChild()
	imgui.SameLine(0, UI_SPACE)
	if imgui.BeginChild("##bindings", {0, h}, {}, {}) {
		if st.action >= 0 && st.action < len(d.actions) {
			a := &d.actions[st.action]
			UI_PanelTitle(ICON_FA_BOLT, a.name)
			imgui.Dummy({0, 4})
			remove := -1
			for &b, bi in a.bindings {
				imgui.PushIDInt(c.int(bi))
				names := []string{"None", "Key", "Mouse", "Gamepad Button", "Gamepad Axis"}
				imgui.SetNextItemWidth(140)
				if idx, changed := UI_Combo(fmt.tprintf("settings.binding-device:%d", bi), int(b.deviceType), names); changed {
					b = {deviceType = e.InputDeviceType(idx), axisDeadzone = 0.25}
				}
				imgui.SameLine(0, 4)
				switch b.deviceType {
				case .KeyboardKey: enum_combo(rl.KeyboardKey, fmt.tprintf("settings.binding:%d", bi), &b)
				case .MouseButton: enum_combo(rl.MouseButton, fmt.tprintf("settings.binding:%d", bi), &b)
				case .GamepadButton: enum_combo(rl.GamepadButton, fmt.tprintf("settings.binding:%d", bi), &b)
				case .GamepadAxis:
					enum_combo(rl.GamepadAxis, fmt.tprintf("settings.binding:%d", bi), &b)
					imgui.SameLine(0, 4)
					imgui.Checkbox("+##pos", &b.axisPositive)
					UI_Tooltip("Positive direction of the axis")
					imgui.SameLine(0, 4)
					imgui.SetNextItemWidth(80)
					imgui.SliderFloat("##dz", &b.axisDeadzone, 0.05, 0.95, "dz %.2f")
				case .None:
				}
				imgui.SameLine(0, 4)
				if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("settings.remove-binding:%d", bi), "Remove binding", size = 26) do remove = bi
				imgui.PopID()
			}
			if remove >= 0 do ordered_remove(&a.bindings, remove)
			imgui.Dummy({0, 4})
			if len(a.bindings) < e.MAX_BINDINGS_PER_ACTION {
				if st.listening {
					imgui.PushStyleColorImVec4(.Text, UI_WARNING)
					imgui.TextUnformatted("Press a key (Esc cancels)...")
					imgui.PopStyleColor()
					for k in imgui.Key.Tab ..= imgui.Key.F12 {
						if !imgui.IsKeyPressed(k, false) do continue
						if k == .Escape {
							st.listening = false
							break
						}
						if rk, ok := imgui_to_raylib_key(k); ok {
							append(&a.bindings, e.InputBinding{deviceType = .KeyboardKey, key = rk})
							st.listening = false
							break
						}
					}
				} else {
					if UI_Button(fmt.tprintf("%s  Press a Key", ICON_FA_PLUS), "settings.listen-key") do st.listening = true
					imgui.SameLine()
					if UI_Button(fmt.tprintf("%s  Add Binding", ICON_FA_PLUS), "settings.add-binding") {
						append(&a.bindings, e.InputBinding{deviceType = .KeyboardKey, key = .SPACE, axisDeadzone = 0.25})
					}
				}
			} else {
				UI_DimText(fmt.tprintf("At most %d bindings per action.", e.MAX_BINDINGS_PER_ACTION))
			}
		} else {
			UI_DimText("Add an action on the left.")
		}
	}
	imgui.EndChild()
}

@(private = "file")
project_video :: proc(state: ^EditorState) {
	d := &st.project
	if !UI_BeginProps("##video") do return
	UI_PropLabel("Window Title")
	text_field("settings.title", &d.windowTitle)
	UI_PropLabel("Window Size")
	size := [2]c.int{c.int(d.windowWidth), c.int(d.windowHeight)}
	if imgui.DragInt2("##winsize", &size, 1, 160, 7680, "%d px") do d.windowWidth, d.windowHeight = int(size.x), int(size.y)
	Drive_Item("settings.window-size")
	UI_PropLabel("Virtual Resolution")
	vres := [2]f32{d.virtualWidth, d.virtualHeight}
	if imgui.DragFloat2("##vres", &vres, 1, 160, 7680, "%.0f") do d.virtualWidth, d.virtualHeight = vres.x, vres.y
	Drive_Item("settings.virtual-res")
	UI_Tooltip("The resolution the game draws at; it is scaled to fit the window or the screen (fullscreen), with bars where the shapes differ")
	UI_PropLabel("Target FPS")
	fps := c.int(d.targetFPS)
	if imgui.SliderInt("##fps", &fps, 30, 240) do d.targetFPS = int(fps)
	Drive_Item("settings.fps")
	check("settings.fullscreen", "Fullscreen", &d.fullscreen, "Cover the whole screen at its own resolution (the game is scaled to it). Scripts: Engine.set_fullscreen(true)")
	check("settings.sharp-scaling", "Sharp Pixels", &d.sharpScaling, "Scale the game to the window nearest-neighbour - crisp pixel art; off: smooth")
	check("settings.vsync", "VSync", &d.vsync)
	check("settings.resizable", "Resizable Window", &d.resizable)
	check("settings.msaa", "Anti-aliasing (MSAA 4x)", &d.msaa)
	check("settings.high-dpi", "High-DPI", &d.highDPI, "Render at the display's native pixel density")
	UI_EndProps()
}

@(private = "file")
project_audio :: proc(state: ^EditorState) {
	d := &st.project
	if !UI_BeginProps("##audio") do return
	vol :: proc(id, label: string, v: ^f32) {
		UI_PropLabel(label)
		pct := v^ * 100
		if imgui.SliderFloat(fmt.ctprintf("##%s", id), &pct, 0, 100, "%.0f%%") do v^ = pct / 100
		Drive_Item(id)
	}
	vol("settings.master-volume", "Master Volume", &d.masterVolume)
	vol("settings.music-volume", "Music", &d.musicVolume)
	vol("settings.sfx-volume", "Sound Effects", &d.sfxVolume)
	UI_PropLabel("")
	UI_DimText("Music and sound nodes play at their own volume times these.")
	UI_EndProps()
}

@(private = "file")
project_export :: proc(state: ^EditorState) {
	d := &st.project
	x := &d.export
	if UI_BeginProps("##export") {
		UI_PropLabel("Executable Name")
		text_field("settings.export-name", &x.executableName, strings.clone_to_cstring(export_default_name(d), context.temp_allocator))
		UI_PropLabel("Output Folder")
		folder_field(state, "settings.export-dir", &x.outputDir, fmt.tprintf("%s_standalone", strings.trim_suffix(state.projectPath, "/")))
		if len(x.presets) == 0 {
			UI_PropLabel("Targets")
			for t in e.Export_Target {
				on := t in x.targets
				label := fmt.ctprintf("%s##tgt%v", e.export_target_name(t), t)
				if imgui.Checkbox(label, &on) {
					if on do x.targets += {t}
					else do x.targets -= {t}
				}
				Drive_Item(fmt.tprintf("settings.target:%s", e.export_target_name(t)))
				imgui.SameLine()
			}
			imgui.NewLine()
		}
		UI_PropLabel("Runners")
		{
			sb := strings.builder_make(context.temp_allocator)
			for t in e.Export_Target {
				if strings.builder_len(sb) > 0 do strings.write_string(&sb, "   ")
				found := Editor_FindRunner(t) != ""
				fmt.sbprintf(&sb, "%s %s", e.export_target_name(t), "ready" if found else ("built on export" if t == e.native_export_target() else "missing"))
			}
			UI_DimText(strings.to_string(sb))
			Drive_Item("settings.runners")
			UI_Tooltip("Prebuilt game runners (runners/<platform>/ next to the editor, or bin/runners/). Build one per platform with scripts/build_runners.sh")
		}
		check("settings.compress", "Compress Package", &x.compress)
		check("settings.include-font", "Include UI Font", &x.includeFont)
		hasMac := false
		for &p in e.Export_EffectivePresets(x) do if p.target == .MacOS do hasMac = true
		if hasMac {
			exeName := x.executableName if x.executableName != "" else export_default_name(d)
			UI_PropLabel("macOS Bundle ID")
			text_field("settings.bundle-id", &x.bundleId, strings.clone_to_cstring(Export_BundleId(d, exeName), context.temp_allocator))
			UI_PropLabel("Signing Identity")
			text_field("settings.mac-sign", &x.macSign, "ad-hoc (or \"Developer ID Application: ...\", or none)")
			UI_Tooltip("codesign identity for the .app. Ad-hoc runs on this Mac; a Developer ID is needed to distribute (and to notarize)")
			UI_PropLabel("Notary Profile")
			text_field("settings.mac-notary", &x.macNotaryProfile, "keychain profile (xcrun notarytool store-credentials)")
			UI_Tooltip("With a Developer ID identity: the app is notarized and stapled after export")
		}
		UI_EndProps()
	}
	export_presets_section(state)
	imgui.Spacing()
	if UI_PrimaryButton(fmt.tprintf("%s  Save and Export%s", ICON_FA_FLOPPY_DISK, " All" if len(x.presets) > 1 else ""), "settings.export-now") {
		settings_save(state)
		Editor_ExportStandalone(state)
	}
}

@(private = "file")
presetSel: int

@(private = "file")
export_presets_section :: proc(state: ^EditorState) {
	d := &st.project
	x := &d.export
	imgui.SeparatorText("Presets")
	platforms := []string{"macos", "windows", "linux"}
	if len(x.presets) == 0 {
		UI_DimText("One export per target above. Presets give each platform (or a demo / debug build) its own settings.")
		if UI_Button(fmt.tprintf("%s  Use Presets", ICON_FA_PLUS), "settings.preset-convert") {
			for &p in e.Export_EffectivePresets(x) do append(&x.presets, e.Export_Preset{name = strings.clone(p.name), target = p.target})
			presetSel = 0
		}
		return
	}
	presetSel = clamp(presetSel, 0, len(x.presets) - 1)
	// The list.
	for &p, i in x.presets {
		label := fmt.ctprintf("%s  (%s%s)##preset%d", p.name, e.export_target_name(p.target), ", debug" if p.debug else "", i)
		if imgui.Selectable(label, presetSel == i) do presetSel = i
		Drive_Item(fmt.tprintf("settings.preset:%s", p.name))
	}
	if imgui.BeginCombo("##addpreset", fmt.ctprintf("%s  Add Preset", ICON_FA_PLUS), {.NoArrowButton}) {
		for name, k in platforms {
			if imgui.Selectable(strings.clone_to_cstring(name, context.temp_allocator)) {
				n := name
				for j := 2; ; j += 1 {
					taken := false
					for q in x.presets do if q.name == n do taken = true
					if !taken do break
					n = fmt.tprintf("%s %d", name, j)
				}
				append(&x.presets, e.Export_Preset{name = strings.clone(n), target = e.Export_Target(k)})
				presetSel = len(x.presets) - 1
			}
			Drive_Item(fmt.tprintf("pick:%s", name))
		}
		imgui.EndCombo()
	}
	Drive_Item("settings.preset-add")
	imgui.SameLine()
	if UI_Button(fmt.tprintf("%s  Duplicate", ICON_FA_COPY), "settings.preset-dup") {
		c := e.Export_Preset_Clone(&x.presets[presetSel])
		delete(c.name)
		c.name = strings.clone(fmt.tprintf("%s copy", x.presets[presetSel].name))
		append(&x.presets, c)
		presetSel = len(x.presets) - 1
	}
	imgui.SameLine()
	if UI_Button(fmt.tprintf("%s  Remove", ICON_FA_TRASH), "settings.preset-remove") {
		e.Export_Preset_Destroy(&x.presets[presetSel])
		ordered_remove(&x.presets, presetSel)
		if len(x.presets) == 0 do return
		presetSel = clamp(presetSel, 0, len(x.presets) - 1)
	}

	// The selected preset.
	p := &x.presets[presetSel]
	imgui.PushIDInt(i32(presetSel))
	defer imgui.PopID()
	if !UI_BeginProps("##preset") do return
	defer UI_EndProps()
	UI_PropLabel("Name")
	text_field("settings.preset-name", &p.name)
	UI_PropLabel("Platform")
	imgui.SetNextItemWidth(-1)
	if k, changed := UI_Combo("settings.preset-platform", int(p.target), platforms); changed do p.target = e.Export_Target(k)
	exeDefault := x.executableName if x.executableName != "" else export_default_name(d)
	UI_PropLabel("Executable Name")
	text_field("settings.preset-exe", &p.executableName, strings.clone_to_cstring(exeDefault, context.temp_allocator))
	outDefault := fmt.tprintf("%s/%s", x.outputDir if x.outputDir != "" else fmt.tprintf("%s_standalone", strings.trim_suffix(state.projectPath, "/")), export_safe_name(p.name))
	UI_PropLabel("Output Folder")
	folder_field(state, "settings.preset-dir", &p.outputDir, outDefault)
	UI_PropLabel("Version")
	text_field("settings.preset-version", &p.version, strings.clone_to_cstring(fmt.tprintf("project: %s", d.version), context.temp_allocator))
	UI_PropLabel("Icon")
	imgui.SetNextItemWidth(-1)
	if path, ok := asset_picker("settings.preset-icon", p.icon, Editor_ListProjectFiles(state, "", {".png"})); ok {
		delete(p.icon)
		p.icon = strings.clone(path)
	}
	UI_Tooltip("None = the project's icon")
	UI_PropLabel("Window Title")
	text_field("settings.preset-title", &p.windowTitle, strings.clone_to_cstring(fmt.tprintf("project: %s", d.windowTitle), context.temp_allocator))
	UI_PropLabel("Window Size")
	size := [2]i32{i32(p.windowWidth), i32(p.windowHeight)}
	imgui.SetNextItemWidth(-1)
	if imgui.DragInt2("##presetsize", &size, 1, 0, 8192, "%d") {
		p.windowWidth, p.windowHeight = int(max(size.x, 0)), int(max(size.y, 0))
	}
	Drive_Item("settings.preset-size")
	UI_Tooltip("0 x 0 = the project's window size")
	UI_PropLabel("Fullscreen")
	imgui.SetNextItemWidth(-1)
	if k, changed := UI_Combo("settings.preset-fullscreen", int(p.fullscreen), {"Project setting", "On", "Off"}); changed do p.fullscreen = e.Export_Toggle(k)
	UI_PropLabel("Include")
	pattern_list("settings.preset-include", &p.include, "everything (or one pattern per line: scenes, textures/*.png)")
	UI_PropLabel("Exclude")
	pattern_list("settings.preset-exclude", &p.exclude, "one pattern per line: *.psd, raw/, levels/test_*")
	UI_PropLabel("Debug")
	imgui.Checkbox("##presetdebug", &p.debug)
	Drive_Item("settings.preset-debug")
	UI_Tooltip("Use the debug runner (debug info; a console window on Windows)")
	UI_PropLabel("")
	if UI_Button(fmt.tprintf("%s  Save and Export This Preset", ICON_FA_BOX_ARCHIVE), "settings.export-preset") {
		settings_save(state)
		Editor_ExportStandalone(state, only = presetSel)
	}
}

// pattern_list edits a list of patterns as lines of text.
@(private = "file")
pattern_list :: proc(id: string, list: ^[dynamic]string, hint: string) {
	@(static) buf: [2048]u8
	@(static) editing: string
	if editing != id {
		joined := strings.join(list[:], "\n", context.temp_allocator)
		buf = {}
		copy(buf[:len(buf) - 1], joined)
	}
	if imgui.InputTextMultiline(fmt.ctprintf("##%s", id), cstring(raw_data(buf[:])), len(buf), {-1, 54}) {
		for s in list do delete(s)
		clear(list)
		for line in strings.split_lines(string(cstring(raw_data(buf[:]))), context.temp_allocator) {
			if t := strings.trim_space(line); t != "" do append(list, strings.clone(t))
		}
	}
	if imgui.IsItemActivated() {
		delete(editing)
		editing = strings.clone(id)
	}
	if imgui.IsItemDeactivated() {
		delete(editing)
		editing = ""
	}
	Drive_Item(id)
	if len(list) == 0 do UI_Tooltip(hint)
}

export_default_name :: proc(d: ^e.ProjectConfig) -> string {
	n, _ := strings.remove_all(d.name, " ", context.temp_allocator)
	n, _ = strings.remove_all(n, "(", context.temp_allocator)
	n, _ = strings.remove_all(n, ")", context.temp_allocator)
	n, _ = strings.remove_all(n, ".", context.temp_allocator)
	return n if n != "" else "Game"
}
