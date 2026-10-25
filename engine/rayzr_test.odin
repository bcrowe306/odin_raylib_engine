package engine

import "base:runtime"
import "core:c"
import "core:fmt"
import os "osx"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import lua "lua54"

// ============================================================================
// RAYZR Package Container & Project Format Unit Tests
// ============================================================================

@(test)
test_rayzr_package_create_and_read :: proc(t: ^testing.T) {
	tempPath := "test_sample_package.rayzr"
	defer {
		if os.exists(tempPath) do os.remove(tempPath)
	}

	// 1. Prepare files: one small, one large repetitive string (deflates), one binary slice
	smallText := "Hello, RAYZR portable package format!"
	largeTextSb: strings.Builder
	strings.builder_init(&largeTextSb, context.temp_allocator)
	for _ in 0..<50 {
		strings.write_string(&largeTextSb, "{\"type\": \"Node\", \"position\": [100.0, 200.0], \"visible\": true}\n")
	}
	largeText := strings.to_string(largeTextSb)

	binData := []u8{0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04}

	sources := []RayzrFileSource{
		{archivePath = "project.json", data = transmute([]u8)smallText},
		{archivePath = "scenes/main.scene.json", data = transmute([]u8)largeText},
		{archivePath = "assets/data.bin", data = binData},
	}

	createOk := RayzrPackage_CreateFromFiles(sources, tempPath, true)
	testing.expect(t, createOk, "RayzrPackage_CreateFromFiles should succeed")

	// 2. Open archive from disk
	pkg, openOk := RayzrPackage_Open(tempPath)
	testing.expect(t, openOk, "RayzrPackage_Open should succeed")
	defer RayzrPackage_Close(pkg)

	testing.expect_value(t, len(pkg.entries), 3)
	testing.expect(t, RayzrPackage_HasFile(pkg, "project.json"), "Should contain project.json")
	testing.expect(t, RayzrPackage_HasFile(pkg, "scenes/main.scene.json"), "Should contain scenes/main.scene.json")
	testing.expect(t, RayzrPackage_HasFile(pkg, "assets/data.bin"), "Should contain assets/data.bin")

	// Verify small file
	readSmall, ok1 := RayzrPackage_ReadString(pkg, "project.json")
	testing.expect(t, ok1, "Reading project.json should succeed")
	testing.expect_value(t, readSmall, smallText)
	delete(readSmall)

	// Verify large compressed file
	readLarge, ok2 := RayzrPackage_ReadString(pkg, "scenes/main.scene.json")
	testing.expect(t, ok2, "Reading scenes/main.scene.json should succeed")
	testing.expect_value(t, readLarge, largeText)
	delete(readLarge)

	largeEntry := pkg.entries["scenes/main.scene.json"]
	testing.expect_value(t, largeEntry.compression, RayzrCompression.Deflate)
	testing.expect(t, largeEntry.compressedSize < largeEntry.uncompressedSize, "Compressed size should be strictly smaller")

	// Verify binary data
	readBin, ok3 := RayzrPackage_ReadFile(pkg, "assets/data.bin")
	testing.expect(t, ok3, "Reading assets/data.bin should succeed")
	testing.expect_value(t, len(readBin), len(binData))
	for b, i in binData {
		testing.expect_value(t, readBin[i], b)
	}
	delete(readBin)
}

@(test)
test_rayzr_package_memory :: proc(t: ^testing.T) {
	tempPath := "test_memory_package.rayzr"
	defer {
		if os.exists(tempPath) do os.remove(tempPath)
	}

	sources := []RayzrFileSource{
		{archivePath = "hello.txt", data = transmute([]u8)string("In-memory test payload")},
	}
	RayzrPackage_CreateFromFiles(sources, tempPath, false)

	data, err := os.read_entire_file(tempPath, context.allocator)
	testing.expect(t, err == nil, "Reading temp file should succeed")

	pkg, ok := RayzrPackage_OpenFromMemory(data)
	testing.expect(t, ok, "RayzrPackage_OpenFromMemory should succeed")
	defer RayzrPackage_Close(pkg)

	readStr, readOk := RayzrPackage_ReadString(pkg, "hello.txt")
	testing.expect(t, readOk, "Should read hello.txt")
	testing.expect_value(t, readStr, "In-memory test payload")
	delete(readStr)
}

@(test)
test_project_config_serialization_roundtrip :: proc(t: ^testing.T) {
	rawJson := `
{
  "name": "Super Space Game",
  "version": "2.1.0",
  "initial_scene": "scenes/level1.scene.json",
  "window": {
    "title": "Super Space Window",
    "width": 1920,
    "height": 1080,
    "virtual_width": 1280.0,
    "virtual_height": 720.0,
    "target_fps": 120
  },
  "physics": {
    "gravity": [0.0, 500.0]
  },
  "scenes": [
    "scenes/level1.scene.json",
    "scenes/level2.scene.json"
  ]
}
`
	cfg, ok := Project_ParseConfig(transmute([]u8)rawJson)
	testing.expect(t, ok, "Project_ParseConfig should parse successfully")
	defer ProjectConfig_Destroy(&cfg)

	testing.expect_value(t, cfg.name, "Super Space Game")
	testing.expect_value(t, cfg.version, "2.1.0")
	testing.expect_value(t, cfg.initialScene, "scenes/level1.scene.json")
	testing.expect_value(t, cfg.windowTitle, "Super Space Window")
	testing.expect_value(t, cfg.windowWidth, 1920)
	testing.expect_value(t, cfg.windowHeight, 1080)
	testing.expect_value(t, cfg.virtualWidth, 1280.0)
	testing.expect_value(t, cfg.virtualHeight, 720.0)
	testing.expect_value(t, cfg.targetFPS, 120)
	testing.expect_value(t, cfg.gravity.x, f32(0.0))
	testing.expect_value(t, cfg.gravity.y, f32(500.0))
	testing.expect_value(t, len(cfg.scenes), 2)

	// Serialize back to JSON and parse again
	serialized := Project_SerializeToJSON(&cfg)
	defer delete(serialized)

	cfgRoundtrip, ok2 := Project_ParseConfig(transmute([]u8)serialized)
	testing.expect(t, ok2, "Roundtrip Project_ParseConfig should succeed")
	defer ProjectConfig_Destroy(&cfgRoundtrip)

	testing.expect_value(t, cfgRoundtrip.name, "Super Space Game")
	testing.expect_value(t, cfgRoundtrip.windowWidth, 1920)
	testing.expect_value(t, cfgRoundtrip.gravity.y, f32(500.0))
}

@(test)
test_scene_json_instantiation_and_serialization :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()

	scene := game->createScene("TestJSONScene", true, nil)
	testing.expect(t, scene != nil, "Scene creation should succeed")

	sceneJson := `
{
  "name": "TestJSONScene",
  "draw_bounds": true,
  "camera": {
    "target_position": [640.0, 360.0],
    "zoom": 1.5
  },
  "root": {
    "type": "Node",
    "name": "SceneRoot",
    "children": [
      {
        "type": "DynamicBodyNode",
        "name": "CratePhysicsNode",
        "position": [300.0, 400.0],
        "scale": [1.0, 1.0],
        "rotation": 15.0,
        "enabled": true,
        "visible": true,
        "physics": {
          "gravity_scale": 1.0,
          "shape": {
            "type": "box",
            "size": [64.0, 64.0],
            "density": 2.0,
            "friction": 0.4
          }
        }
      },
      {
        "type": "AreaNode",
        "name": "TriggerZone",
        "position": [500.0, 400.0],
        "area": {
          "shape": {
            "type": "box",
            "size": [100.0, 100.0]
          }
        }
      }
    ]
  }
}
`
	instOk := Scene_InstantiateFromJSON(scene, transmute([]u8)sceneJson, &game.gameContext)
	testing.expect(t, instOk, "Scene_InstantiateFromJSON should succeed")
	testing.expect(t, scene.drawBounds, "Scene drawBounds should be true")
	testing.expect(t, scene.camera != nil, "Scene camera should be initialized")
	testing.expect_value(t, scene.camera.targetZoom, f32(1.5))

	// Find created nodes
	crateNode := Scene_FindNodeByName(scene, "CratePhysicsNode")
	testing.expect(t, crateNode != nil, "CratePhysicsNode should exist")
	testing.expect_value(t, crateNode.position.x, f32(300.0))
	testing.expect_value(t, crateNode.position.y, f32(400.0))
	testing.expect_value(t, crateNode.rotation, f32(15.0))

	triggerNode := Scene_FindNodeByName(scene, "TriggerZone")
	testing.expect(t, triggerNode != nil, "TriggerZone should exist")

	// Serialize back to JSON string
	outJson := Scene_SerializeToJSON(scene)
	defer delete(outJson)

	testing.expect(t, strings.contains(outJson, "TestJSONScene"), "Output JSON should contain scene name")
	testing.expect(t, strings.contains(outJson, "CratePhysicsNode"), "Output JSON should contain CratePhysicsNode")
	testing.expect(t, strings.contains(outJson, "TriggerZone"), "Output JSON should contain TriggerZone")
}

@(test)
test_project_load_from_directory_and_rayzr :: proc(t: ^testing.T) {
	tempDir := "temp_test_project"
	tempRayzr := "temp_test_project.rayzr"
	defer {
		if os.exists(tempRayzr) do os.remove(tempRayzr)
		if os.exists(tempDir) do os.remove_all(tempDir)
	}

	// 1. Setup mock directory structure on disk
	pScenes, _ := filepath.join({tempDir, "scenes"}, context.temp_allocator)
	pScripts, _ := filepath.join({tempDir, "assets", "scripts"}, context.temp_allocator)
	_ = os.make_directory_all(pScenes)
	_ = os.make_directory_all(pScripts)

	projJson := `
{
  "name": "DataDrivenDemo",
  "version": "1.0.0",
  "initial_scene": "scenes/main.scene.json",
  "window": {
    "title": "Data Driven Engine Demo",
    "width": 1280,
    "height": 720,
    "virtual_width": 1280.0,
    "virtual_height": 720.0,
    "target_fps": 60
  },
  "physics": {
    "gravity": [0.0, 980.0]
  },
  "scenes": [
    "scenes/main.scene.json"
  ]
}
`
	sceneJson := `
{
  "name": "MainScene",
  "draw_bounds": false,
  "root": {
    "type": "Node",
    "name": "RootNode",
    "children": [
      {
        "type": "Node",
        "name": "SpawnPoint",
        "position": [640.0, 360.0]
      }
    ]
  }
}
`
	scriptCode := "print('Hello from data-driven project script!')\n"

	pProjFile, _ := filepath.join({tempDir, "project.json"}, context.temp_allocator)
	pSceneFile, _ := filepath.join({tempDir, "scenes", "main.scene.json"}, context.temp_allocator)
	pScriptFile, _ := filepath.join({tempDir, "assets", "scripts", "test.lua"}, context.temp_allocator)

	_ = os.write_entire_file(pProjFile, transmute([]u8)projJson)
	_ = os.write_entire_file(pSceneFile, transmute([]u8)sceneJson)
	_ = os.write_entire_file(pScriptFile, transmute([]u8)scriptCode)

	// 2. Test Game loading from directory
	{
		game := new(Game)
		InitializeGame(game)
		defer game->terminate()

		loadOk := game->loadProject(tempDir)
		testing.expect(t, loadOk, "game->loadProject from directory should succeed")
		testing.expect_value(t, game.physicsWorld.gravity.y, f32(980.0))
		testing.expect(t, game.sceneManager.currentScene != nil, "Current scene should be set")

		// Export project to .rayzr file
		exportOk := game.exportRayzr(tempDir, tempRayzr)
		testing.expect(t, exportOk, "game.exportRayzr should create package")
		testing.expect(t, os.exists(tempRayzr), "tempRayzr file should exist on disk")
	}

	// 3. Test Game loading from .rayzr archive
	{
		game2 := new(Game)
		InitializeGame(game2)
		defer game2->terminate()

		loadRayzrOk := game2->loadProject(tempRayzr)
		testing.expect(t, loadRayzrOk, "game2->loadProject from .rayzr should succeed")
		testing.expect(t, game2.assetManager.package_ != nil, "AssetManager should have package mounted")

		// Read script asset from inside mounted .rayzr archive
		txt, readOk := AssetManager_ReadFileString(&game2.assetManager, "assets/scripts/test.lua")
		testing.expect(t, readOk, "Reading script from mounted .rayzr package should succeed")
		testing.expect_value(t, txt, scriptCode)
		delete(txt)
	}
}

@(test)
test_script_project_lua_bindings :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()

	// Set project directory
	AssetManager_SetProjectDir(&game.assetManager, ".")

	luaCode := `
local sceneJson = Project.serialize_scene()
assert(type(sceneJson) == "string", "Project.serialize_scene() must return string")

-- Check has_file on existing file
local hasScript = Project.has_file("main.odin")
assert(hasScript == true, "Project.has_file('main.odin') should be true")

local content = Project.read_file("main.odin")
assert(type(content) == "string" and #content > 0, "Project.read_file('main.odin') should return content")

local missing = Project.has_file("non_existent_file_xyz.abc")
assert(missing == false, "Project.has_file should return false for nonexistent file")
`
	res := lua.L_dostring(game.scriptManager.L, strings.clone_to_cstring(luaCode, context.temp_allocator))
	testing.expect_value(t, res, auto_cast lua.OK)
}

@(test)
test_pack_demo_project_rayzr :: proc(t: ^testing.T) {
	if os.exists("assets/demo_project") {
		ok := RayzrPackage_CreateFromDirectory("assets/demo_project", "assets/demo_project.rayzr", true)
		testing.expect(t, ok, "Failed to create assets/demo_project.rayzr")

		_ = os.make_directory_all("bin")
		ok2 := RayzrPackage_CreateFromDirectory("assets/demo_project", "bin/exported_game.rayzr", true)
		testing.expect(t, ok2, "Failed to create bin/exported_game.rayzr")

		// Verify that demo_project.rayzr can be opened and contains project.json, scenes, scripts, components
		pkg, openOk := RayzrPackage_Open("assets/demo_project.rayzr")
		testing.expect(t, openOk, "Should open assets/demo_project.rayzr")
		defer RayzrPackage_Close(pkg)

		testing.expect(t, RayzrPackage_HasFile(pkg, "project.json"), "Archive should contain project.json")
		testing.expect(t, RayzrPackage_HasFile(pkg, "scenes/main.scene.json"), "Archive should contain main.scene.json")
		testing.expect(t, RayzrPackage_HasFile(pkg, "scenes/battle_arena.scene.json"), "Archive should contain battle_arena.scene.json")
		testing.expect(t, RayzrPackage_HasFile(pkg, "scripts/player_ship.lua"), "Archive should contain player_ship.lua")
		testing.expect(t, RayzrPackage_HasFile(pkg, "scripts/asteroid.lua"), "Archive should contain asteroid.lua")
	}
}

// Hidden files and folders (.rayzr/ tooling, .luarc.json, editor settings)
// aren't packaged.
@(test)
test_pack_skips_hidden_files :: proc(t: ^testing.T) {
	dir := "test_pack_hidden"
	defer os.remove_all(dir)
	_ = os.make_directory_all("test_pack_hidden/.rayzr/definitions")
	_ = os.make_directory_all("test_pack_hidden/scripts")
	_ = os.write_entire_file("test_pack_hidden/project.json", transmute([]u8)string(`{"name": "x"}`))
	_ = os.write_entire_file("test_pack_hidden/scripts/a.lua", transmute([]u8)string(`return {}`))
	_ = os.write_entire_file("test_pack_hidden/.luarc.json", transmute([]u8)string(`{}`))
	_ = os.write_entire_file("test_pack_hidden/.rayzr/definitions/engine_api.lua", transmute([]u8)string(`-- api`))
	_ = os.write_entire_file("test_pack_hidden/scripts/.DS_Store", transmute([]u8)string(`x`))
	testing.expect(t, RayzrPackage_CreateFromDirectory(dir, "test_pack_hidden.rayzr", true), "packed")
	defer os.remove("test_pack_hidden.rayzr")
	pkg, ok := RayzrPackage_Open("test_pack_hidden.rayzr")
	testing.expect(t, ok, "opens")
	if !ok do return
	defer RayzrPackage_Close(pkg)
	testing.expect(t, RayzrPackage_HasFile(pkg, "project.json") && RayzrPackage_HasFile(pkg, "scripts/a.lua"), "game files packed")
	testing.expect(t, !RayzrPackage_HasFile(pkg, ".luarc.json") && !RayzrPackage_HasFile(pkg, ".rayzr/definitions/engine_api.lua") && !RayzrPackage_HasFile(pkg, "scripts/.DS_Store"), "hidden files skipped")
}
