package editor

import "core:c"
import "core:fmt"
import "core:os"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"
import imgui_rl "lib/imgui/imgui_impl_raylib"

// ============================================================================
// Editor Main Application Entry Point
// ============================================================================

TOOLBAR_HEIGHT :: 44.0
STATUS_BAR_HEIGHT :: 28.0

faRanges: [3]imgui.Wchar = {0xE000, 0xF8FF, 0}

main :: proc() {
	os.exit(editor_main())
}

editor_main :: proc() -> int {
	isTestMode := false
	for arg in os.args {
		if arg == "--test-e2e" || arg == "--drive" {
			isTestMode = true
			break
		}
	}

	// 1. Configure and Initialize Raylib Window
	if isTestMode {
		rl.SetConfigFlags({.WINDOW_RESIZABLE})
	} else {
		rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	}
	rl.InitWindow(1600, 900, "Odin Raylib Engine - Game Editor")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)
	rl.SetExitKey(.KEY_NULL) // Esc is an editor key (deselect, close popups), not "quit"

	rl.InitAudioDevice()
	defer rl.CloseAudioDevice()

	// 2. Initialize Dear ImGui Context
	imgui.CreateContext(nil)
	defer imgui.DestroyContext(nil)

	io := imgui.GetIO()
	io.ConfigFlags += {.DockingEnable}
	driving := TestDrive_Init(&GlobalDrive)
	if driving {
		// Every drive starts from the default layout, not the user's imgui.ini.
		io.IniFilename = nil
	}

	// Open Sans (regular / semibold / small) with Font Awesome merged in,
	// and the flat editor theme (ui_style.odin).
	UI_LoadFonts()
	UI_ApplyTheme()

	// 3. Initialize Raylib ImGui Backend
	imgui_rl.init()
	defer imgui_rl.shutdown()
	imgui_rl.build_font_atlas()

	// 4. Initialize Core Editor State & Test Harness
	Editor_Init(&GlobalEditor)
	Actions_Init()
	Editor_LoadSettings(&GlobalEditor)
	Lua_ProjectSetup(&GlobalEditor) // .ore/definitions + .luarc.json for Lua tooling
	defer Editor_Shutdown(&GlobalEditor)


	// 5. Main Application Loop
	for !GlobalEditor.quitConfirmed {
		// The window's close button asks about unsaved work first.
		if rl.WindowShouldClose() do Editor_RequestQuit(&GlobalEditor)
		// Poll build / game processes, stream their output to the console
		Editor_UpdatePlaytest(&GlobalEditor)
		NativeDialog_Poll(&GlobalEditor)
		Lua_UpdateProjectTypes(&GlobalEditor)
		if n := e.Shader_CheckForChanges(); n > 0 do Editor_Log(&GlobalEditor, .Info, "Reloaded %d changed shader(s)", n)
		if n := e.ScriptManager_CheckForChanges(&GlobalEditor.game.scriptManager); n > 0 {
			Editor_Log(&GlobalEditor, .Info, "Reloaded %d changed script(s)", n)
		}
		// LDtk files saved in LDtk reload live in the editor too.
		if scene := GlobalEditor.activeScene; scene != nil && scene.manager != nil {
			for n in scene.manager.nodes {
				if n != nil && n.typeId == e.LdtkLevelNode && e.LdtkLevelNode_CheckForChanges(cast(^e.LdtkLevelNode)n) {
					Editor_Log(&GlobalEditor, .Info, "Reloaded LDtk level %s", (cast(^e.LdtkLevelNode)n).projectPath)
				}
			}
		}

		imgui_rl.process_events()
		imgui_rl.new_frame()
		if TestDrive_BeginFrame(&GlobalDrive, &GlobalEditor) do break
		imgui.NewFrame()

		displayW := f32(rl.GetScreenWidth())
		displayH := f32(rl.GetScreenHeight())

		// Keyboard shortcuts: one action table (actions.odin) for the scene,
		// the code editor and global commands.
		Editor_SyncSelection(&GlobalEditor)
		Editor_Autosave(&GlobalEditor)
		Actions_Dispatch(&GlobalEditor)

		// --------------------------------------------------------------------
		// 1. Standard Main Menu Bar (File, Edit, View, Tools, Help)
		// --------------------------------------------------------------------
		menuBarH := MainMenu_Render(&GlobalEditor)
		if menuBarH <= 0 do menuBarH = 22.0

		// --------------------------------------------------------------------
		// 2. Fixed Top Toolbar with FontAwesome Icons
		// --------------------------------------------------------------------
		Toolbar_Render(&GlobalEditor, displayW, TOOLBAR_HEIGHT, menuBarH)

		// --------------------------------------------------------------------
		// 3. Fixed Bottom Status Bar
		// --------------------------------------------------------------------
		StatusBar_Render(&GlobalEditor, displayW, displayH, STATUS_BAR_HEIGHT)

		// --------------------------------------------------------------------
		// 4. Central DockSpace Host Window
		// --------------------------------------------------------------------
		dockAreaY := menuBarH + TOOLBAR_HEIGHT
		dockAreaH := displayH - dockAreaY - STATUS_BAR_HEIGHT
		dockAreaPos := imgui.Vec2{0, dockAreaY}
		dockAreaSize := imgui.Vec2{displayW, dockAreaH}

		imgui.SetNextWindowPos(dockAreaPos)
		imgui.SetNextWindowSize(dockAreaSize)
		dockHostFlags: imgui.WindowFlags = {
			.NoTitleBar,
			.NoCollapse,
			.NoResize,
			.NoMove,
			.NoBringToFrontOnFocus,
			.NoNavFocus,
			.NoBackground,
		}

		imgui.PushStyleVarImVec2(imgui.StyleVar.WindowPadding, imgui.Vec2{0, 0})
		imgui.Begin("##EditorDockSpaceHost", nil, dockHostFlags)
		imgui.PopStyleVar()

		dockspaceID := imgui.GetID("EditorMainDockSpace_v4")

		if DockBuilderGetNode(dockspaceID) == nil {
			DockBuilderRemoveNode(dockspaceID)
			DockBuilderAddNode(dockspaceID, 0)
			DockBuilderSetNodePos(dockspaceID, dockAreaPos)
			DockBuilderSetNodeSize(dockspaceID, dockAreaSize)

			dockMain := dockspaceID
			dockBottom: imgui.ID
			dockLeft: imgui.ID
			dockRight: imgui.ID

			// Left column: Assets over Preview. Right column: Scene over
			// Inspector. Bottom (under the viewport): Console.
			DockBuilderSplitNode(dockMain, .Left, 0.20, &dockLeft, &dockMain)
			dockLeftPreview: imgui.ID
			DockBuilderSplitNode(dockLeft, .Down, 0.36, &dockLeftPreview, &dockLeft)
			DockBuilderDockWindow("Assets###AssetBrowserWindow", dockLeft)
			DockBuilderDockWindow("Preview###PreviewPanelWindow", dockLeftPreview)

			DockBuilderSplitNode(dockMain, .Right, 0.25, &dockRight, &dockMain)
			DockBuilderSplitNode(dockMain, .Down, 0.28, &dockBottom, &dockMain)
			DockBuilderDockWindow("Console###BottomPanelWindow", dockBottom)


			dockInspector: imgui.ID
			dockHierarchy: imgui.ID
			DockBuilderSplitNode(dockRight, .Down, 0.50, &dockInspector, &dockHierarchy)
			DockBuilderDockWindow("Scene###SceneHierarchyWindow", dockHierarchy)
			DockBuilderDockWindow("Inspector###InspectorWindow", dockInspector)

			// 4. Center remaining space -> Viewport
			DockBuilderDockWindow("Viewport###ViewportWindow", dockMain)

			DockBuilderFinish(dockspaceID)
		}

		imgui.DockSpace(dockspaceID, imgui.Vec2{0, 0}, {.PassthruCentralNode, .AutoHideTabBar}) // panels draw their own headers
		imgui.End()

		// --------------------------------------------------------------------
		// 5. Render Dockable Editor Panels & Dialogs
		// --------------------------------------------------------------------
		AssetBrowser_Render(&GlobalEditor)
		Viewport_UpdateAndRender(&GlobalEditor)
		Code_Render(&GlobalEditor)
		SceneInspector_Render(&GlobalEditor)
		BottomPanel_Render(&GlobalEditor)
		PreviewPanel_Render(&GlobalEditor)

		// Modals & Popups
		AddNodeDialog_Render(&GlobalEditor)
		ProjectSettingsDialog_Render(&GlobalEditor)
		Palette_Render(&GlobalEditor)
		Shortcuts_Render(&GlobalEditor)
		Rename_Render(&GlobalEditor)
		QuitPrompt_Render(&GlobalEditor)
		Prompt_Render(&GlobalEditor)
		AssetDelete_Render(&GlobalEditor)
		OpenProject_Render(&GlobalEditor)
		Signals_Render(&GlobalEditor)
		AssetImport_Render(&GlobalEditor)

		// Files dropped from the OS (after the panels: their rects are current).
		Editor_HandleFileDrops(&GlobalEditor)

		// --------------------------------------------------------------------
		// 6. Automated Test-Drive Hook
		// --------------------------------------------------------------------

		// End Frame and Draw
		imgui.Render()

		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{20, 23, 27, 255})
		imgui_rl.render_draw_data(imgui.GetDrawData())
		TestDrive_EndFrame(&GlobalDrive)
		rl.EndDrawing()
	}
	Editor_LaunchPendingProject(&GlobalEditor)
	return TestDrive_ExitCode(&GlobalDrive) if driving else 0
}

// GitKraken-inspired sleek dark theme styling
SetupGitKrakenTheme :: proc() {
	style := imgui.GetStyle()

	style.WindowRounding = 5.0
	style.ChildRounding = 4.0
	style.FrameRounding = 4.0
	style.PopupRounding = 5.0
	style.ScrollbarRounding = 5.0
	style.GrabRounding = 4.0
	style.TabRounding = 5.0

	style.WindowBorderSize = 1.0
	style.ChildBorderSize = 1.0
	style.FrameBorderSize = 0.0
	style.PopupBorderSize = 1.0
	style.TabBorderSize = 0.0

	style.WindowPadding = imgui.Vec2{8, 8}
	style.FramePadding = imgui.Vec2{6, 4}
	style.ItemSpacing = imgui.Vec2{6, 6}
	style.ItemInnerSpacing = imgui.Vec2{4, 4}

	colors := &style.Colors

	// Text
	colors[imgui.Col.Text] = imgui.Vec4{0.90, 0.92, 0.94, 1.00}
	colors[imgui.Col.TextDisabled] = imgui.Vec4{0.48, 0.52, 0.58, 1.00}

	// Windows & Popups
	colors[imgui.Col.WindowBg] = imgui.Vec4{0.11, 0.13, 0.16, 1.00}
	colors[imgui.Col.ChildBg] = imgui.Vec4{0.09, 0.10, 0.13, 1.00}
	colors[imgui.Col.PopupBg] = imgui.Vec4{0.13, 0.15, 0.18, 0.98}

	// Borders
	colors[imgui.Col.Border] = imgui.Vec4{0.18, 0.21, 0.26, 0.90}
	colors[imgui.Col.BorderShadow] = imgui.Vec4{0.00, 0.00, 0.00, 0.00}

	// Headers & Menus
	colors[imgui.Col.MenuBarBg] = imgui.Vec4{0.08, 0.09, 0.11, 1.00}
	colors[imgui.Col.Header] = imgui.Vec4{0.16, 0.20, 0.26, 0.85}
	colors[imgui.Col.HeaderHovered] = imgui.Vec4{0.20, 0.25, 0.33, 0.95}
	colors[imgui.Col.HeaderActive] = imgui.Vec4{0.24, 0.31, 0.40, 1.00}

	// Buttons
	colors[imgui.Col.Button] = imgui.Vec4{0.15, 0.18, 0.23, 0.90}
	colors[imgui.Col.ButtonHovered] = imgui.Vec4{0.20, 0.25, 0.32, 1.00}
	colors[imgui.Col.ButtonActive] = imgui.Vec4{0.00, 0.65, 0.60, 0.90}

	// Frame backgrounds
	colors[imgui.Col.FrameBg] = imgui.Vec4{0.13, 0.15, 0.19, 0.90}
	colors[imgui.Col.FrameBgHovered] = imgui.Vec4{0.17, 0.21, 0.27, 0.95}
	colors[imgui.Col.FrameBgActive] = imgui.Vec4{0.21, 0.26, 0.34, 1.00}

	// Title bars
	colors[imgui.Col.TitleBg] = imgui.Vec4{0.09, 0.10, 0.13, 1.00}
	colors[imgui.Col.TitleBgActive] = imgui.Vec4{0.12, 0.14, 0.18, 1.00}
	colors[imgui.Col.TitleBgCollapsed] = imgui.Vec4{0.08, 0.09, 0.11, 1.00}

	// Tabs
	colors[imgui.Col.Tab] = imgui.Vec4{0.12, 0.14, 0.17, 1.00}
	colors[imgui.Col.TabHovered] = imgui.Vec4{0.18, 0.22, 0.28, 1.00}
	colors[imgui.Col.TabSelected] = imgui.Vec4{0.15, 0.18, 0.23, 1.00}
	colors[imgui.Col.TabSelectedOverline] = imgui.Vec4{0.00, 0.81, 0.79, 1.00}
	colors[imgui.Col.TabDimmed] = imgui.Vec4{0.10, 0.11, 0.14, 1.00}
	colors[imgui.Col.TabDimmedSelected] = imgui.Vec4{0.13, 0.15, 0.19, 1.00}

	// Accents
	colors[imgui.Col.CheckMark] = imgui.Vec4{0.00, 0.81, 0.79, 1.00}
	colors[imgui.Col.SliderGrab] = imgui.Vec4{0.00, 0.72, 0.65, 1.00}
	colors[imgui.Col.SliderGrabActive] = imgui.Vec4{0.00, 0.85, 0.77, 1.00}
	colors[imgui.Col.ScrollbarBg] = imgui.Vec4{0.09, 0.10, 0.13, 0.60}
	colors[imgui.Col.ScrollbarGrab] = imgui.Vec4{0.18, 0.21, 0.26, 1.00}
	colors[imgui.Col.ScrollbarGrabHovered] = imgui.Vec4{0.24, 0.28, 0.35, 1.00}
	colors[imgui.Col.ScrollbarGrabActive] = imgui.Vec4{0.30, 0.35, 0.44, 1.00}

	// Separator
	colors[imgui.Col.Separator] = imgui.Vec4{0.18, 0.21, 0.26, 0.80}
	colors[imgui.Col.SeparatorHovered] = imgui.Vec4{0.00, 0.81, 0.79, 0.80}
	colors[imgui.Col.SeparatorActive] = imgui.Vec4{0.00, 0.81, 0.79, 1.00}
}
