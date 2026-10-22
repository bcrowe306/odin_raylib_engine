package editor

import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import e "../engine"

// ============================================================================
// Editor Core State & Data Types
// ============================================================================

ToolMode :: enum {
	Select = 0,
	Translate,
	Rotate,
	Scale,
	Pan,
}

GizmoHandle :: enum {
	None = 0,
	TranslateX,
	TranslateY,
	TranslateCenter,
	RotateRing,
	ScaleCorner,
	ScaleX,
	ScaleY,
}

BottomTab :: enum {
	Console = 0,
	Output,
	Profiler,
	Animation,
}

ViewportTab :: enum {
	SceneViewport = 0,
	ComponentViewport,
}

Build_Kind :: enum {
	Game,       // the game binary for Play (launches it)
	Standalone, // the runner for an exported standalone game
	Notarize,   // notarizing an exported macOS app
}

Drag_Start :: struct {
	node:       ^e.Node,
	startPos:   [2]f32, // world
	startRot:   f32,
	startScale: [2]f32,
}

LogLevel :: enum {
	Info = 0,
	Warn,
	Error,
}

LogEntry :: struct {
	time:    string,
	level:   LogLevel,
	message: string,
}

ComponentDef :: struct {
	name:        string,
	category:    string,
	description: string,
	jsonSnippet: string,
}

PreviewPanelTab :: enum {
	Texture,
	Audio,
	Animation,
	Scene,
	Script,
}

EditorState :: struct {
	// Project & Game
	game:              ^e.Game,
	projectConfig:     e.ProjectConfig,
	projectPath:       string,
	projectLoaded:     bool,
	activeScenePath:   string,
	activeScene:       ^e.Scene,
	selectedNode:      ^e.Node,
	selectedAssetPath: string,

	// Separate Game Process Management (see playtest.odin)
	gameProcess:        os.Process,
	gameProcessRunning: bool,
	showProjectSettings: bool,
	pendingPlayMode:    Play_Mode,
	pendingPlayScene:   string,
	lastPlayedScene:    string,
	gameOutput:         ^os.File,
	gameLineBuf:        [dynamic]u8,
	buildProcess:       os.Process,
	buildOutput:        ^os.File,
	buildLineBuf:       [dynamic]u8,
	buildRunning:       bool,
	buildKind:          Build_Kind, // what to do when the build succeeds
	exportDir:          string,     // standalone export folder (owned)
	exportOnly:         int,        // the preset being exported (-1 = all), for after the runner build
	buildStarted:       time.Tick,
	skipGameBuild:      bool,             // --no-build: never rebuild before Play
	extraGameArgs:      [dynamic]string,  // appended to the game command line (tests)

	// Saved state of each open scene; a scene is modified when it differs.
	sceneBaselines:     map[^e.Scene]string, // presence = the scene has a file state ("" values)
	// Edit versions (scene_edit_ops.odin): every recorded edit bumps the
	// scene's version; a scene is modified when it differs from the saved one.
	sceneVersion:       map[^e.Scene]int,
	savedVersion:       map[^e.Scene]int,
	nextVersion:        int,
	componentDocs:      map[^e.Scene]bool, // open component (prefab) documents
	sceneViews:         map[^e.Scene][3]f32, // remembered camera x, y, zoom per document
	modifiedCacheScene:  ^e.Scene,
	modifiedCacheValue:  bool,
	modifiedCacheFrames: int,
	modifiedCountValue:  int,
	modifiedCountFrames: int,
	quitRequested:      bool, // asks about unsaved work (QuitPrompt_Render)
	quitConfirmed:      bool, // leave the main loop
	pendingProject:     string, // reopen the editor on this project after quitting
	undoStack:          [dynamic]Undo_Entry,
	redoStack:          [dynamic]Undo_Entry,

	// Tools & Viewport
	toolMode:         ToolMode,
	activeHandle:     GizmoHandle,
	viewportTab:      ViewportTab,
	bottomTab:        BottomTab,
	cameraPos:        [2]f32,
	cameraZoom:       f32,
	renderTexture:    rl.RenderTexture2D,
	viewportSize:     [2]f32,
	viewportPos:      [2]f32, // Screen position of viewport image in ImGui window
	viewportHovered:  bool,
	viewportFocused:  bool,
	viewportDockId:   u32, // dock node of the Viewport (the Code tab joins it)
	// Multi-selection (selectedNode is the primary; see scene_selection.odin).
	selection:        [dynamic]^e.Node,
	boxSelecting:     bool,
	boxStart:         [2]f32,
	dragOthers:       [dynamic]Drag_Start,

	// Dragging / Gizmo interaction
	isDraggingGizmo:  bool,
	dragStartMouse:   [2]f32,
	dragStartPos:     [2]f32,
	dragStartRot:     f32,
	dragStartScale:   [2]f32,

	// Simulation
	isSimulating:     bool,
	isPaused:         bool,
	snapshotJson:     string, // Serialized scene JSON before simulation started

	// Snapping & Overlays
	snapGrid:         bool,
	gridSize:         f32,
	snapRotation:     bool,
	rotationSnapStep: f32,
	showBounds:       bool,
	showGrid:         bool,
	showCameraBounds: bool,

	// Console & Logs
	logs:             [dynamic]LogEntry,
	consoleFilter:    [64]u8,
	consoleAutoScroll: bool,

	// Reusable Components / Prefabs
	components:       [dynamic]ComponentDef,
	selectedCompIdx:  int,

	// Status info
	statusText:       string,
	fpsHistory:       [60]f32,
	fpsIdx:           int,

	// Preview Panel State
	previewTab:            PreviewPanelTab,
	previewAutoSwitch:     bool,

	// Texture Preview State
	previewTexture:        rl.Texture,
	previewTextureLoaded:  bool,
	previewTexturePath:    string,
	previewTextureZoom:    f32,
	previewTextureFit:     bool,

	// Audio Preview State
	previewSound:          rl.Sound,
	previewSoundLoaded:    bool,
	previewSoundPath:      string,
	previewAudioPlaying:   bool,
	previewAudioVolume:    f32,
	previewAudioLoop:      bool,
	previewAudioTimer:     f32,
	previewAudioDuration:  f32,

	// Animation Preview State
	previewAnimFrames:     [dynamic]rl.Texture,
	previewAnimPaths:      [dynamic]string,
	previewAnimPlaying:    bool,
	previewAnimIndex:      int,
	previewAnimTimer:      f32,
	previewAnimFPS:        f32,
	previewAnimLoop:       bool,
	previewAnimLoadedPath: string,

	// Selected Scene/Script Preview overrides
	previewScenePath:      string,
	previewScriptPath:     string,
}

GlobalEditor: EditorState

Editor_Init :: proc(state: ^EditorState) {
	state.game = new(e.Game)
	e.InitializeGame(state.game)

	state.projectPath = "assets/demo_project"
	for i := 0; i < len(os.args); i += 1 {
		if os.args[i] == "--project" && i + 1 < len(os.args) do state.projectPath = os.args[i + 1]
		if os.args[i] == "--no-build" do state.skipGameBuild = true
	}
	state.sceneBaselines = make(map[^e.Scene]string)
	state.sceneVersion = make(map[^e.Scene]int)
	state.savedVersion = make(map[^e.Scene]int)
	state.toolMode = .Select
	state.activeHandle = .None
	state.viewportTab = .SceneViewport
	state.bottomTab = .Console
	state.cameraPos = {640.0, 360.0}
	state.cameraZoom = 1.0
	state.snapGrid = true
	state.gridSize = 32.0
	state.snapRotation = false
	state.rotationSnapStep = 15.0
	state.showBounds = false
	state.showGrid = true
	state.showCameraBounds = true
	state.consoleAutoScroll = true

	state.previewTab = .Texture
	state.previewAutoSwitch = true
	state.previewTextureZoom = 1.0
	state.previewTextureFit = true
	state.previewAudioVolume = 0.8
	state.previewAudioLoop = false
	state.previewAnimPlaying = true
	state.previewAnimFPS = 12.0
	state.previewAnimLoop = true
	state.previewAnimFrames = make([dynamic]rl.Texture)
	state.previewAnimPaths = make([dynamic]string)
	state.selectedCompIdx = -1
	state.statusText = "Ready"
	state.gameProcessRunning = false
	state.showProjectSettings = false

	state.logs = make([dynamic]LogEntry)
	state.components = make([dynamic]ComponentDef)

	// Create initial render texture
	state.viewportSize = {1280, 720}
	state.renderTexture = rl.LoadRenderTexture(1280, 720)

	// Load the project for editing: scenes are registered but no gameplay
	// code runs (no ready(), no scripts) until you Play.
	if cfg, ok := e.Game_LoadProjectForEditing(state.game, state.projectPath); ok {
		state.projectConfig = cfg
		state.projectLoaded = true
		Editor_Log(state, .Info, "Loaded project: %s", state.projectPath)
		initial := cfg.initialScene
		if e.Game_FindSceneByFile(state.game, initial) == nil && len(cfg.scenes) > 0 {
			initial = cfg.scenes[0]
		}
		if !Editor_OpenScene(state, initial) {
			state.activeScene = state.game->createScene("DefaultScene", true, nil)
		}
	} else {
		// Fallback empty scene
		state.activeScene = state.game->createScene("DefaultScene", true, nil)
		Editor_Log(state, .Warn, "No project found at %s, initialized empty scene", state.projectPath)
	}

	// Lua event handlers only run while simulating (or in the game).
	state.game.scriptManager.suspended = true
	Editor_RegisterBuiltinComponents(state)
	Editor_Log(state, .Info, "Odin Raylib Engine GUI Editor initialized")
}

Editor_Shutdown :: proc(state: ^EditorState) {
	Code_Shutdown()
	Palette_Shutdown()
	AnimationPanel_Shutdown()
	InspectorFields_Shutdown()
	delete(state.selection)
	delete(state.dragOthers)
	if state.gameProcessRunning {
		Editor_StopGameProcess(state)
	}

	e.ProjectConfig_Destroy(&state.projectConfig)

	if state.renderTexture.id != 0 {
		rl.UnloadRenderTexture(state.renderTexture)
	}

	for &log in state.logs {
		delete(log.time)
		delete(log.message)
	}
	delete(state.logs)

	for &comp in state.components {
		delete(comp.name)
		delete(comp.category)
		delete(comp.description)
		delete(comp.jsonSnippet)
	}
	delete(state.components)

	if state.snapshotJson != "" {
		delete(state.snapshotJson)
	}

	if state.game != nil {
		state.game->terminate()
	}
}

Editor_CheckGameProcess :: proc(state: ^EditorState) {
	if !state.gameProcessRunning do return
	pState, err := os.process_wait(state.gameProcess, 0)
	if err == .Timeout {
		// Child is still actively running
		return
	}
	state.gameProcessRunning = false
	Editor_Log(state, .Info, "Game process exited (exit code: %d)", pState.exit_code)
}

// Editor_PlayGameProcess toggles the game: stop if running, else Play the
// project (saving and rebuilding first as needed, see playtest.odin).
Editor_PlayGameProcess :: proc(state: ^EditorState, mode: Play_Mode = .Project) {
	if state.gameProcessRunning {
		Editor_StopGameProcess(state)
		return
	}
	Editor_PlayRequest(state, mode)
}

Editor_StopGameProcess :: proc(state: ^EditorState) {
	if !state.gameProcessRunning do return
	_ = os.process_terminate(state.gameProcess)
	time.sleep(50 * time.Millisecond)
	_, err := os.process_wait(state.gameProcess, 0)
	if err == .Timeout {
		_ = os.process_kill(state.gameProcess)
	}
	state.gameProcessRunning = false
	Editor_Log(state, .Info, "Game process stopped.")
}

Editor_Log :: proc(state: ^EditorState, level: LogLevel, format: string, args: ..any) {
	msg := fmt.tprintf(format, ..args)
	now := time.now()
	h, m, s := time.clock(now)
	timeStr := fmt.tprintf("%02d:%02d:%02d", h, m, s)

	append(&state.logs, LogEntry{
		time    = strings.clone(timeStr),
		level   = level,
		message = strings.clone(msg),
	})

	if len(state.logs) > 500 {
		old := pop_front(&state.logs)
		delete(old.time)
		delete(old.message)
	}
}

Editor_RegisterBuiltinComponents :: proc(state: ^EditorState) {
	append(&state.components, ComponentDef{
		name        = strings.clone("Player Spaceship"),
		category    = strings.clone("Gameplay"),
		description = strings.clone("Inertial Asteroids ship controller with steer, thrust, and screen wrap"),
		jsonSnippet = strings.clone(`{
  "type": "TextureNode",
  "name": "PlayerSpaceship",
  "position": [640.0, 360.0],
  "scale": [0.45, 0.45],
  "layer": 2,
  "texture": { "path": "textures/Spaceship_1.png" },
  "script": {
    "path": "assets/scripts/player_ship.lua",
    "properties": { "ship_name": "Vanguard-Prime", "thrust_power": 520.0, "rotation_speed": 210.0, "drag": 0.985, "max_speed": 650.0 }
  }
}`),
	})

	append(&state.components, ComponentDef{
		name        = strings.clone("Large Asteroid"),
		category    = strings.clone("Physics"),
		description = strings.clone("Box2D zero-gravity dynamic body with tumbling & drift vector"),
		jsonSnippet = strings.clone(`{
  "type": "DynamicBodyNode",
  "name": "AsteroidLarge",
  "position": [200.0, 200.0],
  "scale": [0.65, 0.65],
  "layer": 1,
  "texture": { "path": "textures/Asteroid_1.png" },
  "physics": {
    "gravity_scale": 0.0,
    "shape": { "type": "box", "size": [110.0, 110.0], "density": 1.2, "friction": 0.2, "restitution": 0.8 }
  },
  "script": {
    "path": "assets/scripts/asteroid.lua",
    "properties": { "asteroid_name": "Asteroid-Large", "tumble_speed": 18.0, "drift_vx": 35.0, "drift_vy": 22.0 }
  }
}`),
	})

	append(&state.components, ComponentDef{
		name        = strings.clone("Medium Asteroid"),
		category    = strings.clone("Physics"),
		description = strings.clone("Box2D zero-gravity dynamic body with rapid counter-tumbling"),
		jsonSnippet = strings.clone(`{
  "type": "DynamicBodyNode",
  "name": "AsteroidMedium",
  "position": [400.0, 200.0],
  "scale": [0.50, 0.50],
  "layer": 1,
  "texture": { "path": "textures/Asteroid_2.png" },
  "physics": {
    "gravity_scale": 0.0,
    "shape": { "type": "box", "size": [80.0, 80.0], "density": 1.0, "friction": 0.2, "restitution": 0.85 }
  },
  "script": {
    "path": "assets/scripts/asteroid.lua",
    "properties": { "asteroid_name": "Asteroid-Medium", "tumble_speed": -28.0, "drift_vx": -40.0, "drift_vy": 28.0 }
  }
}`),
	})

	append(&state.components, ComponentDef{
		name        = strings.clone("Cosmic Starfield"),
		category    = strings.clone("Effects"),
		description = strings.clone("Deep space drifting particle starfield emitter"),
		jsonSnippet = strings.clone(`{
  "type": "ParticleEmitterNode",
  "name": "CosmicStarfield",
  "position": [640.0, 360.0],
  "scale": [1.0, 1.0],
  "layer": 0,
  "particles": { "amount": 100, "lifetime": 4.5, "velocity": 50.0, "continuous": true, "emitting": true }
}`),
	})

	append(&state.components, ComponentDef{
		name        = strings.clone("Orbiting Drone"),
		category    = strings.clone("Gameplay"),
		description = strings.clone("Node with orbiting_drone.lua script attached and exported properties"),
		jsonSnippet = strings.clone(`{
  "type": "Node",
  "name": "OrbitingDrone",
  "position": [640.0, 360.0],
  "scale": [0.55, 0.55],
  "texture": { "path": "textures/Spaceship_2.png" },
  "script": {
    "path": "assets/scripts/orbiting_drone.lua",
    "properties": { "orbit_radius": 160.0, "rotation_speed": 2.2, "drone_name": "DroneUnit" }
  }
}`),
	})

	append(&state.components, ComponentDef{
		name        = strings.clone("Physics Crate"),
		category    = strings.clone("Physics"),
		description = strings.clone("Dynamic Box2D rigid body box collider with mass & friction"),
		jsonSnippet = strings.clone(`{
  "type": "DynamicBodyNode",
  "name": "PhysicsCrate",
  "position": [0.0, 0.0],
  "scale": [1.0, 1.0],
  "physics": {
    "gravity_scale": 1.0,
    "shape": { "type": "box", "size": [64.0, 64.0], "density": 1.5, "friction": 0.4, "restitution": 0.2 }
  }
}`),
	})

	append(&state.components, ComponentDef{
		name        = strings.clone("Static Platform"),
		category    = strings.clone("Physics"),
		description = strings.clone("Static collision barrier that objects collide against"),
		jsonSnippet = strings.clone(`{
  "type": "StaticBodyNode",
  "name": "StaticPlatform",
  "position": [0.0, 0.0],
  "scale": [1.0, 1.0],
  "physics": {
    "shape": { "type": "box", "size": [400.0, 32.0], "density": 0.0, "friction": 0.8, "restitution": 0.0 }
  }
}`),
	})

	append(&state.components, ComponentDef{
		name        = strings.clone("Trigger Sensor Zone"),
		category    = strings.clone("Physics"),
		description = strings.clone("Area sensor detecting overlapping bodies without physical collision"),
		jsonSnippet = strings.clone(`{
  "type": "AreaNode",
  "name": "TriggerZone",
  "position": [0.0, 0.0],
  "area": {
    "shape": { "type": "box", "size": [128.0, 128.0] }
  }
}`),
	})
}
