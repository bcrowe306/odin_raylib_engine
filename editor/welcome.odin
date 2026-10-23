package editor

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import imgui "lib/imgui"

// ============================================================================
// Welcome window (at startup unless turned off; Help > Welcome): recent
// projects, a new project from a template (project_templates.odin), Open
// Project, and a few pointers for a first session.
// ============================================================================

@(private = "file")
welcome: struct {
	open:      bool,
	shown:     bool, // opened at startup already
	template:  Project_Template,
	nameBuf:   [128]u8,
	whereBuf:  [512]u8,
}

Welcome_Open :: proc(state: ^EditorState) {
	welcome.open = true
	if welcome.nameBuf[0] == 0 do copy(welcome.nameBuf[:len(welcome.nameBuf) - 1], "My Game")
	if welcome.whereBuf[0] == 0 {
		parent := filepath.dir(strings.trim_suffix(state.projectPath, "/"), context.temp_allocator)
		if abs, err := filepath.abs(parent, context.temp_allocator); err == nil do parent = abs
		parent = Editor_StartDir(.Projects, parent) // where the last project was made / opened
		copy(welcome.whereBuf[:len(welcome.whereBuf) - 1], parent)
	}
}

Welcome_IsOpen :: proc() -> bool {return welcome.open}

// Welcome_Render: call every frame (opens itself once at startup).
Welcome_Render :: proc(state: ^EditorState) {
	if !welcome.shown {
		welcome.shown = true
		if GlobalSettings.showWelcome && !GlobalDrive.enabled do Welcome_Open(state)
	}
	if !welcome.open do return
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	imgui.SetNextWindowSize({820, 520}, .Appearing)
	// Its own surface (lighter than the panels: two steps on dark themes)
	// and an accent edge, so it
	// stands out above the editor.
	surface := UI_BG_RAISED if UI_THEME_LIGHT else UI_BG_HOVER
	imgui.PushStyleColorImVec4(.WindowBg, surface)
	imgui.PushStyleColorImVec4(.TitleBg, surface)
	imgui.PushStyleColorImVec4(.TitleBgActive, surface)
	imgui.PushStyleColorImVec4(.Border, ui_accent(0.45))
	imgui.PushStyleVar(.WindowBorderSize, 1)
	imgui.PushStyleVar(.WindowRounding, 10)
	defer imgui.End()
	visible := imgui.Begin("Welcome###WelcomeWindow", &welcome.open, {.NoCollapse, .NoDocking})
	imgui.PopStyleVar(2)
	imgui.PopStyleColor(4)
	if !visible do return
	// Cards and inputs one step brighter than the window.
	imgui.PushStyleColorImVec4(.FrameBg, UI_BG_PANEL if UI_THEME_LIGHT else UI_BG_ACTIVE)
	imgui.PushStyleColorImVec4(.Button, UI_BG_PANEL if UI_THEME_LIGHT else UI_BG_ACTIVE)
	defer imgui.PopStyleColor(2)

	imgui.PushFont(GlobalFonts.semibold)
	imgui.TextUnformatted(fmt.ctprintf("%s  Welcome to the Ore editor", ICON_FA_WAND_MAGIC_SPARKLES))
	imgui.PopFont()
	UI_DimText(fmt.tprintf("Editing %s", state.projectConfig.name if state.projectConfig.name != "" else state.projectPath))
	imgui.Dummy({0, 6})

	// --- left: recent projects and pointers ---
	if imgui.BeginChild("##welcome_left", {300, -40}, {}, {}) {
		UI_SectionHeader("Recent Projects")
		if len(GlobalSettings.recentProjects) == 0 do UI_DimText("None yet.")
		for r in GlobalSettings.recentProjects {
			if imgui.Selectable(fmt.ctprintf("%s  %s##wr_%s", ICON_FA_FOLDER, filepath.base(r), r), false, {}, {0, 24}) {
				Editor_SwitchProject(state, r)
			}
			Drive_Item(fmt.tprintf("welcome.recent:%s", filepath.base(r)))
			UI_Tooltip(r)
		}
		imgui.Dummy({0, 4})
		if UI_Button(fmt.tprintf("%s  Open Project...", ICON_FA_FOLDER_OPEN), "welcome.open", {-1, 0}) {
			welcome.open = false
			Editor_OpenProjectDialog(state)
		}
		imgui.Dummy({0, 8})
		UI_SectionHeader("First Steps")
		imgui.PushTextWrapPos(0)
		tip :: proc(icon, text: string) {
			imgui.PushStyleColorImVec4(.Text, UI_ACCENT)
			imgui.TextUnformatted(strings.clone_to_cstring(icon, context.temp_allocator))
			imgui.PopStyleColor()
			imgui.SameLine(26)
			imgui.TextWrapped("%s", strings.clone_to_cstring(text, context.temp_allocator))
		}
		tip(ICON_FA_PLUS, "Cmd+A adds a node; drag images from Assets into the viewport for sprites.")
		tip(ICON_FA_CODE, "Attach a Lua script in the Inspector; saving reloads it, even while playing.")
		tip(ICON_FA_PLAY, "F5 plays the game; the Game tab shows its live scene tree.")
		tip(ICON_FA_MAGNIFYING_GLASS, "Cmd+P finds files and commands; hover a property for help.")
		imgui.PopTextWrapPos()
	}
	imgui.EndChild()
	imgui.SameLine()

	// --- right: new project ---
	if imgui.BeginChild("##welcome_new", {0, -40}, {.Borders}, {}) {
		UI_SectionHeader("New Project")
		for t in Project_Template {
			info := PROJECT_TEMPLATES[t]
			selected := welcome.template == t
			if imgui.Selectable(fmt.ctprintf("##tmpl_%v", t), selected, {}, {0, 46}) do welcome.template = t
			Drive_Item(fmt.tprintf("welcome.template:%s", info.name))
			mn := imgui.GetItemRectMin()
			dl := imgui.GetWindowDrawList()
			imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.regular, 22, {mn.x + 8, mn.y + 11}, col_u32(UI_ACCENT if selected else UI_TEXT_DIM), strings.clone_to_cstring(info.icon, context.temp_allocator))
			imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.semibold, 15, {mn.x + 44, mn.y + 4}, col_u32(UI_TEXT), strings.clone_to_cstring(info.name, context.temp_allocator))
			clip := imgui.Vec4{mn.x, mn.y, mn.x + imgui.GetContentRegionAvail().x, mn.y + 46}
			imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, 12.5, {mn.x + 44, mn.y + 24}, col_u32(UI_TEXT_DIM), strings.clone_to_cstring(info.description, context.temp_allocator), nil, 0, &clip)
		}
		imgui.Dummy({0, 6})
		if UI_BeginProps("##newproj") {
			UI_PropLabel("Name")
			imgui.InputText("##wname", cstring(raw_data(welcome.nameBuf[:])), len(welcome.nameBuf))
			Drive_Item("welcome.name")
			UI_PropLabel("Location")
			imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x - 90)
			imgui.InputText("##wwhere", cstring(raw_data(welcome.whereBuf[:])), len(welcome.whereBuf))
			Drive_Item("welcome.where")
			imgui.SameLine(0, 4)
			if UI_Button("Browse...", "welcome.where.browse", {86, 0}) {
				start := strings.clone(string(cstring(raw_data(welcome.whereBuf[:]))), context.temp_allocator)
				NativeDialog_Open(state, {title = "New Project Location", folders = true, start = start}, proc(state: ^EditorState, paths: []string) {
					welcome.whereBuf = {}
					copy(welcome.whereBuf[:len(welcome.whereBuf) - 1], paths[0])
				})
			}
			UI_EndProps()
		}
		name := strings.trim_space(string(cstring(raw_data(welcome.nameBuf[:]))))
		location := strings.trim_space(string(cstring(raw_data(welcome.whereBuf[:]))))
		folder, _ := strings.replace_all(name, " ", "_", context.temp_allocator)
		dir, _ := filepath.join({location, folder}, context.temp_allocator)
		UI_DimText(dir)
		if UI_PrimaryButton(fmt.tprintf("%s  Create Project", ICON_FA_PLUS), "welcome.create", {-1, 0}) && name != "" {
			if Project_CreateFromTemplate(dir, name, welcome.template) {
				Editor_Log(state, .Info, "Created %s project %s", PROJECT_TEMPLATES[welcome.template].name, dir)
				welcome.open = false
				Editor_SwitchProject(state, strings.clone(dir, context.temp_allocator))
			} else {
				Editor_Log(state, .Error, "Could not create a project in %s (is there one already?)", dir)
			}
		}
	}
	imgui.EndChild()

	if imgui.Checkbox("Show at startup", &GlobalSettings.showWelcome) do _ = Editor_SaveSettings()
	imgui.SameLine(imgui.GetWindowWidth() - 120)
	if UI_Button("Close", "welcome.close", {100, 0}) do welcome.open = false
}
