package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import rl "vendor:raylib"

// ============================================================================
// New-project templates (the Welcome window; File > New Project uses Empty):
//   Empty       a camera
//   Platformer  a player (CharacterMover: arrows / A-D to run, Space to jump),
//               ground and one-way platforms, a camera that follows
//   Top-down    a player moved by a script with the move_* input actions
//   Menu        a title and a Play button that opens the game scene
// Images are plain placeholder shapes, generated so the project is complete.
// ============================================================================

Project_Template :: enum {
	Empty,
	Platformer,
	TopDown,
	Menu,
}

Template_Info :: struct {
	name, icon, description: string,
}

PROJECT_TEMPLATES := [Project_Template]Template_Info {
	.Empty      = {"Empty", ICON_FA_FILE, "A scene with a camera."},
	.Platformer = {"Platformer", ICON_FA_PERSON_RUNNING, "A player that runs and jumps (built-in character controller), ground, one-way platforms, a camera that follows."},
	.TopDown    = {"Top-down", ICON_FA_ARROWS_UP_DOWN_LEFT_RIGHT, "A player moved in four directions by a short Lua script."},
	.Menu       = {"Menu", ICON_FA_HAND_POINTER, "A title screen whose Play button opens the game scene."},
}

@(private = "file")
write_text :: proc(dir, rel, text: string) -> bool {
	p, _ := filepath.join({dir, rel}, context.temp_allocator)
	_ = os.make_directory_all(filepath.dir(p, context.temp_allocator))
	return os.write_entire_file(p, transmute([]u8)text) == nil
}

// write_box_png: a placeholder image - a filled rectangle with a darker edge.
@(private = "file")
write_box_png :: proc(dir, rel: string, w, h: i32, col: rl.Color) {
	p, _ := filepath.join({dir, rel}, context.temp_allocator)
	_ = os.make_directory_all(filepath.dir(p, context.temp_allocator))
	img := rl.GenImageColor(w, h, col)
	edge := rl.Color{u8(f32(col.r) * 0.6), u8(f32(col.g) * 0.6), u8(f32(col.b) * 0.6), 255}
	rl.ImageDrawRectangleLines(&img, {0, 0, f32(w), f32(h)}, 2, edge)
	rl.ExportImage(img, strings.clone_to_cstring(p, context.temp_allocator))
	rl.UnloadImage(img)
}

@(private = "file")
CAMERA_JSON :: `{"type": "CameraNode", "name": "Camera", "position": [640, 360], "properties": {"isCurrent": true}}`

// Project_CreateFromTemplate makes a project folder (project.json, folders,
// scenes, scripts, images). False when `dir` already holds a project.
Project_CreateFromTemplate :: proc(dir, name: string, tmpl: Project_Template) -> bool {
	pj, _ := filepath.join({dir, "project.json"}, context.temp_allocator)
	if os.is_file(pj) do return false
	for sub in ([]string{"scenes", "scripts", "textures", "audio", "components", "levels"}) {
		p, _ := filepath.join({dir, sub}, context.temp_allocator)
		_ = os.make_directory_all(p)
	}
	cfg, _ := e.Project_ParseConfig(transmute([]u8)string("{}"), context.temp_allocator)
	cfg.name = name
	cfg.windowTitle = name
	cfg.initialScene = "scenes/main.scene.json"
	cfg.gravity = {0, 980}
	append(&cfg.scenes, "scenes/main.scene.json")

	ok := true
	switch tmpl {
	case .Empty:
		ok = write_text(dir, "scenes/main.scene.json", fmt.tprintf(`{{"name": "main", "root": {{"type": "Node", "name": "root", "children": [%s]}}}}`, CAMERA_JSON))
	case .Platformer:
		write_box_png(dir, "textures/player.png", 32, 48, {92, 141, 255, 255})
		write_box_png(dir, "textures/ground.png", 1280, 40, {74, 160, 96, 255})
		write_box_png(dir, "textures/platform.png", 200, 16, {150, 120, 80, 255})
		ok = write_text(dir, "scenes/main.scene.json", `{"name": "main", "background": [24, 28, 40, 255], "root": {"type": "Node", "name": "root", "children": [
  {"type": "CameraNode", "name": "Camera", "position": [640, 360], "follow": "../Player", "properties": {"isCurrent": true}},
  {"type": "StaticBodyNode", "name": "Ground", "position": [640, 680],
   "shapes": [{"type": "Box", "size": [1280, 40]}],
   "children": [{"type": "TextureNode", "name": "Sprite", "texture": "textures/ground.png"}]},
  {"type": "StaticBodyNode", "name": "Platform", "position": [420, 540], "properties": {"oneWay": true},
   "shapes": [{"type": "Box", "size": [200, 16]}],
   "children": [{"type": "TextureNode", "name": "Sprite", "texture": "textures/platform.png"}]},
  {"type": "StaticBodyNode", "name": "Platform2", "position": [820, 420], "properties": {"oneWay": true},
   "shapes": [{"type": "Box", "size": [200, 16]}],
   "children": [{"type": "TextureNode", "name": "Sprite", "texture": "textures/platform.png"}]},
  {"type": "CharacterMoverNode", "name": "Player", "position": [200, 600],
   "properties": {"radius": 16, "height": 48, "enableKeyboardInput": true},
   "children": [{"type": "TextureNode", "name": "Sprite", "texture": "textures/player.png"}]}
]}}`)
	case .TopDown:
		cfg.gravity = {0, 0}
		write_box_png(dir, "textures/player.png", 32, 32, {92, 141, 255, 255})
		write_box_png(dir, "textures/rock.png", 64, 64, {120, 110, 100, 255})
		ok = write_text(dir, "scripts/player.lua", `---@class Player
local Player = {}

Player.properties = {
    speed = { type = "float", default = 220, min = 20, max = 1000, label = "Speed" },
}

-- Arrows / WASD (the project's move_* input actions).
function Player:update(dt)
    local dx, dy = 0, 0
    if Input.is_action_pressed("move_left") then dx = dx - 1 end
    if Input.is_action_pressed("move_right") then dx = dx + 1 end
    if Input.is_action_pressed("move_up") then dy = dy - 1 end
    if Input.is_action_pressed("move_down") then dy = dy + 1 end
    if dx ~= 0 and dy ~= 0 then dx, dy = dx * 0.7071, dy * 0.7071 end
    local x, y = self.node:get_position()
    self.node:set_position(x + dx * self.speed * dt, y + dy * self.speed * dt)
end

return Player
`) && write_text(dir, "scenes/main.scene.json", `{"name": "main", "background": [30, 36, 30, 255], "root": {"type": "Node", "name": "root", "children": [
  {"type": "CameraNode", "name": "Camera", "position": [640, 360], "follow": "../Player", "properties": {"isCurrent": true}},
  {"type": "TextureNode", "name": "Rock", "position": [420, 260], "texture": "textures/rock.png"},
  {"type": "TextureNode", "name": "Rock2", "position": [880, 480], "texture": "textures/rock.png"},
  {"type": "TextureNode", "name": "Player", "position": [640, 360], "texture": "textures/player.png", "script": {"path": "scripts/player.lua"}}
]}}`)
	case .Menu:
		cfg.initialScene = "scenes/menu.scene.json"
		clear(&cfg.scenes)
		append(&cfg.scenes, "scenes/menu.scene.json", "scenes/main.scene.json")
		ok = write_text(dir, "scripts/play_button.lua", `---@class PlayButton
local PlayButton = {}

-- The button's "clicked" event.
function PlayButton:on_clicked()
    Scene.change_scene("main", { transition = "fade", duration = 0.4 })
end

return PlayButton
`) && write_text(dir, "scenes/menu.scene.json", fmt.tprintf(`{{"name": "menu", "background": [18, 20, 30, 255], "root": {{"type": "Node", "name": "root", "children": [
  %s,
  {{"type": "TextNode", "name": "Title", "position": [640, 260], "properties": {{"text": "%s", "fontSize": 64, "centered": true}}}},
  {{"type": "UIButtonNode", "name": "PlayButton", "position": [560, 380], "layer": 7, "properties": {{"text": "Play", "size": [160, 48]}}, "script": {{"path": "scripts/play_button.lua"}}}}
]}}}}`, CAMERA_JSON, name)) && write_text(dir, "scenes/main.scene.json", fmt.tprintf(`{{"name": "main", "root": {{"type": "Node", "name": "root", "children": [
  %s,
  {{"type": "TextNode", "name": "Hello", "position": [640, 360], "properties": {{"text": "The game starts here", "fontSize": 40, "centered": true}}}}
]}}}}`, CAMERA_JSON))
	}
	return ok && e.Project_SaveConfigToFile(dir, &cfg)
}
